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

	"inv-api-server/internal/config"
	"inv-api-server/internal/handler"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"

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

	if err := initLogger(&cfg.Log); err != nil {
		fmt.Printf("Failed to init logger: %v\n", err)
		os.Exit(1)
	}

	logger.Info("Starting API server...", zap.String("timezone", cfg.Timezone))

	_, cancel := context.WithCancel(context.Background())
	defer cancel()

	db, err := initDatabase(cfg)
	if err != nil {
		logger.Warn("Failed to init database, running without DB", zap.Error(err))
	} else {
		defer db.Close()
	}

	rdb, err := initRedis(cfg)
	if err != nil {
		logger.Warn("Failed to init redis, running without Redis", zap.Error(err))
	} else {
		defer rdb.Close()
	}

	if db != nil && rdb != nil {
		startFullServer(cfg, db, rdb)
	} else {
		logger.Warn("Starting server in limited mode (no database)")
		startMinimalServer(cfg)
	}
}

func startFullServer(cfg *config.Config, db *pgxpool.Pool, rdb *redis.Client) {
	jwtInstance := jwt.NewJWT(&jwt.JWTConfig{
		Secret:     cfg.JWT.Secret,
		ExpireTime: cfg.JWT.ExpireTime,
		Issuer:     cfg.JWT.Issuer,
	})

	userRepo := repository.NewUserRepository(db, rdb)
	stationRepo := repository.NewStationRepository(db)
	deviceRepo := repository.NewDeviceRepository(db, rdb)
	alarmRepo := repository.NewAlarmRepository(db)
	notifyRepo := repository.NewNotifyRepository(db)

	userService := service.NewUserService(userRepo, rdb)
	jwtService := service.NewJWTService(jwtInstance)
	smsService := service.NewSMSService(rdb)
	emailService := service.NewEmailService(rdb, cfg.Email)
	stationService := service.NewStationService(stationRepo)
	deviceService := service.NewDeviceService(deviceRepo, rdb, "http://localhost:8081")
	alarmService := service.NewAlarmService(alarmRepo)
	_ = service.NewStatisticsService(deviceRepo, stationRepo)
	_ = service.NewNotifyService(notifyRepo, rdb)

	handler.SetDB(db)

	authHandler := handler.NewAuthHandler(userService, jwtService, smsService, emailService)
	stationHandler := handler.NewStationHandler(stationService, deviceService)
	weatherHandler := handler.NewWeatherHandler(stationService)
	deviceHandler := handler.NewDeviceHandler(deviceService, alarmService)
	alarmHandler := handler.NewAlarmHandler(alarmService)
	adminHandler := handler.NewAdminHandler(db, rdb, "web/admin/index.html", deviceRepo, stationRepo, userRepo, alarmRepo, notifyRepo)
	wsHandler := handler.NewWSHandler(rdb, jwtInstance)

	go runHeartbeatCheck(deviceRepo)

	router := setupRouter(cfg, jwtInstance, authHandler, stationHandler, deviceHandler, alarmHandler, adminHandler, weatherHandler)
	router.GET("/ws/device/:sn", wsHandler.DeviceRealtime)
	serve(cfg, router)
}

func runHeartbeatCheck(deviceRepo *repository.DeviceRepository) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		sns, err := deviceRepo.MarkStaleDevicesOffline(context.Background(), 180)
		if err != nil {
			logger.Error("Heartbeat check failed", zap.Error(err))
		} else if len(sns) > 0 {
			logger.Info("Marked stale devices offline", zap.Int("count", len(sns)))
			deviceRepo.SyncStationStatus(context.Background())
		}
	}
}

func startMinimalServer(cfg *config.Config) {
	router := setupRouterMinimal(cfg)
	serve(cfg, router)
}

func serve(cfg *config.Config, router *gin.Engine) {
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

	logger.Info("Server stopped")
}

func initLogger(cfg *config.LogConfig) error {
	level := "info"
	if cfg != nil && cfg.Level != "" {
		level = cfg.Level
	}
	logger.Info("Logger initialized", zap.String("level", level))
	return nil
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

	logger.Info("Database DSN", zap.String("dsn", dsn))

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}

	poolConfig.ConnConfig.Database = cfg.Database.Database
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

	var dbName string
	err = pool.QueryRow(ctx, "SELECT current_database()").Scan(&dbName)
	if err != nil {
		logger.Warn("Failed to get database name", zap.Error(err))
	} else {
		logger.Info("Database connected", zap.String("dbname", dbName))
	}

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

