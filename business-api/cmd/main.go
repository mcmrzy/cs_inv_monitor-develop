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
	"inv-api-server/internal/job"
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
		logger.Fatal("Failed to init database", zap.Error(err))
	}
	defer db.Close()

	// Migrations are a startup barrier: consumers must never see a partially
	// migrated schema, and a failed migration must never be reported healthy.
	if cfg.Migration.AutoRun {
		logger.Info("Running database migrations...",
			zap.String("dir", cfg.Migration.Dir),
			zap.String("schema_file", cfg.Migration.SchemaFile))
		if err := migration.Run(context.Background(), db, cfg.Migration.Dir, cfg.Migration.SchemaFile, cfg.Migration.BaselineVersion); err != nil {
			logger.Fatal("Database migration failed", zap.Error(err))
		}
	}

	rdb, err := initRedis(cfg)
	if err != nil {
		logger.Fatal("Failed to init redis", zap.Error(err))
	}
	defer rdb.Close()

	startFullServer(cfg, db, rdb)
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
	authorizationRepo := repository.NewAuthorizationRepository(db)
	authorizationService := service.NewAuthorizationService(
		authorizationRepo,
		service.NewResourceObjectResolver("device", authorizationRepo),
	)
	dataPermission := service.NewDataPermissionAdapter(db, authorizationService, service.DataPermissionEnforce, nil)
	stationRepo := repository.NewStationRepository(db)
	deviceRepo := repository.NewDeviceRepository(db, rdb)
	alarmRepo := repository.NewAlarmRepository(db)
	modelRepo := repository.NewModelRepository(db, rdb)
	batteryRepo := repository.NewBatteryRepository(db)
	energyScheduleRepo := repository.NewEnergyScheduleRepository(db)

	userService := service.NewUserService(userRepo, rdb)
	jwtService := service.NewJWTService(jwtInstance, rdb)
	smsProvider, err := service.NewSMSProvider(cfg.SMS.Provider, cfg.SMS.AccessKey, cfg.SMS.SecretKey, cfg.SMS.SignName, cfg.SMS.Template)
	if err != nil {
		logger.Warn("Failed to create SMS provider, using mock", zap.Error(err))
		smsProvider = &service.MockSMSProvider{}
	}
	smsService := service.NewSMSService(rdb, smsProvider)
	configService := service.NewConfigService(db, rdb, *cfg)
	emailService := service.NewEmailService(rdb, cfg.Email, configService)
	jpushService := service.NewJPushService(&cfg.JPush, rdb)
	stationService := service.NewStationService(stationRepo)
	permChecker := service.NewPermChecker(rdb, userRepo)
	deviceService := service.NewDeviceService(deviceRepo, rdb, modelRepo, permChecker, cfg.Backends.DeviceServer, cfg.Backends.InternalKey, db)
	alarmService := service.NewAlarmService(alarmRepo)
	modelService := service.NewModelService(modelRepo)
	batteryService := service.NewBatteryService(batteryRepo)
	energyScheduleService := service.NewEnergyScheduleService(energyScheduleRepo)

	// Initialize RBAC cache if enabled
	var rbacCache *service.RBACCache
	if cfg.RBAC.Enabled {
		ttl := cfg.RBAC.TTLDuration
		if ttl == 0 {
			ttl = 5 * time.Minute // default
		}
		rbacCache = service.NewRBACCache(rdb, ttl)
		logger.Info("RBAC cache initialized", zap.Duration("ttl", ttl))
	} else {
		logger.Info("RBAC caching disabled")
	}

	otaRepo := repository.NewOTARepository(db)
	otaService := service.NewOTAService(otaRepo, rdb, cfg.Backends.DeviceServer, cfg.Backends.InternalKey, cfg.Backends.UploadDir, cfg.Backends.ServerURL, db, jpushService)

	captchaHandler := handler.NewCaptchaHandler(rdb)
	authHandler := handler.NewAuthHandler(userService, jwtService, smsService, emailService, rbacCache, captchaHandler)
	authHandler.SetAuthorizationContextResolver(authorizationRepo)
	stationHandler := handler.NewStationHandler(stationService, deviceService, userService, db, cfg.Backends.AmapAPIKey)
	weatherHandler := handler.NewWeatherHandler(stationService, cfg.Backends.WeatherAPI, cfg.Backends.AmapAPIKey, cfg.Backends.WeatherSource)
	deviceHandler := handler.NewDeviceHandler(deviceService, alarmService, stationService, db)
	alarmHandler := handler.NewAlarmHandler(alarmService)
	notificationHandler := handler.NewNotificationHandler(db, jpushService)
	wsHandler := handler.NewWSHandler(rdb, jwtService, authorizationRepo, dataPermission, cfg.CORS.AllowedOrigins)
	modelHandler := handler.NewModelHandler(modelService)
	batteryHandler := handler.NewBatteryHandler(batteryService)
	energyScheduleHandler := handler.NewEnergyScheduleHandler(energyScheduleService)
	adminHandler := handler.NewAdminHandler(userRepo, modelRepo, permChecker, db, rdb, configService)
	otaHandler := handler.NewOTAHandler(otaService, db, jpushService)
	dashboardHandler := handler.NewDashboardHandler(db, rdb)
	alertRuleHandler := handler.NewAlertRuleHandler(db)
	workOrderHandler := handler.NewWorkOrderHandler(db)
	parallelRepo := repository.NewParallelRepository(db)
	parallelService := service.NewParallelService(parallelRepo)
	parallelHandler := handler.NewParallelHandler(parallelService)

	// Initialize invitation handler with email service
	organizationRepo := repository.NewOrganizationRepository(db)
	invitationRepo := repository.NewInvitationRepository()
	invitationHandler := handler.NewInvitationHandler(
		db,
		userRepo,
		organizationRepo,
		invitationRepo,
		jwtService,
		rbacCache,
		permChecker,
		authorizationRepo,
		emailService,
	)

	organizationHandler := handler.NewOrganizationHandler(db)
	jobStore := job.NewJobStore(rdb)
	memberLifecycleHandler := handler.NewMemberLifecycleHandler(db, rdb, jobStore)
	deviceClaimTransferHandler := handler.NewDeviceClaimTransferHandler(db, permChecker, jwtService, cfg.Backends.DeviceServer, cfg.Backends.InternalKey)
	
	// Task 11 & 12: Pipeline health and DLQ handlers
	pipelineHealthHandler := handler.NewPipelineHealthHandler(rdb)
	dlqHandler := handler.NewDLQHandler(rdb)

	heartbeatDone := make(chan struct{})
	defer close(heartbeatDone)
	// 浜嬩欢椹卞姩锛氱洃鍚?Redis Keyspace Notification锛屽績璺?key 杩囨湡鏃剁珛鍗虫爣璁拌澶囩绾?
	go runHeartbeatExpiryListener(rdb, deviceRepo, heartbeatDone)
	// 鍏滃簳锛氭瘡 5 鍒嗛挓鍏ㄩ噺鎵弿涓€娆★紝澶勭悊鐩戝惉鍣ㄥ彲鑳介仐婕忕殑鎯呭喌
	go runHeartbeatCheck(deviceRepo, heartbeatDone)

	// OTA 鍗囩骇瓒呮椂娓呯悊锛氭瘡 5 鍒嗛挓鎵弿鍗′綇鐨勫崌绾ц褰曞苟鏇存柊鍏宠仈浠诲姟缁熻
	go runOTATimeoutCleanup(db, heartbeatDone)
	// OTA 瀹氭椂浠诲姟锛氶鍙栧苟鎵ц鍒版湡浠诲姟锛岄噸鍚悗涔熶細鎭㈠宸插埌鏈熶絾鏈墽琛岀殑浠诲姟銆?
	go runOTAScheduler(db, otaService, heartbeatDone)

	router := setupRouter(cfg, &RouterDeps{
		DB:                            db,
		RDB:                           rdb,
		JWTInstance:                   jwtInstance,
		JWTService:                    jwtService,
		AuthHandler:                   authHandler,
		CaptchaHandler:                captchaHandler,
		StationHandler:                stationHandler,
		DeviceHandler:                 deviceHandler,
		DeviceClaimTransferHandler:    deviceClaimTransferHandler,
		AlarmHandler:                  alarmHandler,
		NotificationHandler:           notificationHandler,
		WeatherHandler:                weatherHandler,
		ModelHandler:                  modelHandler,
		BatteryHandler:                batteryHandler,
		EnergyScheduleHandler:         energyScheduleHandler,
		PermChecker:                   permChecker,
		AdminHandler:                  adminHandler,
		OTAHandler:                    otaHandler,
		OTAService:                    otaService,
		JPushService:                  jpushService,
		DashboardHandler:              dashboardHandler,
		AlertRuleHandler:              alertRuleHandler,
		WorkOrderHandler:              workOrderHandler,
		ParallelHandler:               parallelHandler,
		OrganizationHandler:           organizationHandler,
		MemberLifecycleHandler:        memberLifecycleHandler,
		InvitationHandler:             invitationHandler,
		PipelineHealthHandler:         pipelineHealthHandler,
		DLQHandler:                    dlqHandler,
		AuthorizationContextValidator: authorizationRepo,
	})
	router.GET("/ws/device/:sn", wsHandler.DeviceRealtime)
	serve(cfg, router)
}

