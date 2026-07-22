// Package main is the entry point for api-gateway, the reverse proxy and traffic controller.
//
// Responsibilities:
//   - JWT token validation on all proxied requests
//   - Rate limiting (global + per-route)
//   - RBAC permission checking (via Redis cache)
//   - Request proxying to inv-api-server and inv-device-server
//
// Dependencies: Redis (RBAC cache, optional)
// Listens on: :8080
// Health endpoint: GET /health
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"api-gateway/internal/config"
	"api-gateway/internal/middleware"
	"api-gateway/internal/routes"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

func main() {
	configFile := flag.String("config", "config.yaml", "配置文件路径")
	flag.Parse()

	cfg, err := config.Load(*configFile)
	if err != nil {
		log.Fatalf("[GW] 加载配置失败: %v", err)
	}

	if err := cfg.Validate(); err != nil {
		log.Fatalf("[GW] %v", err)
	}

	rdb, err := initRedis(cfg)
	if err != nil {
		log.Printf("[GW] Redis 连接失败，RBAC 不可用: %v", err)
	}
	if rdb != nil {
		defer rdb.Close()
	}

	var pgPool *pgxpool.Pool
	pgPool, err = initDB(cfg)
	if err != nil {
		log.Printf("[GW] PostgreSQL 连接失败，RBAC 数据库回退不可用: %v", err)
	}
	if pgPool != nil {
		defer pgPool.Close()
	}

	var rbac *middleware.RBACMiddleware
	if cfg.RBAC.Enabled && rdb != nil {
		rbac = middleware.NewRBACMiddleware(rdb, pgPool, cfg.RBAC.CacheTTLSec)
		log.Printf("[GW] RBAC 权限控制已启用 (Redis缓存+DB回退, TTL=%ds)", cfg.RBAC.CacheTTLSec)
	} else if cfg.RBAC.Enabled {
		log.Println("[GW] RBAC 已启用但 Redis 不可用，权限校验将降级为仅角色检查")
		rbac = middleware.NewRBACMiddleware(nil, pgPool, cfg.RBAC.CacheTTLSec)
	}

	routeLimits := make([]middleware.RouteRateLimitConfig, 0, len(cfg.RouteRateLimits))
	for _, rl := range cfg.RouteRateLimits {
		routeLimits = append(routeLimits, middleware.RouteRateLimitConfig{
			PathPrefix: rl.PathPrefix,
			Rate:       rl.Rate,
			Burst:      rl.Burst,
		})
	}

	router := routes.Setup(routes.Config{
		APIServer:      cfg.Backends.APIServer,
		DeviceServer:   cfg.Backends.DeviceServer,
		JWTSecret:      cfg.JWT.Secret,
		JWTIssuer:      cfg.JWT.Issuer,
		JWTAudience:    cfg.JWT.Audience,
		GlobalRate:     cfg.RateLimit.Rate,
		GlobalBurst:    cfg.RateLimit.Burst,
		RouteLimits:    routeLimits,
		RBAC:           rbac,
		AllowedOrigins: cfg.CORS.AllowedOrigins,
		TrustedProxies: cfg.Server.TrustedProxies,
	})

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       0, // SSE 长连接需要无读取超时
		WriteTimeout:      0, // SSE 长连接需要无写超时
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	go func() {
		log.Printf("[GW] API Gateway v2.0 启动成功，监听端口 %d", cfg.Server.Port)
		log.Printf("[GW] 全局限流: rate=%.0f/s, burst=%d", cfg.RateLimit.Rate, cfg.RateLimit.Burst)
		if len(routeLimits) > 0 {
			log.Printf("[GW] 路由级别限流: %d 条规则", len(routeLimits))
		}
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[GW] 启动服务失败: %v", err)
		}
	}()

	gracefulShutdown(srv)
}

func initRedis(cfg *config.Config) (*redis.Client, error) {
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr(),
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		return nil, err
	}

	log.Println("[GW] Redis 连接成功")
	return rdb, nil
}

func initDB(cfg *config.Config) (*pgxpool.Pool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, cfg.DatabaseDSN())
	if err != nil {
		return nil, err
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, err
	}

	log.Printf("[GW] PostgreSQL 连接成功 (%s:%d/%s)", cfg.Database.Host, cfg.Database.Port, cfg.Database.Name)
	return pool, nil
}

func gracefulShutdown(srv *http.Server) {
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("[GW] 收到信号 %v，正在优雅关闭...", sig)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("[GW] 关闭服务出错: %v", err)
	}

	log.Println("[GW] 服务已停止")
}
