// Package main is the entry point for inv-api-server, the user-facing REST API service.
//
// Responsibilities:
//   - User authentication (login/register/JWT refresh, SMS & email verification)
//   - Station & device CRUD, binding, and real-time data queries
//   - Alarm management (list/acknowledge/ignore/clear)
//   - OTA firmware & upgrade task management
//   - Dashboard statistics, WebSocket real-time push, SSE notifications
//   - RBAC-based admin endpoints (user/role/permission/tenant management)
//
// Dependencies: PostgreSQL (primary store), Redis (cache/heartbeat/pubsub), inv-device-server (internal)
// Listens on: :8080 (configurable via server.port)
// Health endpoint: GET /health
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"runtime/debug"
	"strings"
	"syscall"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/internal/handler"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/migration"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/telemetry"
	"inv-api-server/pkg/timezone"

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

	if err := cfg.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "[FATAL] %v\n", err)
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

		// 在服务器启动前执行数据库自动迁移
		if cfg.Migration.AutoRun {
			logger.Info("Running database migrations...",
				zap.String("dir", cfg.Migration.Dir),
				zap.String("schema_file", cfg.Migration.SchemaFile))
			if err := migration.Run(context.Background(), db, cfg.Migration.Dir, cfg.Migration.SchemaFile); err != nil {
				logger.Error("Database migration failed, server will start anyway — check /health",
					zap.Error(err))
			}
		}
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
	deviceService := service.NewDeviceService(deviceRepo, rdb, modelRepo, cfg.Backends.DeviceServer, cfg.Backends.InternalKey)
	alarmService := service.NewAlarmService(alarmRepo)
	modelService := service.NewModelService(modelRepo)
	rbacCache := service.NewRBACCacheService(rdb, userRepo)
	permChecker := service.NewPermChecker(rdb, userRepo)

	otaRepo := repository.NewOTARepository(db)
	otaService := service.NewOTAService(otaRepo, rdb, cfg.Backends.DeviceServer, cfg.Backends.InternalKey, cfg.Backends.ServerURL)

	authHandler := handler.NewAuthHandler(userService, jwtService, smsService, emailService, rbacCache)
	stationHandler := handler.NewStationHandler(stationService, deviceService)
	weatherHandler := handler.NewWeatherHandler(stationService, cfg.Backends.WeatherAPI, cfg.Backends.AmapAPIKey, cfg.Backends.WeatherSource)
	deviceHandler := handler.NewDeviceHandler(deviceService, alarmService)
	alarmHandler := handler.NewAlarmHandler(alarmService)
	notificationHandler := handler.NewNotificationHandler(db)
	wsHandler := handler.NewWSHandler(rdb, jwtService)
	modelHandler := handler.NewModelHandler(modelService)
	adminHandler := handler.NewAdminHandler(userRepo, modelRepo, permChecker, db, rdb)
	otaHandler := handler.NewOTAHandler(otaService)
	dashboardHandler := handler.NewDashboardHandler(db, rdb)
	alertRuleHandler := handler.NewAlertRuleHandler()
	workOrderHandler := handler.NewWorkOrderHandler()

	heartbeatDone := make(chan struct{})
	defer close(heartbeatDone)
	// 事件驱动：监听 Redis Keyspace Notification，心跳 key 过期时立即标记设备离线
	go runHeartbeatExpiryListener(rdb, deviceRepo, heartbeatDone)
	// 兜底：每 5 分钟全量扫描一次，处理监听器可能遗漏的情况
	go runHeartbeatCheck(deviceRepo, heartbeatDone)

	// OTA 升级超时清理：每 5 分钟扫描卡住的升级记录并更新关联任务统计
	go runOTATimeoutCleanup(db, heartbeatDone)

	router := setupRouter(cfg, &RouterDeps{
		DB:                  db,
		RDB:                 rdb,
		JWTInstance:         jwtInstance,
		JWTService:          jwtService,
		AuthHandler:         authHandler,
		StationHandler:      stationHandler,
		DeviceHandler:       deviceHandler,
		AlarmHandler:        alarmHandler,
		NotificationHandler: notificationHandler,
		WeatherHandler:      weatherHandler,
		ModelHandler:        modelHandler,
		PermChecker:         permChecker,
		AdminHandler:        adminHandler,
		OTAHandler:          otaHandler,
		OTAService:          otaService,
		DashboardHandler:    dashboardHandler,
		AlertRuleHandler:    alertRuleHandler,
		WorkOrderHandler:    workOrderHandler,
	})
	router.GET("/ws/device/:sn", wsHandler.DeviceRealtime)
	serve(cfg, router)
}

