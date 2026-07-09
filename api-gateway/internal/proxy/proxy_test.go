package proxy

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// ===================== NewReverseProxy =====================

func TestNewReverseProxy_ValidTarget(t *testing.T) {
	rp := NewReverseProxy("http://localhost:8080")
	require.NotNil(t, rp)
	assert.Equal(t, "http://localhost:8080", rp.Target())
	assert.NotNil(t, rp.proxy)
}

func TestNewReverseProxy_HTTPSTarget(t *testing.T) {
	rp := NewReverseProxy("https://api.example.com:443")
	require.NotNil(t, rp)
	assert.Equal(t, "https://api.example.com:443", rp.Target())
}

func TestNewReverseProxy_WithBasePath(t *testing.T) {
	rp := NewReverseProxy("http://backend:3000/api")
	require.NotNil(t, rp)
	assert.Contains(t, rp.Target(), "backend:3000")
}

// ===================== Director =====================

func TestDirector_RewritesRequestURL(t *testing.T) {
	rp := NewReverseProxy("http://backend:8080")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
	req.Header.Set("Host", "gateway.example.com")

	rp.proxy.Director(req)

	assert.Equal(t, "http", req.URL.Scheme)
	assert.Equal(t, "backend:8080", req.URL.Host)
	assert.Equal(t, "/api/v1/devices", req.URL.Path)
	assert.Equal(t, "backend:8080", req.Host)
	assert.Equal(t, "gateway.example.com", req.Header.Get("X-Forwarded-Host"))
}

func TestDirector_TrimsTrailingSlash(t *testing.T) {
	rp := NewReverseProxy("http://backend:8080")

	tests := []struct {
		name     string
		path     string
		wantPath string
	}{
		{"trailing slash removed", "/api/v1/devices/", "/api/v1/devices"},
		{"root slash kept", "/", "/"},
		{"no trailing slash", "/api/v1/devices", "/api/v1/devices"},
		{"nested trailing slash", "/api/v1/users/123/", "/api/v1/users/123"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			rp.proxy.Director(req)
			assert.Equal(t, tt.wantPath, req.URL.Path)
		})
	}
}

func TestDirector_SetsForwardedHost(t *testing.T) {
	rp := NewReverseProxy("http://backend:8080")

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Host", "my-gateway.io")

	rp.proxy.Director(req)

	assert.Equal(t, "my-gateway.io", req.Header.Get("X-Forwarded-Host"))
}

// ===================== Handler =====================

func TestHandler_ReturnsGinHandler(t *testing.T) {
	rp := NewReverseProxy("http://localhost:8080")
	handler := rp.Handler()
	assert.NotNil(t, handler)
}

// ===================== RewriteHandler =====================

func newTestGinEngine(handler gin.HandlerFunc, routePath string) *gin.Engine {
	r := gin.New()
	r.Any(routePath, handler)
	return r
}

func TestRewriteHandler_RewritesPath(t *testing.T) {
	var receivedPath string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedPath = r.URL.Path
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	rp := NewReverseProxy(backend.URL)

	engine := newTestGinEngine(rp.RewriteHandler("/api/v1/alarms"), "/api/v1/alerts/*action")
	gateway := httptest.NewServer(engine)
	defer gateway.Close()

	resp, err := http.Get(gateway.URL + "/api/v1/alerts/123")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	assert.Equal(t, "/api/v1/alarms/123", receivedPath)
}

func TestRewriteHandler_RewritesPathNoSuffix(t *testing.T) {
	var receivedPath string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedPath = r.URL.Path
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	rp := NewReverseProxy(backend.URL)

	engine := newTestGinEngine(rp.RewriteHandler("/api/v1/alarms"), "/api/v1/alerts")
	gateway := httptest.NewServer(engine)
	defer gateway.Close()

	resp, err := http.Get(gateway.URL + "/api/v1/alerts")
	require.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
	assert.Equal(t, "/api/v1/alarms", receivedPath)
}

// ===================== ErrorHandler =====================

func TestErrorHandler_Returns502(t *testing.T) {
	rp := NewReverseProxy("http://127.0.0.1:1")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
	rec := httptest.NewRecorder()

	rp.proxy.ErrorHandler(rec, req, http.ErrNoLocation)

	assert.Equal(t, http.StatusBadGateway, rec.Code)
	assert.Contains(t, rec.Body.String(), "502")
}

// ===================== Integration: proxy to test server =====================

func TestProxy_ForwardsToBackend(t *testing.T) {
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"message":"hello from backend"}`))
	}))
	defer backend.Close()

	rp := NewReverseProxy(backend.URL)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/test", nil)
	rec := httptest.NewRecorder()

	rp.proxy.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Body.String(), "hello from backend")
}

func TestProxy_ForwardsRequestBody(t *testing.T) {
	var receivedBody string
	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		buf := make([]byte, 1024)
		n, _ := r.Body.Read(buf)
		receivedBody = string(buf[:n])
		w.WriteHeader(http.StatusOK)
	}))
	defer backend.Close()

	rp := NewReverseProxy(backend.URL)

	body := strings.NewReader(`{"key":"value"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/test", body)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	rp.proxy.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, receivedBody, `"key":"value"`)
}

func TestProxy_BackendUnavailable(t *testing.T) {
	rp := NewReverseProxy("http://127.0.0.1:1")

	req := httptest.NewRequest(http.MethodGet, "/api/v1/test", nil)
	rec := httptest.NewRecorder()

	rp.proxy.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusBadGateway, rec.Code)
	assert.Contains(t, rec.Body.String(), "502")
}

// ===================== Target =====================

func TestTarget_ReturnsFullURL(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"http://localhost:8080", "http://localhost:8080"},
		{"https://api.example.com:443", "https://api.example.com:443"},
		{"http://127.0.0.1:3000", "http://127.0.0.1:3000"},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			rp := NewReverseProxy(tt.input)
			assert.Equal(t, tt.want, rp.Target())
		})
	}
}
