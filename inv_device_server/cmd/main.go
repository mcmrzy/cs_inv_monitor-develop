// Package main is the entry point for inv-device-server, the device communication service.
//
// Responsibilities:
//   - MQTT client management (connect/disconnect, command sending, OTA status relay)
//   - Kafka consumer for protocol parsing (telemetry) and alert processing
//   - Device online/offline status synchronization via Redis heartbeat
//   - Internal API for inv-api-server to query device status and send commands
//   - Model metadata loading for protocol field mapping
//
// Dependencies: PostgreSQL, Redis, MQTT Broker (EMQX), Kafka
// Listens on: :8081
// Health endpoint: GET /health (includes Redis & MQTT status)
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"inv-device-server/internal/config"
	"inv-device-server/internal/mqtt"
	"inv-device-server/internal/repository"
	"inv-device-server/internal/service"
	"inv-device-server/pkg/logger"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

var configFile string

func init() {
	flag.StringVar(&configFile, "config", "config.yaml", "config file path")
}

func main() {
	flag.Parse()

	cfg, err := config.Load(configFile)
	if err != nil {
		fmt.Printf("Failed to load config: %v\n", err)
		os.Exit(1)
	}

	// 环境变量覆盖 config.yaml 中的空值（viper 优先级问题）
	if broker := os.Getenv("MQTT_BROKER"); broker != "" {
		cfg.MQTT.Broker = broker
	}
	if port := os.Getenv("MQTT_PORT"); port != "" {
		if p, err := strconv.Atoi(port); err == nil {
			cfg.MQTT.Port = p
		}
	}
	if cid := os.Getenv("MQTT_CLIENT_ID"); cid != "" {
		cfg.MQTT.ClientID = cid
	}
	if u := os.Getenv("MQTT_USERNAME"); u != "" {
		cfg.MQTT.Username = u
	}
	if p := os.Getenv("MQTT_PASSWORD"); p != "" {
		cfg.MQTT.Password = p
	}
	if insecure := os.Getenv("MQTT_TLS_INSECURE"); insecure == "true" {
		cfg.MQTT.TLSInsecure = true
	}

	if err := cfg.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)
		os.Exit(1)
	}

	if err := setTimezone(cfg.Timezone); err != nil {
		fmt.Printf("Failed to set timezone: %v\n", err)
		os.Exit(1)
	}

	if err := logger.Init(&cfg.Log); err != nil {
		fmt.Printf("Failed to init logger: %v\n", err)
		os.Exit(1)
	}
	defer logger.Sync()

	logger.Info("Starting device server...", zap.String("timezone", cfg.Timezone))

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	db, err := initDatabase(cfg)
	if err != nil {
		logger.Fatal("Failed to init database", zap.Error(err))
	}
	defer db.Close()

	rdb, err := initRedis(cfg)
	if err != nil {
		logger.Fatal("Failed to init redis", zap.Error(err))
	}
	defer rdb.Close()

	hub := mqtt.NewHub(rdb)

	// Rebuild online device set from existing heartbeat keys (startup reconciliation)
	if err := hub.RebuildOnlineSet(ctx); err != nil {
		logger.Warn("Failed to rebuild online set on startup", zap.Error(err))
	}

	var mqttClient *mqtt.Client
	if cfg.MQTT.Broker != "" {
		mqttClient = mqtt.NewClient(&cfg.MQTT, hub)
		if err := mqttClient.Connect(ctx); err != nil {
			logger.Fatal("Failed to connect MQTT", zap.Error(err))
		}
		defer mqttClient.Disconnect()
	} else {
		logger.Info("MQTT broker not configured, skipping MQTT connection (command channel disabled)")
	}

	deviceRepo := repository.NewDeviceRepository(db)
	if cfg.Kafka.Enabled {
		schemaCtx, schemaCancel := context.WithTimeout(ctx, 5*time.Second)
		err := deviceRepo.CheckTelemetryDerivedSchema(schemaCtx)
		schemaCancel()
		if err != nil {
			logger.Fatal("Telemetry database schema is not ready", zap.Error(err))
		}
	}
	metaRepo := repository.NewMetadataRepository(deviceRepo)
	dataService := service.NewDataService(deviceRepo, metaRepo, hub, rdb, cfg.Backends.APIServer, cfg.Backends.InternalKey)

	// 注册 OTA 状态回调：MQTT 收到设备 OTA 状态后转发给 API Server
	if mqttClient != nil {
		mqttClient.SetOtaStatusHandler(dataService.HandleOTAStatus)
		mqttClient.SetOtaCmdAckHandler(dataService.HandleOTACmdAck)
		mqttClient.SetStatusChangeHandler(func(sn string, online bool) {
			status := 0
			if online {
				status = 1
				// 设备上线时，检查并下发离线命令队列中的积压命令
				go dataService.FlushPendingCommands(ctx, sn)
			}
			dataService.SyncDeviceStatus(ctx, sn, status)
		})
		mqttClient.SetCmdResultHandler(dataService.HandleCmdResult)
	}
	dataService.StartMetadataRefresh(ctx)

	// Start periodic online set reconciler (every 5 min, cleans stale entries)
	go hub.StartOnlineSetReconciler(ctx)

	if cfg.Kafka.Enabled {
		protocolParser := service.NewProtocolParser(
			cfg.Kafka.Brokers, cfg.Kafka.TelemetryTopic, "inv-device-server-parser",
			deviceRepo, metaRepo, rdb, hub, cfg.Backends.APIServer, cfg.Backends.InternalKey)
		protocolParser.Start(ctx)

		alertConsumer := service.NewAlertConsumer(
			cfg.Kafka.Brokers, cfg.Kafka.AlarmTopic, "inv-device-server-alerts", rdb, cfg.Backends.APIServer, cfg.Backends.InternalKey)
		alertConsumer.Start(ctx)

		logger.Info("Kafka consumers started (protocol parser + alert consumer)",
			zap.Strings("brokers", cfg.Kafka.Brokers),
			zap.String("telemetry_topic", cfg.Kafka.TelemetryTopic),
			zap.String("alarm_topic", cfg.Kafka.AlarmTopic))
	} else {
		logger.Warn("Kafka is disabled! No data will be processed. Enable Kafka to use EMQX Bridge mode.")
	}

	if metaRepo != nil {
		if err := metaRepo.LoadAllModels(ctx); err != nil {
			logger.Error("Failed to load model metadata", zap.Error(err))
		} else {
			logger.Info("Model metadata loaded successfully")
		}
	}

	router := setupRouter(cfg, dataService, rdb)

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	go func() {
		logger.Info("HTTP server started", zap.Int("port", cfg.Server.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("HTTP server error", zap.Error(err))
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("Server shutdown error", zap.Error(err))
	}

	cancel()

	logger.Info("Server stopped")
}

func initDatabase(cfg *config.Config) (*pgxpool.Pool, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s timezone=UTC",
		cfg.Database.Host, cfg.Database.Port, cfg.Database.User,
		cfg.Database.Password, cfg.Database.Database, cfg.Database.SSLMode,
	)

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}

	poolConfig.MaxConns = int32(cfg.Database.MaxOpenConns)
	poolConfig.MinConns = int32(cfg.Database.MaxIdleConns)
	poolConfig.MaxConnLifetime = cfg.Database.ConnMaxLifetime
	poolConfig.MaxConnIdleTime = cfg.Database.ConnMaxIdleTime

	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := pool.Ping(ctx); err != nil {
		return nil, err
	}

	logger.Info("Database connected")
	return pool, nil
}