// runHeartbeatExpiryListener 监听 Redis Keyspace Notification，当 device:heartbeat:{sn} key 过期时
// 立即将设备标记为离线，实现事件驱动的离线检测，延迟从分钟级降到秒级
func runHeartbeatExpiryListener(rdb *redis.Client, deviceRepo *repository.DeviceRepository, done chan struct{}) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 等待 Redis 连接就绪
	time.Sleep(2 * time.Second)

	// 启用 keyspace notifications for expired events (Ex)
	// 重试 3 次，确保配置成功
	var configErr error
	for i := 0; i < 3; i++ {
		configErr = rdb.ConfigSet(ctx, "notify-keyspace-events", "Ex").Err()
		if configErr == nil {
			break
		}
		logger.Warn("Failed to enable Redis keyspace notifications, retrying...",
			zap.Int("attempt", i+1), zap.Error(configErr))
		time.Sleep(2 * time.Second)
	}
	if configErr != nil {
		logger.Error("Failed to enable Redis keyspace notifications after 3 retries, "+
			"event-driven offline detection disabled. Please ensure Redis config has --notify-keyspace-events Ex",
			zap.Error(configErr))
		return
	}
	logger.Info("Redis keyspace notifications enabled for event-driven offline detection")

	// 订阅 key 过期事件: __keyspace@<db>__:device:heartbeat:*
	pubsub := rdb.PSubscribe(ctx, "__keyspace@*__:device:heartbeat:*")
	defer pubsub.Close()

	// 等待订阅就绪
	time.Sleep(500 * time.Millisecond)

	ch := pubsub.Channel()
	logger.Info("Heartbeat expiry listener started, waiting for key expiry events")
	for {
		select {
		case <-done:
			logger.Info("Heartbeat expiry listener stopped")
			return
		case msg, ok := <-ch:
			if !ok {
				logger.Warn("Heartbeat expiry listener channel closed unexpectedly")
				return
			}
			// 只处理 expired 事件
			if msg.Payload != "expired" {
				continue
			}
			// 从 channel 名称提取设备 SN: __keyspace@0__:device:heartbeat:{sn}
			channel := msg.Channel
			prefix := "device:heartbeat:"
			idx := strings.LastIndex(channel, prefix)
			if idx < 0 {
				continue
			}
			sn := channel[idx+len(prefix):]
			if sn == "" {
				continue
			}

			logger.Info("Device heartbeat key expired, marking offline", zap.String("sn", sn))
			// 标记设备离线（使用新的 context 避免超时）
			offlineCtx, offlineCancel := context.WithTimeout(context.Background(), 5*time.Second)
			result, err := deviceRepo.MarkDeviceOfflineBySN(offlineCtx, sn)
			offlineCancel()
			if err != nil {
				logger.Error("Failed to mark device offline on heartbeat expiry", zap.String("sn", sn), zap.Error(err))
				continue
			}
			if result {
				logger.Info("Device marked offline via keyspace notification", zap.String("sn", sn))
				syncCtx, syncCancel := context.WithTimeout(context.Background(), 5*time.Second)
				deviceRepo.SyncStationStatus(syncCtx)
				syncCancel()
			}
		}
	}
}