// runHeartbeatExpiryListener 鐩戝惉 Redis Keyspace Notification锛屽綋 device:heartbeat:{sn} key 杩囨湡鏃?
// 绔嬪嵆灏嗚澶囨爣璁颁负绂荤嚎锛屽疄鐜颁簨浠堕┍鍔ㄧ殑绂荤嚎妫€娴嬶紝寤惰繜浠庡垎閽熺骇闄嶅埌绉掔骇
func runHeartbeatExpiryListener(rdb *redis.Client, deviceRepo *repository.DeviceRepository, done chan struct{}) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// 绛夊緟 Redis 杩炴帴灏辩华
	time.Sleep(2 * time.Second)

	// 鍚敤 keyspace notifications for expired events (Ex)
	// 閲嶈瘯 3 娆★紝纭繚閰嶇疆鎴愬姛
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

	// 璁㈤槄 key 杩囨湡浜嬩欢: __keyspace@<db>__:device:heartbeat:*
	pubsub := rdb.PSubscribe(ctx, "__keyspace@*__:device:heartbeat:*")
	defer pubsub.Close()

	// 绛夊緟璁㈤槄灏辩华
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
			// 鍙鐞?expired 浜嬩欢
			if msg.Payload != "expired" {
				continue
			}
			// 浠?channel 鍚嶇О鎻愬彇璁惧 SN: __keyspace@0__:device:heartbeat:{sn}
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
			// 鏍囪璁惧绂荤嚎锛堜娇鐢ㄦ柊鐨?context 閬垮厤瓒呮椂锛?
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
	// 鍏滃簳鎵弿浠?5 鍒嗛挓缂╃煭涓?60 绉掞紝纭繚浜嬩欢椹卞姩澶辨晥鏃朵篃鑳藉揩閫熷彂鐜扮绾?
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