func setupRouter(cfg *config.Config, jwtInstance *jwt.JWT, authHandler *handler.AuthHandler, stationHandler *handler.StationHandler, deviceHandler *handler.DeviceHandler, alarmHandler *handler.AlarmHandler, adminHandler *handler.AdminHandler, weatherHandler *handler.WeatherHandler) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.CORS())

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	internal := router.Group("/api/v1/internal")
	{
		internal.POST("/device-status", handler.InternalDeviceStatus)
		internal.POST("/device-data", handler.InternalDeviceData)
		internal.POST("/device-cmd-status", handler.InternalDeviceCmdStatus)
	}

	admin := router.Group("/admin")
	{
		admin.GET("", adminHandler.Index)
		admin.GET("/api/dashboard", adminHandler.Dashboard)
		admin.GET("/api/system", adminHandler.SystemInfo)
		admin.GET("/api/devices", adminHandler.Devices)
		admin.POST("/api/devices", adminHandler.CreateDevice)
		admin.DELETE("/api/devices/:sn", adminHandler.DeleteDevice)
		admin.PUT("/api/devices/:sn", adminHandler.UpdateDevice)
		admin.GET("/api/devices/:sn/realtime", adminHandler.DeviceRealtimeData)
		admin.POST("/api/devices/:sn/command", adminHandler.DeviceCommand)
		admin.POST("/api/devices/:sn/unbind", adminHandler.UnbindDevice)
		admin.POST("/api/devices/batch", adminHandler.BatchCreateDevices)
		admin.POST("/api/devices/batch-delete", adminHandler.BatchDeleteDevices)
		admin.POST("/api/devices/cleanup-old", adminHandler.CleanupOldDevices)
		admin.GET("/api/stations", adminHandler.Stations)
		admin.POST("/api/stations", adminHandler.CreateStation)
		admin.PUT("/api/stations/:id", adminHandler.UpdateStation)
		admin.DELETE("/api/stations/:id", adminHandler.DeleteStation)
		admin.GET("/api/users", adminHandler.Users)
		admin.POST("/api/users", adminHandler.CreateUser)
		admin.PUT("/api/users/:id", adminHandler.UpdateUser)
		admin.DELETE("/api/users/:id", adminHandler.DeleteUser)
		admin.POST("/api/users/:id/toggle", adminHandler.ToggleUserStatus)
		admin.PUT("/api/users/:id/password", adminHandler.ResetUserPassword)
		admin.GET("/api/alarms", adminHandler.Alarms)
		admin.POST("/api/alarms/:id/handle", adminHandler.HandleAlarm)
		admin.GET("/api/models", adminHandler.Models)
		admin.POST("/api/models", adminHandler.CreateModel)
		admin.PUT("/api/models/:id", adminHandler.UpdateModel)
		admin.DELETE("/api/models/:id", adminHandler.DeleteModel)
		admin.POST("/api/proxy", adminHandler.ProxyAPI)
		admin.GET("/api/services", adminHandler.Services)
		admin.POST("/api/restart", adminHandler.RestartServices)
		admin.GET("/api/logs", adminHandler.Logs)
		admin.GET("/api/connections", adminHandler.Connections)
		admin.GET("/api/mqtt-stats", adminHandler.MQTTStats)
	}

	api := router.Group("/api/v1")
	{
		api.POST("/auth/login", authHandler.Login)
		api.POST("/auth/register", authHandler.Register)
		api.POST("/auth/send-code", authHandler.SendCode)
		api.POST("/auth/reset-password", authHandler.ResetPassword)
		api.POST("/auth/email-register", authHandler.EmailRegister)
		api.POST("/auth/email-login", authHandler.EmailLogin)
		api.POST("/auth/send-email-code", authHandler.SendEmailCode)

		auth := api.Group("").Use(middleware.Auth(jwtInstance))
		{
			auth.POST("/auth/logout", authHandler.Logout)
			auth.POST("/auth/change-password", authHandler.ChangePassword)
			auth.GET("/auth/profile", authHandler.GetProfile)
			auth.PUT("/auth/profile", authHandler.UpdateProfile)

			auth.POST("/stations", stationHandler.Create)
			auth.GET("/stations", stationHandler.List)
			auth.GET("/stations/summary", stationHandler.GetSummary)
			auth.GET("/stations/:id", stationHandler.GetByID)
			auth.GET("/stations/:id/weather", weatherHandler.GetStationWeather)
			auth.PUT("/stations/:id", stationHandler.Update)
			auth.DELETE("/stations/:id", stationHandler.Delete)
			auth.GET("/stations/:id/statistics", stationHandler.GetStatistics)

			auth.GET("/devices", deviceHandler.List)
			auth.GET("/devices/:sn", deviceHandler.GetDetail)
			auth.GET("/devices/:sn/realtime", deviceHandler.GetRealtimeData)
			auth.POST("/devices/bind", deviceHandler.Bind)
			auth.DELETE("/devices/:sn/unbind", deviceHandler.Unbind)
			auth.POST("/devices/:sn/control", deviceHandler.Control)
			auth.GET("/devices/:sn/params", deviceHandler.GetParams)
			auth.PUT("/devices/:sn/params", deviceHandler.UpdateParams)
			auth.GET("/devices/:sn/history", deviceHandler.GetHistory)
			auth.GET("/devices/:sn/alarms", deviceHandler.GetAlarms)
			auth.GET("/devices/:sn/statistics", deviceHandler.GetStatistics)
			auth.POST("/devices/:sn/share", deviceHandler.Share)
			auth.DELETE("/devices/:sn/share/:share_id", deviceHandler.CancelShare)
			auth.GET("/devices/:sn/shares", deviceHandler.GetShares)
			auth.POST("/devices/add-to-station", deviceHandler.AddToStation)
			auth.GET("/devices/scan/local", deviceHandler.ScanLocal)
			auth.POST("/devices/:sn/ota", deviceHandler.OTAUpgrade)
			auth.GET("/devices/:sn/ota/status", deviceHandler.GetOTAStatus)

			auth.GET("/alarms", alarmHandler.List)
			auth.GET("/alarms/:id", alarmHandler.GetByID)
			auth.PUT("/alarms/:id/handle", alarmHandler.MarkHandled)
			auth.PUT("/alarms/read", alarmHandler.MarkRead)
		}
	}

	return router
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

func setupRouterMinimal(cfg *config.Config) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.CORS())

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "db": false})
	})

	router.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusServiceUnavailable, gin.H{"code": -1, "message": "Database not available, please ensure PostgreSQL and Redis are running"})
	})

	return router
}