func runHeartbeatCheck(deviceRepo *repository.DeviceRepository, done chan struct{}) {
	// 兜底扫描从 5 分钟缩短为 60 秒，确保事件驱动失效时也能快速发现离线
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			logger.Info("Heartbeat check stopped")
			return
		case <-ticker.C:
			sns, err := deviceRepo.MarkStaleDevicesOffline(context.Background(), 120)
			if err != nil {
				logger.Error("Heartbeat fallback scan failed", zap.Error(err))
			} else if len(sns) > 0 {
				logger.Info("Heartbeat fallback scan: marked stale devices offline",
					zap.Int("count", len(sns)), zap.Strings("sns", sns))
				deviceRepo.SyncStationStatus(context.Background())
			}
		}
	}
}

// runOTATimeoutCleanup 定期清理卡住的 OTA 升级记录。
// 每 5 分钟扫描一次 status='upgrading' 且 started_at 超过 15 分钟的记录，
// 将其标记为 failed，并更新关联 upgrade_tasks 的统计数据与状态。
func runOTATimeoutCleanup(db *pgxpool.Pool, done chan struct{}) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			logger.Info("OTA timeout cleanup stopped")
			return
		case <-ticker.C:
			// 1. 查找所有 status='upgrading' 且 started_at 超过 15 分钟的记录
			rows, err := db.Query(context.Background(), `
				SELECT id, COALESCE(task_id, 0)
				FROM device_upgrades
				WHERE status = 'upgrading' AND started_at IS NOT NULL AND started_at < NOW() - INTERVAL '15 minutes'
			`)
			if err != nil {
				logger.Warn("OTA timeout cleanup query failed", zap.Error(err))
				continue
			}

			type staleRecord struct{ id, taskID int64 }
			var staleRecords []staleRecord
			for rows.Next() {
				var r staleRecord
				rows.Scan(&r.id, &r.taskID)
				staleRecords = append(staleRecords, r)
			}
			rows.Close()

			if len(staleRecords) == 0 {
				continue
			}

			// 2. 批量标记为 failed
			for _, r := range staleRecords {
				db.Exec(context.Background(), `
					UPDATE device_upgrades SET status = 'failed', error_message = '升级超时，设备可能已断连', updated_at = NOW()
					WHERE id = $1 AND status = 'upgrading'`, r.id)
				logger.Info("OTA upgrade marked as timed out", zap.Int64("id", r.id))
			}

			// 3. 更新关联任务统计
			taskIDs := map[int64]bool{}
			for _, r := range staleRecords {
				if r.taskID > 0 {
					taskIDs[r.taskID] = true
				}
			}
			for taskID := range taskIDs {
				db.Exec(context.Background(), `
					UPDATE upgrade_tasks SET
						success_count = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'success'),
						failed_count  = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'failed'),
						updated_at = NOW()
					WHERE id = $1`, taskID)

				// 检查是否全部完成
				var total, success, failed int
				if err := db.QueryRow(context.Background(), `
					SELECT total_devices, success_count, failed_count FROM upgrade_tasks WHERE id = $1
				`, taskID).Scan(&total, &success, &failed); err == nil && total > 0 {
					if success+failed >= total {
						newStatus := "completed"
						if failed > 0 {
							newStatus = "partial_success"
						}
						db.Exec(context.Background(), `
							UPDATE upgrade_tasks SET status = $2, completed_at = NOW(), updated_at = NOW()
							WHERE id = $1`, taskID, newStatus)
						logger.Info("Upgrade task auto-completed after timeout",
							zap.Int64("task_id", taskID), zap.String("status", newStatus))
					}
				}
			}

			logger.Info("OTA timeout cleanup completed", zap.Int("stale_records", len(staleRecords)))
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
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s timezone=UTC",
		cfg.Database.Host, cfg.Database.Port, cfg.Database.User,
		cfg.Database.Password, cfg.Database.Database, cfg.Database.SSLMode,
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

	const maxRetries = 10
	for attempt := 1; attempt <= maxRetries; attempt++ {
		logger.Info("Database connecting",
			zap.String("host", cfg.Database.Host),
			zap.Int("port", cfg.Database.Port),
			zap.String("database", cfg.Database.Database),
			zap.String("user", cfg.Database.User),
			zap.String("sslmode", cfg.Database.SSLMode),
			zap.Int("attempt", attempt),
			zap.Int("maxRetries", maxRetries),
		)

		pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
		if err != nil {
			logger.Warn("Database pool creation failed", zap.Error(err), zap.Int("attempt", attempt))
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := pool.Ping(ctx); err != nil {
			cancel()
			pool.Close()
			logger.Warn("Database ping failed", zap.Error(err), zap.Int("attempt", attempt))
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
			continue
		}

		var dbName string
		err = pool.QueryRow(ctx, "SELECT current_database()").Scan(&dbName)
		cancel()
		if err != nil {
			logger.Warn("Failed to get database name", zap.Error(err))
		} else {
			logger.Info("Database connected", zap.String("dbname", dbName))
		}
		return pool, nil
	}

	return nil, fmt.Errorf("database connection failed after %d attempts", maxRetries)
}

