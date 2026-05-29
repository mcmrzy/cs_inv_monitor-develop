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
	"inv-api-server/pkg/telemetry"

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
	_ = telemetry.Init("inv-api-server")
	defer telemetry.Shutdown()

	jwtInstance := jwt.NewJWT(&jwt.JWTConfig{
		Secret:     cfg.JWT.Secret,
		ExpireTime: cfg.JWT.ExpireTime,
		Issuer:     cfg.JWT.Issuer,
	})

	userRepo := repository.NewUserRepository(db, rdb)
	stationRepo := repository.NewStationRepository(db)
	deviceRepo := repository.NewDeviceRepository(db, rdb)
	alarmRepo := repository.NewAlarmRepository(db)
	modelRepo := repository.NewModelRepository(db)

	userService := service.NewUserService(userRepo, rdb)
	jwtService := service.NewJWTService(jwtInstance)
	smsService := service.NewSMSService(rdb)
	emailService := service.NewEmailService(rdb, cfg.Email)
	stationService := service.NewStationService(stationRepo)
	deviceService := service.NewDeviceService(deviceRepo, rdb, modelRepo, cfg.Backends.DeviceServer)
	alarmService := service.NewAlarmService(alarmRepo)
	modelService := service.NewModelService(modelRepo)
	rbacCache := service.NewRBACCacheService(rdb, userRepo)
	permChecker := service.NewPermChecker(rdb, userRepo)
	dataPerm := service.NewDataPermission(db)
	_ = dataPerm

	otaRepo := repository.NewOTARepository(db)
	otaService := service.NewOTAService(otaRepo, cfg.Backends.DeviceServer)

	handler.SetDB(db)

	authHandler := handler.NewAuthHandler(userService, jwtService, smsService, emailService, rbacCache)
	stationHandler := handler.NewStationHandler(stationService, deviceService)
	weatherHandler := handler.NewWeatherHandler(stationService)
	deviceHandler := handler.NewDeviceHandler(deviceService, alarmService)
	alarmHandler := handler.NewAlarmHandler(alarmService)
	wsHandler := handler.NewWSHandler(rdb, jwtInstance)
	modelHandler := handler.NewModelHandler(modelService)
	adminHandler := handler.NewAdminHandler(userRepo, permChecker)
	otaHandler := handler.NewOTAHandler(otaService)

	go runHeartbeatCheck(deviceRepo)

	router := setupRouter(cfg, jwtInstance, authHandler, stationHandler, deviceHandler, alarmHandler, weatherHandler, modelHandler, permChecker, adminHandler, otaHandler)
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

	logger.Info("Database connecting",
		zap.String("host", cfg.Database.Host),
		zap.Int("port", cfg.Database.Port),
		zap.String("database", cfg.Database.Database),
		zap.String("user", cfg.Database.User),
		zap.String("sslmode", cfg.Database.SSLMode),
	)

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

