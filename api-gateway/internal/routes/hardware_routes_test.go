package routes

import (
	"io"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"

	"api-gateway/internal/middleware"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func hardwareRequest(t *testing.T, engine http.Handler, method, path, token string) (int, string) {
	t.Helper()
	gateway := httptest.NewServer(engine)
	defer gateway.Close()
	req, err := http.NewRequest(method, gateway.URL+path, nil)
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

func TestHardwareRoutesAuthenticationAndAuthorization(t *testing.T) {
	cases := []struct {
		name, method, path, permissions string
		authenticated, admin            bool
		backendStatus, wantStatus       int
		wantBackend                     bool
	}{
		{"catalog requires login", "GET", "/api/v1/hardware/board-types", "[]", false, false, 200, 401, false},
		{"catalog is a login reference read", "GET", "/api/v1/hardware/board-types?model=CS-L10-6K2&target_chip=dsp", "[]", true, false, 200, 200, true},
		{"registry requires devices view", "GET", "/api/v1/hardware/devices/INV001", "[]", true, false, 200, 403, false},
		{"registry with devices view", "GET", "/api/v1/hardware/devices/INV001", `[{"permission_code":"devices:view","data_scope":"organization"}]`, true, false, 200, 200, true},
		{"history with devices view", "GET", "/api/v1/hardware/devices/INV001/history?page=1", `[{"permission_code":"devices:view","data_scope":"organization"}]`, true, false, 200, 200, true},
		{"foreign registry denied downstream", "GET", "/api/v1/hardware/devices/FOREIGN", `[{"permission_code":"devices:view","data_scope":"organization"}]`, true, false, 403, 403, true},
		{"history requires devices view", "GET", "/api/v1/hardware/devices/INV001/history", "[]", true, false, 200, 403, false},
		{"catalog write denied for ordinary user", "POST", "/api/v1/hardware/board-types", "[]", true, false, 200, 403, false},
		{"registry write denied for ordinary user", "POST", "/api/v1/hardware/devices/INV001/verify", "[]", true, false, 200, 403, false},
		{"registry write retains business admin denial", "POST", "/api/v1/hardware/devices/INV001/verify", `[{"permission_code":"devices:create","data_scope":"organization"}]`, true, false, 403, 403, true},
		{"catalog unsupported method stays missing", "PUT", "/api/v1/hardware/board-types", "[]", true, true, 200, 404, false},
		{"unknown hardware path stays missing", "GET", "/api/v1/hardware/unknown", "[]", true, true, 200, 404, false},
		{"unknown registry action stays missing", "POST", "/api/v1/hardware/devices/INV001/unknown", "[]", true, true, 200, 404, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var hits atomic.Int32
			backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				hits.Add(1)
				assert.Equal(t, tc.method, r.Method)
				assert.Equal(t, tc.path, r.URL.RequestURI())
				assert.Equal(t, "42", r.Header.Get("X-User-ID"))
				w.WriteHeader(tc.backendStatus)
			}))
			defer backend.Close()
			mr := miniredis.RunT(t)
			mr.Set("refresh_session:42:route-session", "digest")
			mr.Set(userPermsCacheKey(42), tc.permissions)
			rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
			defer rdb.Close()
			engine := Setup(protocolRouteConfig(backend.URL, middleware.NewRBACMiddleware(rdb, nil, 300)))
			token := ""
			if tc.authenticated {
				token = signedProtocolRouteToken(t, 42, tc.admin)
			}
			status, body := hardwareRequest(t, engine, tc.method, tc.path, token)
			assert.Equal(t, tc.wantStatus, status, body)
			assert.Equal(t, tc.wantBackend, hits.Load() == 1)
		})
	}
}

func TestHardwareAdministrationRoutesReachBusinessAuthorization(t *testing.T) {
	paths := []struct{ method, path string }{
		{"POST", "/api/v1/hardware/board-types"},
		{"POST", "/api/v1/hardware/devices/INV001/verify"},
		{"POST", "/api/v1/hardware/devices/INV001/corrections"},
		{"POST", "/api/v1/hardware/devices/INV001/service-changes"},
		{"POST", "/api/v1/hardware/devices/INV001/freeze"},
		{"POST", "/api/v1/hardware/imports"},
		{"GET", "/api/v1/hardware/imports/1"},
		{"POST", "/api/v1/hardware/imports/1/commit"},
	}
	for _, route := range paths {
		t.Run(route.method+" "+route.path, func(t *testing.T) {
			backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assert.Equal(t, route.path, r.URL.Path)
				assert.Equal(t, "true", r.Header.Get("X-Is-System-Admin"))
				// Business authorization and validation responses must be preserved.
				w.WriteHeader(http.StatusUnprocessableEntity)
			}))
			defer backend.Close()
			engine := Setup(protocolRouteConfig(backend.URL, middleware.NewRBACMiddleware(nil, nil, 300)))
			status, body := hardwareRequest(t, engine, route.method, route.path, signedProtocolRouteToken(t, 42, true))
			assert.Equal(t, http.StatusUnprocessableEntity, status, body)
		})
	}
}
