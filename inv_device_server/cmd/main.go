package main

import (
	"context"
	"flag"
	"fmt"
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

	initSchema(db, cfg)

	rdb, err := initRedis(cfg)
	if err != nil {
		logger.Fatal("Failed to init redis", zap.Error(err))
	}
	defer rdb.Close()

	hub := mqtt.NewHub(rdb)

	mqttClient := mqtt.NewClient(&cfg.MQTT, hub)
	if err := mqttClient.Connect(ctx); err != nil {
		logger.Fatal("Failed to connect MQTT", zap.Error(err))
	}
	defer mqttClient.Disconnect()

	deviceRepo := repository.NewDeviceRepository(db)
	metaRepo := repository.NewMetadataRepository(deviceRepo)
	dataService := service.NewDataService(deviceRepo, metaRepo, hub, rdb)
	dataService.StartMetadataRefresh(ctx)

	if cfg.Kafka.Enabled {
		protocolParser := service.NewProtocolParser(
			cfg.Kafka.Brokers, cfg.Kafka.TelemetryTopic, "inv-device-server-parser",
			deviceRepo, metaRepo, rdb, hub)
		protocolParser.Start(ctx)

		alertConsumer := service.NewAlertConsumer(
			cfg.Kafka.Brokers, cfg.Kafka.AlarmTopic, "inv-device-server-alerts", deviceRepo)
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
	tz := cfg.Timezone
	if tz == "" {
		tz = "Asia/Shanghai"
	}
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s timezone=%s",
		cfg.Database.Host, cfg.Database.Port, cfg.Database.User,
		cfg.Database.Password, cfg.Database.Database, cfg.Database.SSLMode, tz,
	)

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}

	poolConfig.MaxConns = int32(cfg.Database.MaxOpenConns)
	poolConfig.MinConns = int32(cfg.Database.MaxIdleConns)
	poolConfig.MaxConnLifetime = cfg.Database.ConnMaxLifetime

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
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	router.GET("/metrics", func(c *gin.Context) {
		stats := dataService.GetMQTTStats()
		statsMap := map[string]interface{}{
			"mqtt_online_clients": stats.OnlineClients,
			"mqtt_cmd_sent":       stats.CmdSent,
		}
		c.JSON(http.StatusOK, statsMap)
	})

	api := router.Group("/api/v1")
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
			if err != nil {
				data, err = dataService.GetRealtimeFromDB(ctx, sn)
			}
			if err != nil || data == nil {
				c.JSON(http.StatusNotFound, gin.H{"error": "device not found or no data"})
				return
			}
			c.JSON(http.StatusOK, data)
		})

		api.POST("/device/:sn/command", func(c *gin.Context) {
			sn := c.Param("sn")

			var req struct {
				Command string                 `json:"command"`
				Params  map[string]interface{} `json:"params"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
				return
			}

			if !dataService.IsDeviceOnline(sn) {
				c.JSON(http.StatusServiceUnavailable, gin.H{"error": "设备离线"})
				return
			}

			if err := dataService.SendCommand(sn, req.Command, req.Params, ""); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}

			c.JSON(http.StatusOK, gin.H{
				"sn":      sn,
				"command": req.Command,
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

func initSchema(db *pgxpool.Pool, cfg *config.Config) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	_, err := db.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS devices (
			id BIGSERIAL PRIMARY KEY,
			sn VARCHAR(50) NOT NULL UNIQUE,
			model VARCHAR(50),
			manufacturer VARCHAR(50),
			firmware_arm VARCHAR(50),
			firmware_esp VARCHAR(50),
			device_type VARCHAR(50),
			rated_power INTEGER DEFAULT 0,
			rated_voltage INTEGER DEFAULT 0,
			rated_freq DECIMAL(5,1),
			battery_voltage DECIMAL(6,1),
			battery_type VARCHAR(50),
			cell_count INTEGER DEFAULT 0,
			status INTEGER DEFAULT 0,
			ip_address VARCHAR(50),
			city VARCHAR(50),
			user_id BIGINT DEFAULT 0,
			station_id BIGINT DEFAULT 0,
			last_online_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS device_telemetry (
			id BIGSERIAL,
			device_sn VARCHAR(50) NOT NULL,
			topic VARCHAR(200),
			data JSONB NOT NULL,
			total_active_power DECIMAL(12,2) DEFAULT 0,
			daily_energy DECIMAL(14,4) DEFAULT 0,
			work_state VARCHAR(50),
			fault_code VARCHAR(50),
			internal_temperature DECIMAL(6,1) DEFAULT 0,
			time TIMESTAMP NOT NULL DEFAULT NOW(),
			created_at TIMESTAMP NOT NULL DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_telemetry_sn_time ON device_telemetry(device_sn, time DESC);

		CREATE TABLE IF NOT EXISTS device_alarms (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			event_type VARCHAR(50),
			source VARCHAR(50),
			fault_code INTEGER,
			fault_desc VARCHAR(200),
			alarm_code INTEGER,
			trigger_info JSONB,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);
		CREATE INDEX IF NOT EXISTS idx_alarms_sn ON device_alarms(device_sn);

		CREATE TABLE IF NOT EXISTS device_cmd_logs (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			cmd VARCHAR(50),
			result VARCHAR(20),
			message VARCHAR(200),
			sent_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS device_day_data (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			data_date DATE NOT NULL,
			energy_produce DECIMAL(10,4),
			run_minutes INTEGER,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(device_sn, data_date)
		);

		CREATE TABLE IF NOT EXISTS station_day_data (
			id BIGSERIAL PRIMARY KEY,
			station_id BIGINT NOT NULL,
			data_date DATE NOT NULL,
			energy_produce DECIMAL(10,4),
			income DECIMAL(10,2),
			device_count INTEGER DEFAULT 0,
			online_count INTEGER DEFAULT 0,
			fault_count INTEGER DEFAULT 0,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(station_id, data_date)
		);
	`)
	if err != nil {
		logger.Error("Failed to init schema", zap.Error(err))
	} else {
		logger.Info("Database schema verified")
	}
}

func setTimezone(tz string) error {
	if tz == "" {
		tz = "Asia/Shanghai"
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return fmt.Errorf("invalid timezone %q: %w", tz, err)
	}
	time.Local = loc
	os.Setenv("TZ", tz)
	return nil
}

func strconvParseInt(s string, base int, bitSize int) (int64, error) {
	return strconv.ParseInt(s, base, bitSize)
}