func setupRouter(cfg *config.Config, jwtInstance *jwt.JWT, authHandler *handler.AuthHandler, stationHandler *handler.StationHandler, deviceHandler *handler.DeviceHandler, alarmHandler *handler.AlarmHandler, weatherHandler *handler.WeatherHandler, modelHandler *handler.ModelHandler, permChecker *service.PermChecker, adminHandler *handler.AdminHandler, otaHandler *handler.OTAHandler) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.CORS())
	router.Use(tracingMiddleware())

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// DEPRECATED: Admin APIs migrated to NestJS backend (inv-admin-backend)
	// Only keeping internal APIs for device server communication
	// admin := router.Group("/admin")
	// {
	// 	admin.GET("", adminHandler.Index)
	// 	admin.GET("/api/dashboard", adminHandler.Dashboard)
	// 	admin.GET("/api/system", adminHandler.SystemInfo)
	// 	admin.GET("/api/devices", adminHandler.Devices)
	// 	admin.POST("/api/devices", adminHandler.CreateDevice)
	// 	admin.DELETE("/api/devices/:sn", adminHandler.DeleteDevice)
	// 	admin.PUT("/api/devices/:sn", adminHandler.UpdateDevice)
	// 	admin.GET("/api/devices/:sn/realtime", adminHandler.DeviceRealtimeData)
	// 	admin.POST("/api/devices/:sn/command", adminHandler.DeviceCommand)
	// 	admin.POST("/api/devices/:sn/unbind", adminHandler.UnbindDevice)
	// 	admin.POST("/api/devices/batch", adminHandler.BatchCreateDevices)
	// 	admin.POST("/api/devices/batch-delete", adminHandler.BatchDeleteDevices)
	// 	admin.POST("/api/devices/cleanup-old", adminHandler.CleanupOldDevices)
	// 	admin.GET("/api/stations", adminHandler.Stations)
	// 	admin.POST("/api/stations", adminHandler.CreateStation)
	// 	admin.PUT("/api/stations/:id", adminHandler.UpdateStation)
	// 	admin.DELETE("/api/stations/:id", adminHandler.DeleteStation)
	// 	admin.GET("/api/users", adminHandler.Users)
	// 	admin.POST("/api/users", adminHandler.CreateUser)
	// 	admin.PUT("/api/users/:id", adminHandler.UpdateUser)
	// 	admin.DELETE("/api/users/:id", adminHandler.DeleteUser)
	// 	admin.POST("/api/users/:id/toggle", adminHandler.ToggleUserStatus)
	// 	admin.PUT("/api/users/:id/password", adminHandler.ResetUserPassword)
	// 	admin.GET("/api/alarms", adminHandler.Alarms)
	// 	admin.POST("/api/alarms/:id/handle", adminHandler.HandleAlarm)
	// 	admin.GET("/api/models", adminHandler.Models)
	// 	admin.POST("/api/models", adminHandler.CreateModel)
	// 	admin.PUT("/api/models/:id", adminHandler.UpdateModel)
	// 	admin.DELETE("/api/models/:id", adminHandler.DeleteModel)
	// 	admin.POST("/api/proxy", adminHandler.ProxyAPI)
	// 	admin.GET("/api/services", adminHandler.Services)
	// 	admin.POST("/api/restart", adminHandler.RestartServices)
	// 	admin.GET("/api/logs", adminHandler.Logs)
	// 	admin.GET("/api/connections", adminHandler.Connections)
	// 	admin.GET("/api/mqtt-stats", adminHandler.MQTTStats)
 	// }

 	internal := router.Group("/api/v1/internal")
 	{
 		internal.POST("/device-status", handler.InternalDeviceStatus)
 		internal.POST("/device-info", handler.InternalDeviceInfo)
 		internal.POST("/device-data", handler.InternalDeviceData)
 		internal.POST("/device-cmd-status", handler.InternalDeviceCmdStatus)
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
 		auth.GET("/devices/:sn/history", deviceHandler.GetHistory)
 		auth.GET("/devices/:sn/alarms", deviceHandler.GetAlarms)
 		auth.GET("/devices/:sn/statistics", deviceHandler.GetStatistics)
 		auth.POST("/devices/add-to-station", deviceHandler.AddToStation)
 		auth.GET("/devices/scan/local", deviceHandler.ScanLocal)

			auth.GET("/alarms", alarmHandler.List)
			auth.GET("/alarms/:id", alarmHandler.GetByID)
			auth.PUT("/alarms/:id/handle", alarmHandler.MarkHandled)
			auth.PUT("/alarms/read", alarmHandler.MarkRead)

			auth.GET("/models", modelHandler.ListModels)
			auth.POST("/models", modelHandler.CreateModel)
			auth.GET("/models/:id", modelHandler.GetModel)
			auth.PUT("/models/:id", modelHandler.UpdateModel)
			auth.DELETE("/models/:id", modelHandler.DeleteModel)
			auth.GET("/models/:id/fields", modelHandler.GetModelFields)
			auth.GET("/models/by-code/:code/fields", modelHandler.GetFieldsByModelCode)
			auth.POST("/models/:id/fields", modelHandler.CreateField)
			auth.PUT("/models/:id/fields/:fieldId", modelHandler.UpdateField)
			auth.DELETE("/models/:id/fields/:fieldId", modelHandler.DeleteField)
			auth.PUT("/models/:id/fields/batch", modelHandler.BatchUpdateFields)
		}

		requireAdmin := middleware.RequirePermission(permChecker, "admin", "manage")
		adminGroup := api.Group("/admin").Use(middleware.Auth(jwtInstance), requireAdmin)
		{
			adminGroup.GET("/users", adminHandler.ListUsers)
			adminGroup.GET("/users/:id", adminHandler.GetUser)
			adminGroup.PUT("/users/:id/role", adminHandler.UpdateUserRole)
			adminGroup.PUT("/users/:id/toggle", adminHandler.ToggleUserStatus)
			adminGroup.GET("/permissions", adminHandler.ListRolePermissions)
			adminGroup.PUT("/permissions", adminHandler.UpdatePermission)
			adminGroup.GET("/models", adminHandler.ListAllModels)
		}

		usersGroup := api.Group("/users").Use(middleware.Auth(jwtInstance))
		{
			usersGroup.GET("", adminHandler.ListUsers)
			usersGroup.GET("/:id", adminHandler.GetUser)
			usersGroup.PUT("/:id/role", middleware.RequirePermission(permChecker, "users", "edit"), adminHandler.UpdateUserRole)
			usersGroup.PUT("/:id/toggle", middleware.RequirePermission(permChecker, "users", "edit"), adminHandler.ToggleUserStatus)
		}

		otaGroup := api.Group("/ota").Use(middleware.Auth(jwtInstance), middleware.RequirePermission(permChecker, "ota", "view"))
		{
			otaGroup.GET("/firmware", otaHandler.ListFirmware)
			otaGroup.GET("/firmware/:id", otaHandler.GetFirmware)
			otaGroup.POST("/firmware", middleware.RequirePermission(permChecker, "ota", "create"), otaHandler.CreateFirmware)
			otaGroup.DELETE("/firmware/:id", middleware.RequirePermission(permChecker, "ota", "delete"), otaHandler.DeleteFirmware)
			otaGroup.GET("/tasks", otaHandler.ListTasks)
			otaGroup.GET("/tasks/:id", otaHandler.GetTask)
			otaGroup.POST("/tasks", middleware.RequirePermission(permChecker, "ota", "create"), otaHandler.CreateTask)
			otaGroup.POST("/tasks/:id/dispatch", middleware.RequirePermission(permChecker, "ota", "control"), otaHandler.DispatchTask)
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

func tracingMiddleware() gin.HandlerFunc {
	spanFn := telemetry.GinMiddleware("inv-api-server")
	return func(c *gin.Context) {
		ctx, end := spanFn(c.Request.Context(), c.Request.Method, c.FullPath())
		c.Request = c.Request.WithContext(ctx)
		c.Next()
		end(c.Writer.Status())
	}
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