func initRedis(cfg *config.Config) (*redis.Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%d", cfg.Redis.Host, cfg.Redis.Port),
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	const maxRetries = 10
	for attempt := 1; attempt <= maxRetries; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := rdb.Ping(ctx).Err(); err != nil {
			cancel()
			logger.Warn("Redis ping failed", zap.Error(err), zap.Int("attempt", attempt))
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
			continue
		}
		cancel()
		logger.Info("Redis connected")
		return rdb, nil
	}

	rdb.Close()
	return nil, fmt.Errorf("redis connection failed after %d attempts", maxRetries)
}

type RouterDeps struct {
	DB                  *pgxpool.Pool
	RDB                 *redis.Client
	JWTInstance         *jwt.JWT
	JWTService          *service.JWTService
	AuthHandler         *handler.AuthHandler
	StationHandler      *handler.StationHandler
	DeviceHandler       *handler.DeviceHandler
	AlarmHandler        *handler.AlarmHandler
	NotificationHandler *handler.NotificationHandler
	WeatherHandler      *handler.WeatherHandler
	ModelHandler        *handler.ModelHandler
	PermChecker         *service.PermChecker
	AdminHandler        *handler.AdminHandler
	OTAHandler          *handler.OTAHandler
	OTAService          *service.OTAService
	DashboardHandler    *handler.DashboardHandler
	AlertRuleHandler    *handler.AlertRuleHandler
	WorkOrderHandler    *handler.WorkOrderHandler
}

