package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
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

	hub := mqtt.NewHub()

	mqttClient := mqtt.NewClient(&cfg.MQTT, hub)
	if err := mqttClient.Connect(ctx); err != nil {
		logger.Fatal("Failed to connect MQTT", zap.Error(err))
	}
	defer mqttClient.Disconnect()

	deviceRepo := repository.NewDeviceRepository(db)
	dataService := service.NewDataService(deviceRepo, hub, rdb)
	dataService.Start(ctx)

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
			sn := c.Param("sn")
			data := dataService.GetRealtime(sn)
			if data == nil {
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
			rated_power INTEGER DEFAULT 0,
			status INTEGER DEFAULT 0,
			firmware_version VARCHAR(50),
			hardware_version VARCHAR(50),
			mac_address VARCHAR(50),
			user_id BIGINT DEFAULT 0,
			station_id BIGINT DEFAULT 0,
			last_online_at TIMESTAMP,
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS device_realtime_data (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL UNIQUE,
			manufacturer VARCHAR(50),
			model VARCHAR(50),
			device_type_code INTEGER,
			arm_version VARCHAR(50),
			dsp_version VARCHAR(50),
			protocol_number INTEGER,
			protocol_version INTEGER,
			nominal_active_power DECIMAL(10,2),
			nominal_reactive_power DECIMAL(10,2),
			output_type SMALLINT,
			daily_power_yields DECIMAL(12,2),
			total_power_yields DECIMAL(14,2),
			total_power_yields_01 DECIMAL(14,2),
			monthly_power_yields DECIMAL(14,2),
			total_running_time INTEGER,
			daily_running_time INTEGER,
			internal_temperature DECIMAL(5,1),
			mppt_voltage JSONB,
			mppt_current JSONB,
			total_dc_power DECIMAL(10,2),
			phase_a_voltage DECIMAL(6,1),
			phase_b_voltage DECIMAL(6,1),
			phase_c_voltage DECIMAL(6,1),
			phase_a_current DECIMAL(6,2),
			phase_b_current DECIMAL(6,2),
			phase_c_current DECIMAL(6,2),
			total_active_power DECIMAL(10,2),
			total_reactive_power DECIMAL(10,2),
			total_apparent_power DECIMAL(10,2),
			power_factor DECIMAL(5,3),
			grid_frequency DECIMAL(5,2),
			work_state_1 VARCHAR(50),
			work_state_1_code INTEGER,
			work_state_2 INTEGER,
			inverter_state_1 INTEGER,
			inverter_state_2 INTEGER,
			insulation_resistance INTEGER,
			bus_voltage DECIMAL(6,1),
			negative_ground_voltage DECIMAL(6,1),
			pid_work_state INTEGER,
			pid_alarm_code INTEGER,
			country_code INTEGER,
			meter_total_power DECIMAL(10,2),
			meter_phase_a_power DECIMAL(10,2),
			meter_phase_b_power DECIMAL(10,2),
			meter_phase_c_power DECIMAL(10,2),
			load_power DECIMAL(10,2),
			daily_feed_energy DECIMAL(12,2),
			total_feed_energy DECIMAL(14,2),
			daily_grid_import DECIMAL(12,2),
			total_grid_import DECIMAL(14,2),
			string_currents JSONB,
			active_power_setting DECIMAL(10,2),
			reactive_power_setting DECIMAL(10,2),
			power_factor_setting DECIMAL(5,3),
			esp32_timestamp INTEGER,
			data_time TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS device_telemetry (
			id BIGSERIAL,
			device_sn VARCHAR(50) NOT NULL,
			model_code VARCHAR(50),
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

		CREATE TABLE IF NOT EXISTS device_cmd_logs (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			command VARCHAR(50) NOT NULL,
			status VARCHAR(20) NOT NULL,
			message VARCHAR(200),
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
		);

		CREATE INDEX IF NOT EXISTS idx_cmd_logs_sn ON device_cmd_logs(device_sn);
		CREATE INDEX IF NOT EXISTS idx_cmd_logs_created ON device_cmd_logs(created_at);

		CREATE TABLE IF NOT EXISTS device_day_data (
			id BIGSERIAL PRIMARY KEY,
			device_sn VARCHAR(50) NOT NULL,
			data_date DATE NOT NULL,
			energy_produce DECIMAL(10,4),
			energy_consume DECIMAL(10,4),
			energy_sell DECIMAL(10,4),
			energy_buy DECIMAL(10,4),
			max_power DECIMAL(10,2),
			avg_soc INTEGER,
			run_minutes INTEGER,
			income DECIMAL(10,2),
			created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(device_sn, data_date)
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
