package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/jwt"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

// setupStreamRouter 构建最小路由：仅 JWTService 指向 miniredis，其余依赖为 nil
//（本测试只验证 SSE 流路由的鉴权行为，其余 handler 永远不会被调用）。
// 返回 router 与其中的 JWTService，便于测试用同一 Redis 生成有效令牌。
func setupStreamRouter(t *testing.T) (*gin.Engine, *service.JWTService) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	mr, err := miniredis.Run()
	require.NoError(t, err)
	t.Cleanup(mr.Close)

	jwtInstance := jwt.NewJWT(&jwt.JWTConfig{
		Secret:            "test-secret",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "test",
	})
	jwtSvc := service.NewJWTService(jwtInstance, redis.NewClient(&redis.Options{Addr: mr.Addr()}))

	// setupRouter 会创建固件目录，重定向到临时路径避免 CI 无 /data 写权限
	t.Setenv("FIRMWARE_DATA_DIR", filepath.Join(os.TempDir(), "firmware_test_stream"))

	cfg := &config.Config{
		Server:   config.ServerConfig{Port: 8080, Mode: "test"},
		CORS:     config.CORSConfig{AllowedOrigins: []string{"http://localhost:5173"}},
		Backends: config.BackendsConfig{InternalKey: "test-key"},
	}
	return setupRouter(cfg, &RouterDeps{JWTService: jwtSvc}), jwtSvc
}

func generateStreamAccessToken(t *testing.T, jwtSvc *service.JWTService) string {
	t.Helper()
	refreshToken, err := jwtSvc.GenerateRefreshTokenWithVersion(9, 1)
	require.NoError(t, err)
	refreshClaims, err := jwtSvc.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	require.NoError(t, jwtSvc.StoreRefreshToken(context.Background(), 9, refreshToken, time.Hour))
	accessToken, err := jwtSvc.GenerateContextAccessTokenForSession(9, 100, 101, 102, 1, 1, 1, refreshClaims.SessionID, "13700137000", false)
	require.NoError(t, err)
	return accessToken
}

// TestPipelineHealthStreamRoute_NoTokenRejected 边界用例：SSE 流路由不携带任何
// token 时返回 401，鉴权不可绕过。
func TestPipelineHealthStreamRoute_NoTokenRejected(t *testing.T) {
	router, _ := setupStreamRouter(t)

	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/system/pipeline-health/stream", nil)
	router.ServeHTTP(w, req)

	require.Equal(t, http.StatusUnauthorized, w.Code)
}

// TestPipelineHealthStreamRoute_QueryTokenAllowed 正向用例：通过 ?token= 查询参数
//（EventSource 无法携带 Authorization 头）可完成鉴权并进入 SSE handler。
func TestPipelineHealthStreamRoute_QueryTokenAllowed(t *testing.T) {
	router, jwtSvc := setupStreamRouter(t)

	accessToken := generateStreamAccessToken(t, jwtSvc)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/system/pipeline-health/stream?token="+accessToken, nil)
	ctx, cancel := context.WithCancel(req.Context())
	req = req.WithContext(ctx)

	w := httptest.NewRecorder()
	// SSE handler 持续推送，测试在收到 connected 事件后取消请求上下文结束
	done := make(chan struct{})
	go func() {
		defer close(done)
		router.ServeHTTP(w, req)
	}()
	time.Sleep(300 * time.Millisecond)
	cancel()
	<-done

	require.Equal(t, http.StatusOK, w.Code)
	require.Equal(t, "text/event-stream", w.Header().Get("Content-Type"))
	require.Contains(t, w.Body.String(), "event: connected")
}
