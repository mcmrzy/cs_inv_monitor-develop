package routes

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync/atomic"
	"testing"
	"time"

	"api-gateway/internal/middleware"

	"github.com/alicebob/miniredis/v2"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const protocolRouteJWTSecret = "protocol-route-test-secret"

func signedProtocolRouteToken(t *testing.T, userID int, isSystemAdmin bool) string {
	t.Helper()
	now := time.Now().UTC()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"token_version": 2, "token_type": "access",
		"user_id": userID, "root_tenant_id": 100,
		"organization_id": 101, "membership_id": 102,
		"membership_version": 1, "session_version": 1,
		"session_id":            "route-session",
		"authorization_version": 1,
		"is_system_admin":       isSystemAdmin,
		"sub":                   strconv.Itoa(userID),
		"iss":                   middleware.DefaultJWTIssuer, "aud": middleware.DefaultAccessAudience,
		"jti":                   fmt.Sprintf("route-%d-%v", userID, isSystemAdmin),
		"iat":                   now.Add(-time.Minute).Unix(), "nbf": now.Add(-time.Minute).Unix(),
		"exp":                   now.Add(time.Hour).Unix(),
	})
	signed, err := token.SignedString([]byte(protocolRouteJWTSecret))
	require.NoError(t, err)
	return signed
}

func protocolRouteConfig(apiURL string, rbac *middleware.RBACMiddleware) Config {
	return Config{
		APIServer:      apiURL,
		DeviceServer:   apiURL,
		JWTSecret:      protocolRouteJWTSecret,
		GlobalRate:     1000,
		GlobalBurst:    1000,
		RBAC:           rbac,
		AllowedOrigins: []string{"*"},
	}
}

func performGatewayRequest(t *testing.T, engine http.Handler, path, token string) (int, string) {
	t.Helper()
	gateway := httptest.NewServer(engine)
	defer gateway.Close()

	req, err := http.NewRequest(http.MethodGet, gateway.URL+path, nil)
	require.NoError(t, err)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := gateway.Client().Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	require.NoError(t, err)
	return resp.StatusCode, string(body)
}

// userPermsCacheKey builds the Redis cache key used by the new RBAC middleware.
func userPermsCacheKey(userID int) string {
	return fmt.Sprintf("gw:user_perms:%d:101:102", userID)
}

func TestDeviceProtocolReadRoutesRequireJWTAndDevicesView(t *testing.T) {
	paths := []string{
		"/api/v1/devices/INV001/alarm-events",
		"/api/v1/devices/INV001/parallel-state",
		"/api/v1/devices/INV001/three-phase",
	}

	for _, path := range paths {
		t.Run(path, func(t *testing.T) {
			var backendHits atomic.Int32
			backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				backendHits.Add(1)
				assert.Equal(t, "42", r.Header.Get("X-User-ID"))
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`{"source":"api","ok":true}`))
			}))
			defer backend.Close()

			mr := miniredis.RunT(t)
			mr.Set("refresh_session:42:route-session", "digest")
			rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
			defer rdb.Close()
			rbac := middleware.NewRBACMiddleware(rdb, nil, 300)
			engine := Setup(protocolRouteConfig(backend.URL, rbac))

			t.Run("no token", func(t *testing.T) {
				status, _ := performGatewayRequest(t, engine, path, "")
				assert.Equal(t, http.StatusUnauthorized, status)
				assert.EqualValues(t, 0, backendHits.Load())
			})

			t.Run("no devices view but basic user GET allowed", func(t *testing.T) {
				mr.Set(userPermsCacheKey(42), "[]")
				status, body := performGatewayRequest(t, engine, path, signedProtocolRouteToken(t, 42, false))
				assert.Equal(t, http.StatusOK, status)
				assert.JSONEq(t, `{"source":"api","ok":true}`, body)
				assert.EqualValues(t, 1, backendHits.Load())
			})

			t.Run("devices view proxies to API", func(t *testing.T) {
				perms, err := json.Marshal([]middleware.PermissionEntry{
					{PermissionCode: "devices:view", DataScope: "organization"},
				})
				require.NoError(t, err)
				mr.Set(userPermsCacheKey(42), string(perms))
				// Use a new middleware instance so the previous negative memory cache
				// cannot influence this independent authorization case.
				engine = Setup(protocolRouteConfig(backend.URL, middleware.NewRBACMiddleware(rdb, nil, 300)))
				status, body := performGatewayRequest(t, engine, path, signedProtocolRouteToken(t, 42, false))
				assert.Equal(t, http.StatusOK, status)
				assert.JSONEq(t, `{"source":"api","ok":true}`, body)
				assert.EqualValues(t, 2, backendHits.Load())
			})
		})
	}
}

func TestDeviceProtocolReadRoute_SystemAdminBypassAndAPIObjectDenial(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Query().Get("foreign") == "1" {
			w.WriteHeader(http.StatusForbidden)
			_, _ = w.Write([]byte(`{"code":403,"message":"device not owned"}`))
			return
		}
		_, _ = w.Write([]byte(`{"source":"api","ok":true}`))
	}))
	defer backend.Close()

	mr := miniredis.RunT(t)
	mr.Set("refresh_session:1:route-session", "digest")
	mr.Set("refresh_session:42:route-session", "digest")
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	engine := Setup(protocolRouteConfig(backend.URL, middleware.NewRBACMiddleware(rdb, nil, 300)))

	t.Run("system admin bypasses RBAC", func(t *testing.T) {
		status, _ := performGatewayRequest(t, engine, "/api/v1/devices/INV001/three-phase", signedProtocolRouteToken(t, 1, true))
		assert.Equal(t, http.StatusOK, status)
	})

	t.Run("foreign object denial comes from API", func(t *testing.T) {
		perms, err := json.Marshal([]middleware.PermissionEntry{
			{PermissionCode: "devices:view", DataScope: "organization"},
		})
		require.NoError(t, err)
		mr.Set(userPermsCacheKey(42), string(perms))
		engine = Setup(protocolRouteConfig(backend.URL, middleware.NewRBACMiddleware(rdb, nil, 300)))

		status, body := performGatewayRequest(t, engine, "/api/v1/devices/FOREIGN/alarm-events?foreign=1", signedProtocolRouteToken(t, 42, false))
		assert.Equal(t, http.StatusForbidden, status)
		assert.JSONEq(t, `{"code":403,"message":"device not owned"}`, body)
	})
}