func initRedis(cfg *config.Config) (*redis.Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", cfg.Redis.Host, cfg.Redis.Port),
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, err
	}

	logger.Info("Redis connected")
	return rdb, nil
}

func setupRouter(cfg *config.Config, dataService *service.DataService, rdb *redis.Client) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())

	router.GET("/health", func(c *gin.Context) {
		status := gin.H{"status": "ok"}
		httpStatus := http.StatusOK
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if rdb != nil {
			if err := rdb.Ping(ctx).Err(); err != nil {
				status["redis"] = "error"
				httpStatus = http.StatusServiceUnavailable
			} else {
				status["redis"] = "ok"
			}
			mqttStatus, err := rdb.Get(ctx, "mqtt:broker:health").Result()
			if err != nil || mqttStatus != "ok" {
				status["mqtt"] = "error"
				status["status"] = "degraded"
				httpStatus = http.StatusServiceUnavailable
			} else {
				status["mqtt"] = "ok"
			}
		}

		stats := dataService.GetMQTTStats()
		status["mqtt_clients"] = stats.OnlineClients

		c.JSON(httpStatus, status)
	})

	router.GET("/metrics", func(c *gin.Context) {
		stats := dataService.GetMQTTStats()
		c.Header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		c.String(http.StatusOK,
			"# HELP inv_device_mqtt_online_clients Number of online MQTT device clients\n"+
				"# TYPE inv_device_mqtt_online_clients gauge\n"+
				"inv_device_mqtt_online_clients %d\n"+
				"# HELP inv_device_mqtt_cmd_sent Total MQTT commands sent\n"+
				"# TYPE inv_device_mqtt_cmd_sent counter\n"+
				"inv_device_mqtt_cmd_sent %d\n",
			stats.OnlineClients, stats.CmdSent)
	})

	// 内部认证中间件：校验 X-Internal-Key
	internalAuth := func() gin.HandlerFunc {
		key := cfg.Backends.InternalKey
		return func(c *gin.Context) {
			if key == "" {
				c.Next()
				return
			}
			if c.GetHeader("X-Internal-Key") != key {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
				return
			}
			c.Next()
		}
	}

	api := router.Group("/api/v1").Use(internalAuth())
	{
		api.GET("/device/:sn/online", func(c *gin.Context) {
			sn := c.Param("sn")
			online := dataService.IsDeviceOnline(sn)
			c.JSON(http.StatusOK, gin.H{
				"sn":     sn,
				"online": online,
			})
		})

		api.GET("/device/:sn/data", func(c *gin.Context) {
			ctx := c.Request.Context()
			sn := c.Param("sn")

			data, err := dataService.GetRealtimeFromRedis(ctx, sn)
			if err != nil || data == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "device not found or no data"})
				return
			}
			c.JSON(http.StatusOK, data)
		})

		api.POST("/device/:sn/command", func(c *gin.Context) {
			sn := c.Param("sn")

			// 读取完整 body，OTA 命令需要原始 JSON 直接转发
			rawBody, err := io.ReadAll(c.Request.Body)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read body"})
				return
			}

			var req struct {
				Command string                 `json:"command"`
				Action  string                 `json:"action"`
				Params  map[string]interface{} `json:"params"`
			}
			if err := json.Unmarshal(rawBody, &req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			// OTA 命令使用 "action" 字段，兼容处理
			cmdType := req.Command
			if cmdType == "" {
				cmdType = req.Action
			}

			if !dataService.IsDeviceOnline(sn) {
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "设备离线"})
				return
			}

			if err := dataService.SendCommand(sn, cmdType, req.Params, rawBody); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}

			c.JSON(http.StatusOK, gin.H{
				"sn":      sn,
				"command": cmdType,
				"status":  "sent",
			})
		})

		api.GET("/stats/mqtt", func(c *gin.Context) {
			stats := dataService.GetMQTTStats()
			c.JSON(http.StatusOK, stats)
		})
	}

	return router
}

func setTimezone(tz string) error {
	// 统一使用 UTC 作为服务端时区, 前端根据站点 timezone 做本地化显示
	loc, err := time.LoadLocation("UTC")
	if err != nil {
		return fmt.Errorf("invalid timezone UTC: %w", err)
	}
	time.Local = loc
	os.Setenv("TZ", "UTC")
	return nil
}
