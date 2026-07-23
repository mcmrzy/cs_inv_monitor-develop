//go:build integration

package integration

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// apiResponse mirrors the standard response envelope from inv_api_server.
type apiResponse struct {
	Code    int             `json:"code"`
	Message string          `json:"message"`
	Data    json.RawMessage `json:"data,omitempty"`
}

// loginResponse captures the auth token payload.
type loginResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

// ---------- helpers ----------

func doJSON(t *testing.T, client *http.Client, method, url string, body interface{}, token string) (*apiResponse, int) {
	t.Helper()

	var reqBody io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		require.NoError(t, err)
		reqBody = bytes.NewReader(b)
	}

	req, err := http.NewRequest(method, url, reqBody)
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := client.Do(req)
	require.NoError(t, err)
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	require.NoError(t, err)

	var apiResp apiResponse
	_ = json.Unmarshal(respBody, &apiResp)
	return &apiResp, resp.StatusCode
}

// doJSONWithRetry wraps doJSON and retries on HTTP 429 (rate limit) responses.
func doJSONWithRetry(t *testing.T, client *http.Client, method, url string, body interface{}, token string, maxRetries int) (*apiResponse, int) {
	t.Helper()
	var resp *apiResponse
	var status int
	for i := 0; i <= maxRetries; i++ {
		resp, status = doJSON(t, client, method, url, body, token)
		if status != http.StatusTooManyRequests {
			return resp, status
		}
		wait := time.Duration(500*(i+1)) * time.Millisecond
		t.Logf("429 rate limited on %s %s, retry %d/%d after %v", method, url, i+1, maxRetries, wait)
		time.Sleep(wait)
	}
	return resp, status
}

// setEmailCode stores a verification code through the isolated test Redis
// endpoint. It must never depend on a named developer/production container.
func setEmailCode(t *testing.T, email, codeType, code string) {
	t.Helper()
	cfg := LoadConfig()
	rdb := ConnectRedis(t, cfg)
	defer rdb.Close()

	redisKey := fmt.Sprintf("email:%s:%s", email, codeType)
	err := rdb.Set(context.Background(), redisKey, code, 5*time.Minute).Err()
	require.NoError(t, err, "test Redis SET failed")
}

func registerUser(t *testing.T, baseURL, phone, password string) {
	t.Helper()
	client := &http.Client{Timeout: 10 * time.Second}

	// Use email-register as phone registration may require SMS code
	email := fmt.Sprintf("test_%d@test.com", time.Now().UnixNano())
	nickname := fmt.Sprintf("testuser_%d", time.Now().UnixNano()%1000000)
	testCode := "123456"

	// Pre-store verification code in Redis so email-register can verify it
	setEmailCode(t, email, "register", testCode)

	payload := map[string]string{
		"email":    email,
		"phone":    phone,
		"password": password,
		"code":     testCode,
		"nickname": nickname,
	}
	resp, status := doJSONWithRetry(t, client, "POST", baseURL+"/api/v1/auth/email-register", payload, "", 5)
	t.Logf("register status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	require.Equal(t, 0, resp.Code, "registration should succeed")
}

func loginUser(t *testing.T, baseURL, account, password string) string {
	t.Helper()
	client := &http.Client{Timeout: 10 * time.Second}

	payload := map[string]string{
		"account":  account,
		"password": password,
	}
	resp, status := doJSONWithRetry(t, client, "POST", baseURL+"/api/v1/auth/login", payload, "", 5)
	require.Equal(t, 200, status, "login HTTP status")

	if resp.Code != 0 {
		t.Logf("login response: code=%d msg=%s", resp.Code, resp.Message)
	}
	require.Equal(t, 0, resp.Code, "login should succeed")

	var lr loginResponse
	err := json.Unmarshal(resp.Data, &lr)
	require.NoError(t, err)
	require.NotEmpty(t, lr.AccessToken, "access token should not be empty")
	return lr.AccessToken
}

// ---------- tests ----------

// TestHealthCheck verifies the gateway health endpoint.
func TestHealthCheck(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 5 * time.Second}
	// Use raw base URL which may contain port already; just call /health
	resp, err := client.Get(cfg.APIBaseURL + "/health")
	require.NoError(t, err, "API gateway health request failed")
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)

	var body map[string]interface{}
	err = json.NewDecoder(resp.Body).Decode(&body)
	require.NoError(t, err)
	assert.Equal(t, "ok", body["status"])
}

// TestAuthFlow tests the complete authentication lifecycle:
// register → login → get profile → refresh token → logout.
func TestAuthFlow(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}
	phone := fmt.Sprintf("138%08d", time.Now().UnixNano()%100000000)
	password := "TestPass@2026"

	// Step 1: Register
	registerUser(t, cfg.APIBaseURL, phone, password)

	// Step 2: Login
	token := loginUser(t, cfg.APIBaseURL, phone, password)
	require.NotEmpty(t, token)

	// Step 3: Get profile
	resp, status := doJSON(t, client, "GET", cfg.APIBaseURL+"/api/v1/auth/profile", nil, token)
	assert.Equal(t, 200, status)
	assert.Equal(t, 0, resp.Code, "get profile should succeed")

	// Step 4: Refresh token
	refreshPayload := map[string]string{"refresh_token": token} // reuse access token as refresh for simplicity
	resp, status = doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/auth/refresh", refreshPayload, token)
	t.Logf("refresh: status=%d code=%d msg=%s", status, resp.Code, resp.Message)

	// Step 5: Logout
	resp, status = doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/auth/logout", nil, token)
	assert.Equal(t, 200, status)
	t.Logf("logout: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
}

