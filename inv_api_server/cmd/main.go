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

	if cfg.JWT.Secret == "" || cfg.JWT.Secret == "CHANGE_ME" {
		fmt.Println("FATAL: JWT_SECRET not set or using default value")
		os.Exit(1)
	}
	if cfg.Database.Password == "" {
		fmt.Println("FATAL: DB_PASSWORD not set")
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
		Secret:            cfg.JWT.Secret,
		ExpireTime:        cfg.JWT.ExpireTime,
		RefreshExpireTime: cfg.JWT.RefreshExpireTime,
		Issuer:            cfg.JWT.Issuer,
	})

	userRepo := repository.NewUserRepository(db, rdb)
	stationRepo := repository.NewStationRepository(db)
	deviceRepo := repository.NewDeviceRepository(db, rdb)
	alarmRepo := repository.NewAlarmRepository(db)
	modelRepo := repository.NewModelRepository(db)

	userService := service.NewUserService(userRepo, rdb)
	jwtService := service.NewJWTService(jwtInstance, rdb)
	smsProvider, err := service.NewSMSProvider(cfg.SMS.Provider, cfg.SMS.AccessKey, cfg.SMS.SecretKey, cfg.SMS.SignName, cfg.SMS.Template)
	if err != nil {
		logger.Warn("Failed to create SMS provider, using mock", zap.Error(err))
		smsProvider = &service.MockSMSProvider{}
	}
	smsService := service.NewSMSService(rdb, smsProvider)
	emailService := service.NewEmailService(rdb, cfg.Email)
	stationService := service.NewStationService(stationRepo)
	deviceService := service.NewDeviceService(deviceRepo, rdb, modelRepo, cfg.Backends.DeviceServer)
	alarmService := service.NewAlarmService(alarmRepo)
	modelService := service.NewModelService(modelRepo)
	rbacCache := service.NewRBACCacheService(rdb, userRepo)
	permChecker := service.NewPermChecker(rdb, userRepo)

	otaRepo := repository.NewOTARepository(db)
	otaService := service.NewOTAService(otaRepo, rdb, cfg.Backends.DeviceServer, cfg.Backends.InternalKey, cfg.Backends.ServerURL)

	authHandler := handler.NewAuthHandler(userService, jwtService, smsService, emailService, rbacCache)
	stationHandler := handler.NewStationHandler(stationService, deviceService)
	weatherHandler := handler.NewWeatherHandler(stationService)
	deviceHandler := handler.NewDeviceHandler(deviceService, alarmService)
	alarmHandler := handler.NewAlarmHandler(alarmService)
	wsHandler := handler.NewWSHandler(rdb, jwtService)
	modelHandler := handler.NewModelHandler(modelService)
	adminHandler := handler.NewAdminHandler(userRepo, modelRepo, permChecker, db, rdb)
	otaHandler := handler.NewOTAHandler(otaService)
	dashboardHandler := handler.NewDashboardHandler(db, rdb)
	alertRuleHandler := handler.NewAlertRuleHandler()
	workOrderHandler := handler.NewWorkOrderHandler()

	go runHeartbeatCheck(deviceRepo)

	router := setupRouter(cfg, &RouterDeps{
		DB:               db,
		RDB:              rdb,
		JWTInstance:      jwtInstance,
		JWTService:       jwtService,
		AuthHandler:      authHandler,
		StationHandler:   stationHandler,
		DeviceHandler:    deviceHandler,
		AlarmHandler:     alarmHandler,
		WeatherHandler:   weatherHandler,
		ModelHandler:     modelHandler,
		PermChecker:      permChecker,
		AdminHandler:     adminHandler,
		OTAHandler:       otaHandler,
		DashboardHandler: dashboardHandler,
		AlertRuleHandler: alertRuleHandler,
		WorkOrderHandler: workOrderHandler,
	})
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
	
	zapCfg := zap.NewProductionConfig()
	lvl, err := zap.ParseAtomicLevel(level)
	if err != nil {
		return err
	}
	zapCfg.Level = lvl
	zapCfg.OutputPaths = []string{"stdout"}
	zapCfg.ErrorOutputPaths = []string{"stderr"}
	
	return logger.Init(zapCfg)
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