func setupRouter(cfg *config.Config, deps *RouterDeps) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.MaxMultipartMemory = 200 << 20 // 200MB
	router.Use(customRecovery())
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

	internalHandler := handler.NewInternalHandler(deps.DB, deps.RDB, deps.OTAService, nil, nil)

	internal := router.Group("/api/v1/internal").Use(middleware.InternalAuth())
	{
		internal.POST("/device-status", internalHandler.DeviceStatus)
		internal.POST("/device-info", internalHandler.DeviceInfo)
		internal.POST("/device-data", internalHandler.DeviceData)
		internal.POST("/device-cmd-status", internalHandler.DeviceCmdStatus)
		internal.POST("/device-cmd-result", internalHandler.DeviceCmdResult)
		internal.POST("/device-alarm", internalHandler.DeviceAlarm)
		internal.POST("/ota-status", internalHandler.OTAStatus)
		internal.POST("/ota-cmd-ack", internalHandler.OTACmdAck)
	}

	// 固件文件下载（无需认证，设备直接访问 /firmware/xxx.bin）
	router.Static("/firmware", "/data/firmware")

	api := router.Group("/api/v1")
	{
		api.POST("/auth/login", deps.AuthHandler.Login)
		api.POST("/auth/register", deps.AuthHandler.Register)
		api.POST("/auth/send-code", deps.AuthHandler.SendCode)
		api.POST("/auth/reset-password", deps.AuthHandler.ResetPassword)
		api.POST("/auth/email-reset-password", deps.AuthHandler.EmailResetPassword)
		api.POST("/auth/email-register", deps.AuthHandler.EmailRegister)
		api.POST("/auth/email-login", deps.AuthHandler.EmailLogin)
		api.POST("/auth/send-email-code", deps.AuthHandler.SendEmailCode)
		api.POST("/auth/refresh", deps.AuthHandler.RefreshToken)

		// 公共参考数据 (无需认证)
		api.GET("/timezones", func(c *gin.Context) {
			response.Success(c, timezone.GetTimezoneList())
		})

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
			auth.POST("/devices/batch/control", deps.DeviceHandler.BatchControl)
			auth.GET("/devices/:sn/control-fields", deps.DeviceHandler.GetControlFields)
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
			auth.DELETE("/alarms/clear", deps.AlarmHandler.ClearAll)
			auth.PUT("/alarms/read", deps.AlarmHandler.MarkRead)
			auth.GET("/alarms/stats", deps.AlarmHandler.GetStats)
			auth.GET("/alarms/:id", deps.AlarmHandler.GetByID)
			auth.PUT("/alarms/:id/handle", deps.AlarmHandler.MarkHandled)
			auth.POST("/alarms/:id/acknowledge", deps.AlarmHandler.Acknowledge)
			auth.POST("/alarms/:id/ignore", deps.AlarmHandler.Ignore)
			auth.DELETE("/alarms/:id", deps.AlarmHandler.Delete)

			// 通知管理
			auth.GET("/notifications", deps.NotificationHandler.List)
			auth.GET("/notifications/stats", deps.NotificationHandler.GetStats)
			// SSE 实时推送端点（必须在参数路由之前注册）
			auth.GET("/notifications/stream", internalHandler.NotificationStream)
			auth.DELETE("/notifications/clear", deps.NotificationHandler.ClearAll)
			auth.DELETE("/notifications/:id", deps.NotificationHandler.Delete)

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

			// Protocol CRUD
			auth.GET("/models/:id/protocols", deps.ModelHandler.GetProtocols)
			auth.POST("/models/:id/protocols", deps.ModelHandler.CreateProtocol)
			auth.PUT("/models/:id/protocols/:protocolId", deps.ModelHandler.UpdateProtocol)
			auth.DELETE("/models/:id/protocols/:protocolId", deps.ModelHandler.DeleteProtocol)

			auth.GET("/dashboard/statistics", deps.DashboardHandler.GetStatistics)
			auth.GET("/dashboard/device-distribution", deps.DashboardHandler.GetDeviceDistribution)
			auth.GET("/dashboard/trend", deps.DashboardHandler.GetTrend)
			auth.GET("/dashboard/big-screen", deps.DashboardHandler.GetBigScreen)
			auth.GET("/dashboard/compare", deps.DashboardHandler.CompareDevices)
			auth.GET("/dashboard/energy-stats", deps.DashboardHandler.GetEnergyStats)
			auth.GET("/dashboard/energy-flow", deps.DashboardHandler.GetEnergyFlow)
			auth.GET("/dashboard/station-ranking", deps.DashboardHandler.GetStationRanking)
			auth.GET("/dashboard/sse", deps.DashboardHandler.SSE)

			auth.GET("/alert-rules", deps.AlertRuleHandler.List)
			auth.GET("/alert-rules/:id", deps.AlertRuleHandler.GetByID)
			auth.POST("/alert-rules", deps.AlertRuleHandler.Create)
			auth.PUT("/alert-rules/:id", deps.AlertRuleHandler.Update)
			auth.DELETE("/alert-rules/:id", deps.AlertRuleHandler.Delete)

			auth.GET("/work-orders", deps.WorkOrderHandler.List)
			auth.GET("/work-orders/stats", deps.WorkOrderHandler.GetStatistics)
			auth.POST("/work-orders", deps.WorkOrderHandler.Create)
			auth.GET("/work-orders/:id", deps.WorkOrderHandler.GetByID)
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
			// 升级管理（替代旧 /tasks）
			otaGroup.GET("/upgrades/dashboard", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradeDashboard)
			otaGroup.POST("/upgrades/push", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.PushUpgrade)
			otaGroup.GET("/upgrades/firmware/:firmwareId", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetFirmwareUpgradeDetails)
			otaGroup.POST("/upgrades/retry", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RetryUpgrade)
			otaGroup.POST("/upgrades/cancel", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.CancelUpgrade)
			otaGroup.DELETE("/upgrades/firmware/:firmwareId", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradesByFirmware)

			// 升级包管理
			otaGroup.GET("/packages", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListUpgradePackages)
			otaGroup.GET("/packages/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradePackage)
			otaGroup.POST("/packages", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateUpgradePackage)
			otaGroup.DELETE("/packages/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradePackage)
			otaGroup.POST("/packages/push", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.PushPackageUpgrade)
			otaGroup.POST("/packages/:id/rollback", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackPackageUpgrade)
			otaGroup.GET("/packages/:id/details", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetPackageUpgradeDetails)

			// 升级任务管理（新统一接口）
			otaGroup.GET("/tasks", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListUpgradeTasks)
			otaGroup.POST("/tasks", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateUpgradeTask)
			otaGroup.GET("/tasks/stats", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetTaskStats)
			otaGroup.GET("/tasks/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradeTask)
			otaGroup.POST("/tasks/:id/execute", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.ExecuteUpgradeTask)
			otaGroup.POST("/tasks/:id/cancel", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.CancelUpgradeTask)
			otaGroup.POST("/tasks/:id/retry", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RetryUpgradeTask)
			otaGroup.DELETE("/tasks/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradeTask)
			otaGroup.GET("/tasks/:id/devices", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradeTaskDevices)

			otaGroup.GET("/firmware/devices", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetDevicesByFirmware)
			otaGroup.GET("/firmware/package-devices", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradePackageDevices)

			// APP端接口（所有登录用户可访问）
			otaGroup.GET("/check/:sn", deps.OTAHandler.CheckUpdate)
			otaGroup.POST("/trigger", deps.OTAHandler.TriggerOTA)
			otaGroup.POST("/resend/:sn", deps.OTAHandler.ResendUpgradeCommand)
			otaGroup.GET("/devices/:sn/status", deps.OTAHandler.GetDeviceOTAStatus)
			otaGroup.GET("/devices/:sn/history", deps.OTAHandler.GetDeviceOTAHistory)
			otaGroup.POST("/devices/:sn/local-ota-result", deps.OTAHandler.ReportLocalOTAResult)
			otaGroup.GET("/app/packages", deps.OTAHandler.AppListUpgradePackages)
			otaGroup.POST("/app/packages/install", deps.OTAHandler.AppInstallPackage)
			otaGroup.GET("/devices/:sn/package-upgrade/:packageId", deps.OTAHandler.GetDevicePackageUpgradeInfo)
			otaGroup.GET("/devices/:sn/upgrade-packages", deps.OTAHandler.ListDeviceUpgradePackages)

			// App版本管理
			otaGroup.GET("/app/check", deps.OTAHandler.CheckAppUpdate) // APP检查更新（无需额外权限）
			otaGroup.GET("/app/versions", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListAppVersions)
			otaGroup.POST("/app/versions", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateAppVersion)
			otaGroup.DELETE("/app/versions/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteAppVersion)
			otaGroup.PUT("/app/versions/:id/rollout", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.UpdateAppVersionRollout)
			otaGroup.POST("/app/versions/:id/rollback", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackAppVersion)
			otaGroup.POST("/app/versions/:id/restore", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RestoreAppVersion)
		}
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

func customRecovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		defer func() {
			if r := recover(); r != nil {
				fmt.Fprintf(os.Stderr, "[PANIC RECOVERED] %s %s: %v\n%s\n",
					c.Request.Method, c.Request.URL.Path, r, debug.Stack())
				c.AbortWithStatus(http.StatusInternalServerError)
			}
		}()
		c.Next()
	}
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