// runOTATimeoutCleanup 瀹氭湡娓呯悊鍗′綇鐨?OTA 鍗囩骇璁板綍銆?
// 姣?5 鍒嗛挓鎵弿涓€娆?status='upgrading' 涓?started_at 瓒呰繃 15 鍒嗛挓鐨勮褰曪紝
// 灏嗗叾鏍囪涓?failed锛屽苟鏇存柊鍏宠仈 upgrade_tasks 鐨勭粺璁℃暟鎹笌鐘舵€併€?
func runOTATimeoutCleanup(db *pgxpool.Pool, done chan struct{}) {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			logger.Info("OTA timeout cleanup stopped")
			return
		case <-ticker.C:
			// 1. 鏌ユ壘鎵€鏈?status='upgrading' 涓?started_at 瓒呰繃 15 鍒嗛挓鐨勮褰?
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

			// 2. 鎵归噺鏍囪涓?failed
			for _, r := range staleRecords {
				db.Exec(context.Background(), `
					UPDATE device_upgrades SET status = 'failed', error_message = '鍗囩骇瓒呮椂锛岃澶囧彲鑳藉凡鏂繛', updated_at = NOW()
					WHERE id = $1 AND status = 'upgrading'`, r.id)
				logger.Info("OTA upgrade marked as timed out", zap.Int64("id", r.id))
			}

			// 3. 鏇存柊鍏宠仈浠诲姟缁熻
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

				// 妫€鏌ユ槸鍚﹀叏閮ㄥ畬鎴?
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

// runOTAScheduler atomically claims due scheduled tasks. A task left pending
// by a process crash is reclaimable after five minutes.
func runOTAScheduler(db *pgxpool.Pool, otaService *service.OTAService, done chan struct{}) {
	run := func() {
		rows, err := db.Query(context.Background(), `
			WITH due AS (
				SELECT id FROM upgrade_tasks
				WHERE execute_mode = 'scheduled'
				  AND scheduled_at IS NOT NULL
				  AND scheduled_at <= NOW()
				  AND (status = 'scheduled' OR (status = 'pending' AND updated_at < NOW() - INTERVAL '5 minutes'))
				ORDER BY scheduled_at, id
				FOR UPDATE SKIP LOCKED
				LIMIT 20
			)
			UPDATE upgrade_tasks t
			SET status = 'pending', updated_at = NOW()
			FROM due
			WHERE t.id = due.id
			RETURNING t.id
		`)
		if err != nil {
			logger.Warn("OTA scheduler claim failed", zap.Error(err))
			return
		}
		var taskIDs []int64
		for rows.Next() {
			var id int64
			if err := rows.Scan(&id); err == nil {
				taskIDs = append(taskIDs, id)
			}
		}
		rows.Close()
		for _, taskID := range taskIDs {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			err := otaService.ExecuteTask(ctx, taskID)
			cancel()
			if err != nil {
				logger.Error("Scheduled OTA task execution failed", zap.Int64("task_id", taskID), zap.Error(err))
				_, _ = db.Exec(context.Background(), `
					UPDATE upgrade_tasks SET status = 'failed', notes = CONCAT_WS(E'\n', NULLIF(notes, ''), $2),
					completed_at = NOW(), updated_at = NOW() WHERE id = $1 AND status IN ('pending','running')
				`, taskID, "瀹氭椂鎵ц澶辫触: "+err.Error())
			}
		}
		if len(taskIDs) > 0 {
			logger.Info("OTA scheduled tasks dispatched", zap.Int("count", len(taskIDs)))
		}
	}

	run()
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			logger.Info("OTA scheduler stopped")
			return
		case <-ticker.C:
			run()
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
	DB                            *pgxpool.Pool
	RDB                           *redis.Client
	JWTInstance                   *jwt.JWT
	JWTService                    *service.JWTService
	AuthHandler                   *handler.AuthHandler
	CaptchaHandler                *handler.CaptchaHandler
	StationHandler                *handler.StationHandler
	DeviceHandler                 *handler.DeviceHandler
	DeviceClaimTransferHandler    *handler.DeviceClaimTransferHandler
	AlarmHandler                  *handler.AlarmHandler
	NotificationHandler           *handler.NotificationHandler
	WeatherHandler                *handler.WeatherHandler
	ModelHandler                  *handler.ModelHandler
	BatteryHandler                *handler.BatteryHandler
	EnergyScheduleHandler         *handler.EnergyScheduleHandler
	PermChecker                   *service.PermChecker
	AdminHandler                  *handler.AdminHandler
	OTAHandler                    *handler.OTAHandler
	OTAService                    *service.OTAService
	JPushService                  *service.JPushService
	DashboardHandler              *handler.DashboardHandler
	AlertRuleHandler              *handler.AlertRuleHandler
	WorkOrderHandler              *handler.WorkOrderHandler
	ParallelHandler               *handler.ParallelHandler
	OrganizationHandler           *handler.OrganizationHandler
	MemberLifecycleHandler        *handler.MemberLifecycleHandler
	InvitationHandler             *handler.InvitationHandler
	PipelineHealthHandler         *handler.PipelineHealthHandler
	DLQHandler                    *handler.DLQHandler
	AuthorizationContextValidator middleware.AuthorizationContextValidator
}

func setupRouter(cfg *config.Config, deps *RouterDeps) *gin.Engine {
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.MaxMultipartMemory = 8 << 20
	router.Use(customRecovery())
	router.Use(requestBodyLimit())
	router.Use(middleware.CORS(cfg.CORS.AllowedOrigins))
	router.Use(tracingMiddleware())
	router.Use(middleware.RateLimit())

	router.GET("/health", func(c *gin.Context) {
		status := gin.H{"status": "ok"}
		httpStatus := http.StatusOK
		ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
		defer cancel()

		if deps.DB != nil {
			if err := deps.DB.Ping(ctx); err != nil {
				status["db"] = "error"
				httpStatus = http.StatusServiceUnavailable
			} else {
				status["db"] = "ok"
			}
		}
		if deps.RDB != nil {
			if err := deps.RDB.Ping(ctx).Err(); err != nil {
				status["redis"] = "error"
				httpStatus = http.StatusServiceUnavailable
			} else {
				status["redis"] = "ok"
			}
		}

		if httpStatus != http.StatusOK {
			status["status"] = "degraded"
		}
		c.JSON(httpStatus, status)
	})

	internalHandler := handler.NewInternalHandler(deps.DB, deps.RDB, deps.OTAService, deps.JPushService, nil, nil)

	internal := router.Group("/api/v1/internal").Use(middleware.InternalAuth(cfg.Backends.InternalKey))
	{
		internal.POST("/device-status", internalHandler.DeviceStatus)
		internal.POST("/device-info", internalHandler.DeviceInfo)
		internal.POST("/device-data", internalHandler.DeviceData)
		internal.POST("/device-data-batch", internalHandler.DeviceDataBatch)
		internal.POST("/device-cmd-status", internalHandler.DeviceCmdStatus)
		internal.POST("/device-cmd-result", internalHandler.DeviceCmdResult)
		internal.POST("/device-alarm", internalHandler.IngestAlarmV1)
		internal.POST("/parallel-state", internalHandler.IngestParallelV1)
		internal.POST("/three-phase", internalHandler.IngestThreePhaseV1)
		internal.POST("/ota-status", internalHandler.OTAStatus)
		internal.POST("/ota-cmd-ack", internalHandler.OTACmdAck)
	}

	// 鍥轰欢鏂囦欢涓嬭浇锛堟棤闇€璁よ瘉锛岃澶囩洿鎺ヨ闂?/firmware/xxx.bin锛?
	// 浣跨敤 http.ServeContent 鏇夸唬 Gin Static锛屼紭鍖栧ぇ鏂囦欢浼犺緭
	firmwareDir := "/data/firmware"
	if err := os.MkdirAll(firmwareDir, 0755); err != nil {
		panic("create firmware directory: " + err.Error())
	}
	firmwareRoot, err := os.OpenRoot(firmwareDir)
	if err != nil {
		panic("open firmware directory: " + err.Error())
	}
	router.GET("/firmware/*filepath", func(c *gin.Context) {
		f, err := openFirmwareFile(firmwareRoot, c.Param("filepath"))
		if err != nil {
			c.Status(http.StatusNotFound)
			return
		}
		defer f.Close()
		stat, err := f.Stat()
		if err != nil || stat.IsDir() {
			c.Status(http.StatusNotFound)
			return
		}
		c.Header("Content-Type", "application/octet-stream")
		c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%q", stat.Name()))
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("Accept-Ranges", "bytes")
		http.ServeContent(c.Writer, c.Request, stat.Name(), stat.ModTime(), f)
	})

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
		api.POST("/auth/context", deps.AuthHandler.AuthorizationContext)
		api.POST("/auth/phone-code-login", deps.AuthHandler.PhoneCodeLogin)
		api.POST("/auth/email-code-login", deps.AuthHandler.EmailCodeLogin)

		// 鍏叡鍙傝€冩暟鎹?(鏃犻渶璁よ瘉)
		api.GET("/timezones", func(c *gin.Context) {
			response.Success(c, timezone.GetTimezoneList())
		})

		// 楠岃瘉鐮?API锛堟棤闇€璁よ瘉锛?
		captchaLimit := middleware.RateLimitWith(2, 5)
		api.GET("/captcha/generate", captchaLimit, deps.CaptchaHandler.GenerateCaptcha)
		api.POST("/captcha/verify", captchaLimit, deps.CaptchaHandler.VerifyCaptcha)

		// Invitation endpoints (accept is public, others require auth)
		api.POST("/invite/accept", deps.InvitationHandler.Accept)

		auth := api.Group("")
		auth.Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			authInv := auth.Group("/invitations")
			{
				authInv.POST("/create", deps.InvitationHandler.Create)
				authInv.GET("/list", deps.InvitationHandler.List)
				authInv.DELETE("/:id/revoke", deps.InvitationHandler.Revoke)
				authInv.GET("/:id/details", deps.InvitationHandler.Details)
			}

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
			auth.POST("/devices", deps.DeviceHandler.Create)
			auth.GET("/devices/:sn", deps.DeviceHandler.GetDetail)
			auth.GET("/devices/:sn/realtime", deps.DeviceHandler.GetRealtimeData)
			auth.POST("/devices/bind", deps.DeviceHandler.Bind)
			auth.POST("/devices/:sn/unbind", deps.DeviceHandler.Unbind)
			auth.DELETE("/devices/:sn/unbind", deps.DeviceHandler.Unbind)
			auth.POST("/devices/:sn/request-unbind", deps.DeviceHandler.RequestUnbind)
			auth.DELETE("/devices/:sn", deps.DeviceHandler.DeleteDevice)
			auth.PUT("/devices/:sn", deps.DeviceHandler.Update)
			auth.POST("/devices/:sn/control", middleware.RequirePermission(deps.PermChecker, "devices", "control"), deps.DeviceHandler.Control)
			auth.POST("/devices/batch/control", middleware.RequirePermission(deps.PermChecker, "devices", "control"), deps.DeviceHandler.BatchControl)
			auth.GET("/devices/:sn/control-fields", deps.DeviceHandler.GetControlFields)
			auth.GET("/devices/:sn/control-capabilities", deps.DeviceHandler.GetControlCapabilities)
			auth.GET("/devices/:sn/control-state", deps.DeviceHandler.GetControlState)
			auth.GET("/devices/:sn/commands", deps.DeviceHandler.GetCommands)
			auth.GET("/devices/:sn/commands/history", deps.DeviceHandler.GetCommands)
			auth.GET("/devices/:sn/telemetry", deps.DeviceHandler.GetTelemetry)
			auth.GET("/devices/:sn/telemetry/export", deps.DeviceHandler.ExportTelemetry)
			auth.GET("/devices/:sn/telemetry/export-excel", deps.DeviceHandler.ExportTelemetryExcel)
			auth.GET("/devices/:sn/lifecycle", deps.DeviceHandler.GetLifecycleHistory)
			auth.GET("/devices/:sn/history", deps.DeviceHandler.GetHistory)
			auth.GET("/devices/:sn/alarms", deps.DeviceHandler.GetAlarms)
			auth.GET("/devices/:sn/alarm-events", internalHandler.GetAlarmEvents)
			auth.GET("/devices/:sn/parallel-state", internalHandler.GetParallelState)
			auth.GET("/devices/:sn/three-phase", internalHandler.GetThreePhaseHistory)
			auth.GET("/alarm-events/:id", internalHandler.GetAlarmEventDetail)
			auth.GET("/devices/:sn/statistics", deps.DeviceHandler.GetStatistics)
			auth.POST("/devices/add-to-station", deps.DeviceHandler.AddToStation)
			auth.POST("/devices/:sn/remove-from-station", deps.DeviceHandler.RemoveFromStation)
			auth.GET("/devices/scan/local", deps.DeviceHandler.ScanLocal)
			auth.GET("/devices/unbind-requests", deps.DeviceHandler.GetUnbindRequests)
			auth.POST("/devices/unbind-requests/:id/approve", deps.DeviceHandler.ApproveUnbind)
			auth.POST("/devices/unbind-requests/:id/reject", deps.DeviceHandler.RejectUnbind)

			// 璁惧璁ら涓庤浆绉荤鐞嗭紙鏂板锛?
			auth.POST("/devices/claim-code/generate", deps.DeviceClaimTransferHandler.GenerateClaimCode)
			auth.POST("/devices/claim-code/verify", deps.DeviceClaimTransferHandler.VerifyClaimCode)
			auth.POST("/devices/:sn/claim", deps.DeviceClaimTransferHandler.ClaimDevice)
			auth.POST("/devices/:sn/request-transfer", deps.DeviceClaimTransferHandler.RequestTransfer)
			auth.GET("/devices/transfers/list", deps.DeviceClaimTransferHandler.ListTransfers)
			auth.POST("/devices/transfers/:id/approve", deps.DeviceClaimTransferHandler.ApproveTransfer)
			auth.POST("/devices/transfers/:id/reject", deps.DeviceClaimTransferHandler.RejectTransfer)
			auth.POST("/devices/transfers/:id/cancel", deps.DeviceClaimTransferHandler.CancelTransfer)

			// 璁惧鍒嗛厤瀹夎鍟?
			auth.POST("/devices/:sn/assign-installer", deps.DeviceHandler.AssignInstaller)
			auth.DELETE("/devices/:sn/installer", deps.DeviceHandler.RemoveInstaller)
			auth.POST("/devices/batch-assign-installer", deps.DeviceHandler.BatchAssignInstaller)
			auth.POST("/devices/import-excel", deps.DeviceHandler.ImportExcel)

			// 鐢垫睜閰嶇疆妯℃澘
			auth.GET("/devices/:sn/battery-config", deps.BatteryHandler.GetDeviceConfig)
			auth.PUT("/devices/:sn/battery-config", deps.BatteryHandler.BindDeviceConfig)
			auth.GET("/battery-profiles", deps.BatteryHandler.ListProfiles)
			auth.GET("/battery-profiles/:id", deps.BatteryHandler.GetProfile)
			auth.POST("/battery-profiles", deps.BatteryHandler.CreateProfile)

			// 鑳芥簮璁″垝涓庝复鏃惰鐩?
			auth.GET("/devices/:sn/energy-schedule", deps.EnergyScheduleHandler.GetSchedule)
			auth.PUT("/devices/:sn/energy-schedule", deps.EnergyScheduleHandler.UpdateSchedule)
			auth.POST("/devices/:sn/control-overrides", deps.EnergyScheduleHandler.CreateOverride)
			auth.GET("/devices/:sn/control-overrides", deps.EnergyScheduleHandler.ListOverrides)
			auth.DELETE("/devices/:sn/control-overrides/:id", deps.EnergyScheduleHandler.CancelOverride)

			auth.GET("/alarms", deps.AlarmHandler.List)
			auth.DELETE("/alarms/clear", deps.AlarmHandler.ClearAll)
			auth.PUT("/alarms/read", deps.AlarmHandler.MarkRead)
			auth.GET("/alarms/stats", deps.AlarmHandler.GetStats)
			auth.GET("/alarms/:id", deps.AlarmHandler.GetByID)
			auth.PUT("/alarms/:id/handle", deps.AlarmHandler.MarkHandled)
			auth.POST("/alarms/:id/acknowledge", deps.AlarmHandler.Acknowledge)
			auth.POST("/alarms/:id/ignore", deps.AlarmHandler.Ignore)
			auth.DELETE("/alarms/:id", deps.AlarmHandler.Delete)

			// 閫氱煡绠＄悊
			auth.GET("/notifications", deps.NotificationHandler.List)
			auth.GET("/notifications/stats", deps.NotificationHandler.GetStats)
			// SSE 瀹炴椂鎺ㄩ€佺鐐癸紙蹇呴』鍦ㄥ弬鏁拌矾鐢变箣鍓嶆敞鍐岋級
			auth.GET("/notifications/stream", internalHandler.NotificationStream)
			auth.DELETE("/notifications/clear", deps.NotificationHandler.ClearAll)
			auth.DELETE("/notifications/:id", deps.NotificationHandler.Delete)

			registerModelRoutes(auth, deps.ModelHandler, deps.PermChecker)

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
			auth.GET("/work-orders/templates", deps.WorkOrderHandler.ListTemplates)
			auth.POST("/work-orders", deps.WorkOrderHandler.Create)
			auth.GET("/work-orders/:id", deps.WorkOrderHandler.GetByID)
			auth.PUT("/work-orders/:id", deps.WorkOrderHandler.Update)
			auth.PATCH("/work-orders/:id", deps.WorkOrderHandler.Update)
			auth.PATCH("/work-orders/:id/status", deps.WorkOrderHandler.Update)
			auth.POST("/work-orders/:id/escalate", deps.WorkOrderHandler.Escalate)
			auth.POST("/work-orders/:id/attachments", deps.WorkOrderHandler.UploadAttachments)
			auth.GET("/work-orders/:id/attachments/:attachmentId", deps.WorkOrderHandler.DownloadAttachment)
			auth.DELETE("/work-orders/:id", deps.WorkOrderHandler.Delete)
		}

		requireAdmin := middleware.RequirePermission(deps.PermChecker, "admin", "manage")
		adminGroup := api.Group("/admin").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator), requireAdmin)
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
			adminGroup.POST("/push-announcement", deps.NotificationHandler.PushAnnouncement)
			adminGroup.GET("/tenants", deps.AdminHandler.ListTenants)
			adminGroup.POST("/tenants", deps.AdminHandler.CreateTenant)
			adminGroup.PATCH("/tenants/:id", deps.AdminHandler.UpdateTenant)
			adminGroup.POST("/tenants/:id/toggle", deps.AdminHandler.ToggleTenant)
			adminGroup.GET("/metrics", deps.AdminHandler.GetMetrics)
		}

		usersGroup := api.Group("/users").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			usersGroup.GET("", middleware.RequirePermission(deps.PermChecker, "users", "view"), deps.AdminHandler.ListUsers)
			usersGroup.GET("/:id", deps.AdminHandler.GetUser)
			usersGroup.PATCH("/:id", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.UpdateUser)
			usersGroup.GET("/:id/children", deps.AdminHandler.GetUserChildren)
			usersGroup.PUT("/:id/role", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.UpdateUserRole)
			usersGroup.PUT("/:id/toggle", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.ToggleUserStatus)
			usersGroup.PUT("/:id/parent", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.UpdateUserParent)
			usersGroup.PUT("/:id/password", middleware.RequirePermission(deps.PermChecker, "users", "edit"), deps.AdminHandler.ResetUserPassword)
		}

		parallelGroup := api.Group("/parallel-groups").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			parallelGroup.GET("", deps.ParallelHandler.List)
			parallelGroup.GET("/:id", deps.ParallelHandler.Get)
			parallelGroup.POST("", deps.ParallelHandler.Create)
			parallelGroup.PUT("/:id", deps.ParallelHandler.Update)
			parallelGroup.PATCH("/:id", deps.ParallelHandler.Update)
			parallelGroup.DELETE("/:id", deps.ParallelHandler.Delete)
		}

		orgGroup := api.Group("/organizations").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			orgGroup.POST("", deps.OrganizationHandler.Create)
			orgGroup.GET("", deps.OrganizationHandler.List)
			orgGroup.GET("/:id", deps.OrganizationHandler.GetByID)
			orgGroup.PUT("/:id", deps.OrganizationHandler.Update)
			orgGroup.DELETE("/:id", deps.OrganizationHandler.Delete)
			orgGroup.POST("/:id/move", deps.OrganizationHandler.Move)
			orgGroup.PATCH("/:id/status", deps.OrganizationHandler.ToggleStatus)
			orgGroup.GET("/:id/tree", deps.OrganizationHandler.GetTree)
		}

		// Member Lifecycle Management APIs
		authMembers := api.Group("/members").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			// Member management (authenticated users with org permissions)
			authMembers.POST("/add", deps.MemberLifecycleHandler.AddMember)
			authMembers.PUT("/memberships/:id/update", deps.MemberLifecycleHandler.UpdateMembership)
			authMembers.DELETE("/memberships/:id/remove", deps.MemberLifecycleHandler.RemoveMember)
			authMembers.PATCH("/memberships/:id/deactivate", deps.MemberLifecycleHandler.DeactivateMember)
			authMembers.PATCH("/memberships/:id/reactivate", deps.MemberLifecycleHandler.ReactivateMember)
			
			// Cross-organization transfer
			authMembers.POST("/transfer/initiate", deps.MemberLifecycleHandler.TransferInitiate)
			authMembers.POST("/transfer/accept", deps.MemberLifecycleHandler.TransferAccept)
			authMembers.POST("/transfer/reject", deps.MemberLifecycleHandler.TransferReject)
			authMembers.GET("/transfers/list", deps.MemberLifecycleHandler.ListTransfers)
			
			// Bulk operations (admin privileges recommended)
			authMembers.POST("/bulk-add", deps.MemberLifecycleHandler.BulkAdd)
			authMembers.POST("/bulk-transfer", deps.MemberLifecycleHandler.BulkTransfer)
		}

		otaGroup := api.Group("/ota").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			// 闇€瑕佹潈闄愮殑绠＄悊鎺ュ彛
			otaGroup.GET("/firmware", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListFirmware)
			otaGroup.GET("/firmware/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetFirmware)
			otaGroup.POST("/firmware", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateFirmware)
			otaGroup.DELETE("/firmware/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteFirmware)
			// 鍗囩骇绠＄悊锛堟浛浠ｆ棫 /tasks锛?
			otaGroup.GET("/upgrades/dashboard", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradeDashboard)
			otaGroup.POST("/upgrades/push", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.PushUpgrade)
			otaGroup.GET("/upgrades/firmware/:firmwareId", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetFirmwareUpgradeDetails)
			otaGroup.POST("/upgrades/retry", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RetryUpgrade)
			otaGroup.POST("/upgrades/cancel", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.CancelUpgrade)
			otaGroup.DELETE("/upgrades/firmware/:firmwareId", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradesByFirmware)

			// 鍗囩骇鍖呯鐞?
			otaGroup.GET("/packages", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListUpgradePackages)
			otaGroup.GET("/packages/:id", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetUpgradePackage)
			otaGroup.POST("/packages", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateUpgradePackage)
			otaGroup.PUT("/packages/:id", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.UpdateUpgradePackage)
			otaGroup.DELETE("/packages/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteUpgradePackage)
			otaGroup.PATCH("/packages/:id/publish", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.PublishPackage)
			otaGroup.POST("/packages/push", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.PushPackageUpgrade)
			otaGroup.POST("/packages/:id/rollback", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackPackageUpgrade)
			otaGroup.GET("/packages/:id/details", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.GetPackageUpgradeDetails)

			// 鍗囩骇浠诲姟绠＄悊锛堟柊缁熶竴鎺ュ彛锛?
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

			// APP绔帴鍙ｏ紙鎵€鏈夌櫥褰曠敤鎴峰彲璁块棶锛?
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
			otaGroup.GET("/packages/available/:sn", deps.OTAHandler.GetAvailablePackages)
			otaGroup.POST("/rollback", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackUpgrade)
			otaGroup.POST("/rollback-to-published", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackToPublishedVersion)

			// App鐗堟湰绠＄悊
			otaGroup.GET("/app/check", deps.OTAHandler.CheckAppUpdate) // APP妫€鏌ユ洿鏂帮紙鏃犻渶棰濆鏉冮檺锛?
			otaGroup.GET("/app/versions", middleware.RequirePermission(deps.PermChecker, "ota", "view"), deps.OTAHandler.ListAppVersions)
			otaGroup.POST("/app/versions", middleware.RequirePermission(deps.PermChecker, "ota", "create"), deps.OTAHandler.CreateAppVersion)
			otaGroup.DELETE("/app/versions/:id", middleware.RequirePermission(deps.PermChecker, "ota", "delete"), deps.OTAHandler.DeleteAppVersion)
			otaGroup.PUT("/app/versions/:id/rollout", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.UpdateAppVersionRollout)
			otaGroup.POST("/app/versions/:id/rollback", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RollbackAppVersion)
			otaGroup.POST("/app/versions/:id/restore", middleware.RequirePermission(deps.PermChecker, "ota", "control"), deps.OTAHandler.RestoreAppVersion)
		}

		// Pipeline Health & DLQ Management APIs (Task 11, 12, 13)
		pipelineHealthGroup := api.Group("/system").Use(middleware.Auth(deps.JWTService, deps.AuthorizationContextValidator))
		{
			// Task 11: Pipeline health aggregation endpoints
			pipelineHealthGroup.GET("/pipeline-health", deps.PipelineHealthHandler.GetPipelineHealth)
			pipelineHealthGroup.GET("/pipeline-metrics", deps.PipelineHealthHandler.GetPipelineMetrics)
			
			// Task 12: DLQ management endpoints
			// NOTE: retry-all and clear use query param ?consumer_type=xxx to avoid
			// Gin wildcard conflict between :id and :consumer_type at the same path level.
			pipelineHealthGroup.GET("/dlq", deps.DLQHandler.List)
			pipelineHealthGroup.POST("/dlq/:id/retry", deps.DLQHandler.Retry)
			pipelineHealthGroup.DELETE("/dlq/:id", deps.DLQHandler.Delete)
			pipelineHealthGroup.POST("/dlq/retry-all", deps.DLQHandler.RetryAll)
			pipelineHealthGroup.DELETE("/dlq/all", deps.DLQHandler.Clear)
			pipelineHealthGroup.GET("/dlq/stats", deps.DLQHandler.Stats)
			
			// Task 13: SSE pipeline health stream (implemented in ws_handler.go)
			pipelineHealthGroup.GET("/pipeline-health/stream", handler.PipelineHealthSSE(deps.RDB))
		}
	}

	return router
}