// TestEmailLoginFlow tests email-based registration and login.
func TestEmailLoginFlow(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}
	email := fmt.Sprintf("e2e_%d@test.com", time.Now().UnixNano())
	password := "E2E-Test@2026"
	nickname := fmt.Sprintf("e2euser_%d", time.Now().UnixNano()%1000000)
	testCode := "123456"

	// Pre-store verification code in Redis
	setEmailCode(t, email, "register", testCode)

	// Register
	regPayload := map[string]string{
		"email":    email,
		"phone":    fmt.Sprintf("139%08d", time.Now().UnixNano()%100000000),
		"password": password,
		"code":     testCode,
		"nickname": nickname,
	}
	resp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/auth/email-register", regPayload, "")
	t.Logf("email-register: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	require.Equal(t, 0, resp.Code, "email-register should succeed")

	// Login with email
	loginPayload := map[string]string{
		"email":    email,
		"password": password,
	}
	resp, status = doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/auth/email-login", loginPayload, "")
	assert.Equal(t, 200, status)
	t.Logf("email-login: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
}

// TestDeviceManagementFlow tests: bind device → list → get detail → unbind.
func TestDeviceManagementFlow(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}
	phone := fmt.Sprintf("137%08d", time.Now().UnixNano()%100000000)
	password := "DeviceTest@2026"

	// Register and login
	registerUser(t, cfg.APIBaseURL, phone, password)
	token := loginUser(t, cfg.APIBaseURL, phone, password)
	require.NotEmpty(t, token)

	testSN := fmt.Sprintf("E2E-TEST-%d", time.Now().UnixNano())

	// Step 1: Bind device
	bindPayload := map[string]interface{}{
		"sn":         testSN,
		"station_id": 0,
	}
	resp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/bind", bindPayload, token)
	t.Logf("bind: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	require.Equal(t, http.StatusOK, status, "bind HTTP status")
	require.Equal(t, 0, resp.Code, "bind should succeed")

	// Step 2: List devices
	resp, status = doJSON(t, client, "GET", cfg.APIBaseURL+"/api/v1/devices", nil, token)
	assert.Equal(t, 200, status)
	assert.Equal(t, 0, resp.Code, "list devices should succeed")
	t.Logf("list devices: status=%d code=%d", status, resp.Code)

	// Step 3: Get device detail
	resp, status = doJSON(t, client, "GET", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+testSN, nil, token)
	t.Logf("get device: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	require.Equal(t, http.StatusOK, status, "get device HTTP status")
	require.Equal(t, 0, resp.Code, "get device should succeed")

	// Step 4: Unbind the owned device through the same self-service path used by the app.
	resp, status = doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+testSN+"/unbind", nil, token)
	require.Equal(t, http.StatusOK, status, "unbind HTTP status")
	require.Equal(t, 0, resp.Code, "unbind should succeed")
}

// TestUnauthorizedAccess verifies that accessing protected endpoints without token fails.
func TestUnauthorizedAccess(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}

	endpoints := []struct {
		method string
		path   string
	}{
		{"GET", "/api/v1/devices"},
		{"GET", "/api/v1/stations"},
		{"GET", "/api/v1/alarms"},
		{"GET", "/api/v1/auth/profile"},
	}

	for _, ep := range endpoints {
		t.Run(ep.method+" "+ep.path, func(t *testing.T) {
			resp, status := doJSON(t, client, ep.method, cfg.APIBaseURL+ep.path, nil, "")
			// Should be 401 Unauthorized
			assert.Equal(t, http.StatusUnauthorized, status, "should require auth, got: %s", resp.Message)
		})
	}
}

// TestDataIsolation verifies user A cannot access user B's devices.
func TestDataIsolation(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}
	password := "Isolation@2026"

	// Create user A
	phoneA := fmt.Sprintf("136%08d", time.Now().UnixNano()%100000000)
	registerUser(t, cfg.APIBaseURL, phoneA, password)
	tokenA := loginUser(t, cfg.APIBaseURL, phoneA, password)

	// Create user B
	phoneB := fmt.Sprintf("135%08d", time.Now().UnixNano()%100000000)
	registerUser(t, cfg.APIBaseURL, phoneB, password)
	tokenB := loginUser(t, cfg.APIBaseURL, phoneB, password)

	// User A binds a device
	snA := fmt.Sprintf("ISO-A-%d", time.Now().UnixNano())
	bindPayload := map[string]interface{}{"sn": snA, "station_id": 0}
	resp, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/devices/bind", bindPayload, tokenA)
	t.Logf("userA bind: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	require.Equal(t, http.StatusOK, status, "user A bind HTTP status")
	require.Equal(t, 0, resp.Code, "user A bind should succeed")

	// User B should NOT see user A's device
	resp, status = doJSON(t, client, "GET", cfg.APIBaseURL+"/api/v1/devices/by-sn/"+snA, nil, tokenB)
	t.Logf("userB get userA device: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	// Expect: 404 or 403 or business error code indicating no access
	assert.NotEqual(t, 0, resp.Code, "user B must not see user A's device")
	assert.Contains(t, []int{http.StatusForbidden, http.StatusNotFound}, status)
}

// TestRateLimiting verifies the gateway rate limiting is active.
func TestRateLimiting(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")

	client := &http.Client{Timeout: 10 * time.Second}

	// Send many requests quickly to the login endpoint (rate: 10/s burst: 20)
	rateLimited := false
	for i := 0; i < 50; i++ {
		payload := map[string]string{"account": "ratelimit@test.com", "password": "wrong"}
		_, status := doJSON(t, client, "POST", cfg.APIBaseURL+"/api/v1/auth/login", payload, "")
		if status == http.StatusTooManyRequests {
			rateLimited = true
			break
		}
	}

	assert.True(t, rateLimited, "rate limiting should kick in after many rapid requests")
}