type RouterDeps struct {
	DB               *pgxpool.Pool
	RDB              *redis.Client
	JWTInstance      *jwt.JWT
	JWTService       *service.JWTService
	AuthHandler      *handler.AuthHandler
	StationHandler   *handler.StationHandler
	DeviceHandler    *handler.DeviceHandler
	AlarmHandler     *handler.AlarmHandler
	WeatherHandler   *handler.WeatherHandler
	ModelHandler     *handler.ModelHandler
	PermChecker      *service.PermChecker
	AdminHandler     *handler.AdminHandler
	OTAHandler       *handler.OTAHandler
	DashboardHandler *handler.DashboardHandler
	AlertRuleHandler *handler.AlertRuleHandler
	WorkOrderHandler *handler.WorkOrderHandler
}

func setupRouter(cfg *config.Config, deps *RouterDeps) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.MaxMultipartMemory = 200 << 20 // 200MB
	router.Use(gin.Recovery())
	router.Use(middleware.CORS(cfg.CORS.AllowedOrigins))
	router.Use(tracingMiddleware())
	router.Use(middleware.RateLimit())

	router.GET("/health", func(c *gin.Context) {
		status := gin.H{"status": "ok"}
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if deps.DB != nil {
			if err := deps.DB.Ping(ctx); err != nil {
				status["db"] = "error"
			} else {
				status["db"] = "ok"
			}
		}
		if deps.RDB != nil {
			if err := deps.RDB.Ping(ctx).Err(); err != nil {
				status["redis"] = "error"
			} else {
				status["redis"] = "ok"
			}
		}

		c.JSON(http.StatusOK, status)
	})

	internalHandler := handler.NewInternalHandler(deps.DB, deps.RDB)

	internal := router.Group("/api/v1/internal").Use(middleware.InternalAuth())
	{
		internal.POST("/device-status", internalHandler.DeviceStatus)
		internal.POST("/device-info", internalHandler.DeviceInfo)
		internal.POST("/device-data", internalHandler.DeviceData)
		internal.POST("/device-cmd-status", internalHandler.DeviceCmdStatus)
		internal.POST("/device-alarm", internalHandler.DeviceAlarm)
		internal.POST("/ota-status", internalHandler.OTAStatus)
	}

 	// 固件文件下载（无需认证，设备直接访问 /firmware/xxx.bin）
	router.Static("/firmware", "/data/firmware")

	api := router.Group("/api/v1")
	{
		api.POST("/auth/login", deps.AuthHandler.Login)
		api.POST("/auth/register", deps.AuthHandler.Register)
		api.POST("/auth/send-code", deps.AuthHandler.SendCode)
		api.POST("/auth/reset-password", deps.AuthHandler.ResetPassword)
		api.POST("/auth/email-register", deps.AuthHandler.EmailRegister)
		api.POST("/auth/email-login", deps.AuthHandler.EmailLogin)
		api.POST("/auth/send-email-code", deps.AuthHandler.SendEmailCode)
		api.POST("/auth/refresh", deps.AuthHandler.RefreshToken)

		auth := api.Group("").Use(middleware.Auth(deps.JWTService))
		{
			auth.POST("/auth/logout", deps.AuthHandler.Logout)
			auth.POST("/auth/change-password", deps.AuthHandler.ChangePassword)
			auth.GET("/auth/profile", deps.AuthHandler.GetProfile)
			auth.PUT("/auth/profile", deps.AuthHandler.UpdateProfile)

			auth.POST("/stations", deps.StationHandler.Create)
			auth.GET("/stations", deps.StationHandler.List)
			auth.GET("/stations/summary", deps.StationHandler.GetSummary)
			auth.GET("/stations/:id", deps.StationHandler.GetByID)
			auth.GET("/stations/:id/weather", deps.WeatherHandler.GetStationWeather)
			auth.PUT("/stations/:id", deps.StationHandler.Update)
			auth.PUT("/stations/:id/assign", deps.StationHandler.Assign)
			auth.DELETE("/stations/:id", deps.StationHandler.Delete)
			auth.GET("/stations/:id/statistics", deps.StationHandler.GetStatistics)

			auth.GET("/devices", deps.DeviceHandler.List)
		auth.GET("/devices/:sn", deps.DeviceHandler.GetDetail)
		auth.GET("/devices/:sn/realtime", deps.DeviceHandler.GetRealtimeData)
		auth.POST("/devices/bind", deps.DeviceHandler.Bind)
		auth.POST("/devices/:sn/unbind", deps.DeviceHandler.Unbind)
		auth.DELETE("/devices/:sn/unbind", deps.DeviceHandler.Unbind)
		auth.DELETE("/devices/:sn", deps.DeviceHandler.DeleteDevice)
		auth.POST("/devices/:sn/control", deps.DeviceHandler.Control)
		auth.GET("/devices/:sn/commands", deps.DeviceHandler.GetCommands)
		auth.GET("/devices/:sn/commands/history", deps.DeviceHandler.GetCommands)
		auth.GET("/devices/:sn/telemetry", deps.DeviceHandler.GetTelemetry)
		auth.GET("/devices/:sn/lifecycle", deps.DeviceHandler.GetLifecycleHistory)
		auth.GET("/devices/:sn/history", deps.DeviceHandler.GetHistory)
		auth.GET("/devices/:sn/alarms", deps.DeviceHandler.GetAlarms)
		auth.GET("/devices/:sn/statistics", deps.DeviceHandler.GetStatistics)
		auth.POST("/devices/add-to-station", deps.DeviceHandler.AddToStation)
		auth.GET("/devices/scan/local", deps.DeviceHandler.ScanLocal)
		auth.GET("/devices/unbind-requests", deps.DeviceHandler.GetUnbindRequests)
		auth.POST("/devices/unbind-requests/:id/approve", deps.DeviceHandler.ApproveUnbind)
		auth.POST("/devices/unbind-requests/:id/reject", deps.DeviceHandler.RejectUnbind)

			auth.GET("/alarms", deps.AlarmHandler.List)
			auth.GET("/alarms/:id", deps.AlarmHandler.GetByID)
			auth.PUT("/alarms/:id/handle", deps.AlarmHandler.MarkHandled)
			auth.PUT("/alarms/read", deps.AlarmHandler.MarkRead)
			auth.GET("/alarms/stats", deps.AlarmHandler.GetStats)

			auth.GET("/models", deps.ModelHandler.ListModels)
		auth.POST("/models", deps.ModelHandler.CreateModel)
		auth.GET("/models/:id", deps.ModelHandler.GetModel)
		auth.PUT("/models/:id", deps.ModelHandler.UpdateModel)
		auth.DELETE("/models/:id", deps.ModelHandler.DeleteModel)
		auth.GET("/models/:id/fields", deps.ModelHandler.GetModelFields)
		auth.GET("/models/by-code/:code/fields", deps.ModelHandler.GetFieldsByModelCode)
		auth.POST("/models/:id/fields", deps.ModelHandler.CreateField)
		auth.PUT("/models/:id/fields/:fieldId", deps.ModelHandler.UpdateField)
		auth.DELETE("/models/:id/fields/:fieldId", deps.ModelHandler.DeleteField)
		auth.PUT("/models/:id/fields/batch", deps.ModelHandler.BatchUpdateFields)

		auth.GET("/dashboard/statistics", deps.DashboardHandler.GetStatistics)
		auth.GET("/dashboard/device-distribution", deps.DashboardHandler.GetDeviceDistribution)
		auth.GET("/dashboard/trend", deps.DashboardHandler.GetTrend)
		auth.GET("/dashboard/big-screen", deps.DashboardHandler.GetBigScreen)
		auth.GET("/dashboard/compare", deps.DashboardHandler.CompareDevices)

		auth.GET("/alert-rules", deps.AlertRuleHandler.List)
		auth.GET("/alert-rules/:id", deps.AlertRuleHandler.GetByID)
		auth.POST("/alert-rules", deps.AlertRuleHandler.Create)
		auth.PUT("/alert-rules/:id", deps.AlertRuleHandler.Update)
		auth.DELETE("/alert-rules/:id", deps.AlertRuleHandler.Delete)

		auth.GET("/work-orders", deps.WorkOrderHandler.List)
		auth.GET("/work-orders/:id", deps.WorkOrderHandler.GetByID)
		auth.GET("/work-orders/stats", deps.WorkOrderHandler.GetStatistics)
		auth.POST("/work-orders", deps.WorkOrderHandler.Create)
		auth.PUT("/work-orders/:id", deps.WorkOrderHandler.Update)
		auth.DELETE("/work-orders/:id", deps.WorkOrderHandler.Delete)
	}

		requireAdmin := middleware.RequirePermission(deps.PermChecker, "admin", "manage")
		adminGroup := api.Group("/admin").Use(middleware.Auth(deps.JWTService), requireAdmin)
		{
			adminGroup.GET("/users", deps.AdminHandler.ListUsers)
			adminGroup.GET("/users/:id", deps.AdminHandler.GetUser)
			adminGroup.PUT("/users/:id/role", deps.AdminHandler.UpdateUserRole)
			adminGroup.PUT("/users/:id/toggle", deps.AdminHandler.ToggleUserStatus)

			adminGroup.GET("/permissions", deps.AdminHandler.ListRolePermissions)
			adminGroup.PUT("/permissions", deps.AdminHandler.UpdatePermission)
			adminGroup.GET("/permissions/:role", deps.AdminHandler.ListRolePermissions)
			adminGroup.PUT("/permissions/:role", deps.AdminHandler.UpdateRolePermissions)
			adminGroup.POST("/permissions/:role/toggle", deps.AdminHandler.TogglePermission)

			adminGroup.GET("/models", deps.AdminHandler.ListAllModels)

			adminGroup.GET("/logs", deps.AdminHandler.GetAuditLogs)
			adminGroup.GET("/logs/export", deps.AdminHandler.ExportAuditLogs)
			adminGroup.GET("/system-health", deps.AdminHandler.GetSystemHealth)
			adminGroup.GET("/system-config", deps.AdminHandler.GetSystemConfig)
			adminGroup.PATCH("/system-config", deps.AdminHandler.UpdateSystemConfig)
			adminGroup.GET("/tenants", deps.AdminHandler.ListTenants)
			adminGroup.POST("/tenants", deps.AdminHandler.CreateTenant)
			adminGroup.PATCH("/tenants/:id", deps.AdminHandler.UpdateTenant)
			adminGroup.POST("/tenants/:id/toggle", deps.AdminHandler.ToggleTenant)
			adminGroup.GET("/metrics", deps.AdminHandler.GetMetrics)
		}

		usersGroup := api.Group("/users").Use(middleware.Auth(deps.JWTService))
	{
		usersGroup.GET("", middleware.RequirePermission(deps.PermChecker, "users", "view"), deps.AdminHandler.ListUsers)
		usersGroup.GET("/:id", deps.AdminHandler.GetUser)
		usersGroup.PUT("/:id/role", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.UpdateUserRole)
		usersGroup.PUT("/:id/toggle", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.ToggleUserStatus)
	}

		otaGroup := api.Group("/ota").Use(middleware.Auth(deps.JWTService))
		{
			// 需要权限的管理接口
			otaGroup.GET("/firmware", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListFirmware)
			otaGroup.GET("/firmware/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetFirmware)
			otaGroup.POST("/firmware", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateFirmware)
			otaGroup.DELETE("/firmware/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteFirmware)
			otaGroup.GET("/tasks", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListTasks)
			otaGroup.GET("/tasks/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetTask)
			otaGroup.GET("/tasks/:id/devices", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetTaskDevices)
			otaGroup.POST("/tasks", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateTask)
			otaGroup.POST("/tasks/:id/dispatch", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.DispatchTask)
			otaGroup.POST("/tasks/:id/notify", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.NotifyDevices)
			otaGroup.DELETE("/tasks/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteTask)

			// APP端接口（所有登录用户可访问）
			otaGroup.GET("/check/:sn", deps.OTAHandler.CheckUpdate)
			otaGroup.POST("/trigger", deps.OTAHandler.TriggerOTA)
			otaGroup.GET("/tasks/:id/progress", deps.OTAHandler.GetTaskProgress)
			otaGroup.GET("/devices/:sn/status", deps.OTAHandler.GetDeviceOTAStatus)
			otaGroup.GET("/devices/:sn/history", deps.OTAHandler.GetDeviceOTAHistory)
			otaGroup.GET("/firmwares", deps.OTAHandler.GetAllFirmware)
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
	router.Use(middleware.CORS([]string{}))

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "db": false})
	})

	router.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusServiceUnavailable, gin.H{"code": -1, "message": "Database not available, please ensure PostgreSQL and Redis are running"})
	})

	return router
}