func openFirmwareFile(root *os.Root, requestPath string) (*os.File, error) {
	name := strings.TrimPrefix(strings.TrimSpace(requestPath), "/")
	if name == "" {
		return nil, os.ErrNotExist
	}
	return root.Open(name)
}

func requestBodyLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		const (
			defaultLimit         = int64(2 << 20)
			firmwareUploadLimit  = int64(201 << 20)
			workOrderUploadLimit = int64(51 << 20)
		)
		limit := defaultLimit
		path := c.Request.URL.Path
		if c.Request.Method == http.MethodPost && path == "/api/v1/ota/firmware" {
			limit = firmwareUploadLimit
		} else if c.Request.Method == http.MethodPost && strings.HasPrefix(path, "/api/v1/work-orders/") && strings.HasSuffix(path, "/attachments") {
			limit = workOrderUploadLimit
		}
		if c.Request.ContentLength > limit {
			c.AbortWithStatusJSON(http.StatusRequestEntityTooLarge, gin.H{"code": -1, "message": "request body too large"})
			return
		}
		if c.Request.Body != nil {
			c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, limit)
		}
		c.Next()
	}
}

func setTimezone(tz string) error {
	// 缁熶竴浣跨敤 UTC 浣滀负鏈嶅姟绔椂鍖? 鍓嶇鏍规嵁绔欑偣 timezone 鍋氭湰鍦板寲鏄剧ず
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
	// 浣跨敤閰嶇疆鐨?CORS origins锛屾垨榛樿浠呭厑璁?localhost
	corsOrigins := cfg.CORS.AllowedOrigins
	if len(corsOrigins) == 0 {
		corsOrigins = []string{"http://localhost:5173", "http://localhost:3000"}
	}
	router.Use(middleware.CORS(corsOrigins))

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "db": false})
	})

	router.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusServiceUnavailable, gin.H{"code": -1, "message": "Database not available, please ensure PostgreSQL and Redis are running"})
	})

	return router
}
