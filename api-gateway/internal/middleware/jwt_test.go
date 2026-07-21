package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
)

const testSecret = "test-secret-key-for-unit-tests"

const (
	testIssuer   = "inv-api-server-test"
	testAudience = "inv-channel-access-test"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// makeToken 生成测试用 JWT token
func makeToken(claims jwt.MapClaims, secret string) string {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, _ := token.SignedString([]byte(secret))
	return signed
}

func validAccessClaims() jwt.MapClaims {
	now := time.Now().UTC()
	return jwt.MapClaims{
		"token_version":         float64(2),
		"token_type":            "access",
		"user_id":               float64(42),
		"root_tenant_id":        float64(100),
		"organization_id":       float64(101),
		"membership_id":         float64(102),
		"membership_version":    float64(3),
		"session_version":       float64(4),
		"session_id":            "session-42",
		"authorization_version": float64(5),
		"phone":                 "13800001111",
		"role":                  float64(1),
		"sub":                   "42",
		"iss":                   testIssuer,
		"aud":                   testAudience,
		"jti":                   "access-jti-42",
		"iat":                   float64(now.Add(-time.Minute).Unix()),
		"nbf":                   float64(now.Add(-time.Minute).Unix()),
		"exp":                   float64(now.Add(time.Hour).Unix()),
	}
}

func defaultAccessClaims() jwt.MapClaims {
	claims := validAccessClaims()
	claims["iss"] = DefaultJWTIssuer
	claims["aud"] = DefaultAccessAudience
	return claims
}

func strictJWTAuth() gin.HandlerFunc {
	return JWTAuthWithConfig(JWTAuthConfig{
		Secret:   testSecret,
		Issuer:   testIssuer,
		Audience: testAudience,
	})
}

func serveProtectedRequest(t *testing.T, claims jwt.MapClaims, headers http.Header) *httptest.ResponseRecorder {
	t.Helper()
	router := gin.New()
	router.Use(strictJWTAuth())
	router.GET("/api/v1/devices", func(c *gin.Context) {
		values := make(map[string][]string)
		for key, value := range c.Request.Header {
			values[key] = append([]string(nil), value...)
		}
		c.JSON(http.StatusOK, values)
	})

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
	request.Header = headers.Clone()
	request.Header.Set("Authorization", "Bearer "+makeToken(claims, testSecret))
	router.ServeHTTP(recorder, request)
	return recorder
}

func TestStripUntrustedIdentityHeaders_RemovesSpoofedHeadersFromPublicRequests(t *testing.T) {
	router := gin.New()
	router.Use(StripUntrustedIdentityHeaders())
	router.GET("/public", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"user_id": c.GetHeader("X-User-ID"),
			"evil":    c.GetHeader("X-User-Evil"),
			"org_id":  c.GetHeader("X-Organization-ID"),
			"tenant":  c.GetHeader("X-Tenant-ID"),
		})
	})

	request := httptest.NewRequest(http.MethodGet, "/public", nil)
	request.Header.Add("X-User-ID", "attacker-1")
	request.Header.Add("x-user-id", "attacker-2")
	request.Header.Set("X-User-Evil", "admin")
	request.Header.Set("X-Organization-ID", "999")
	request.Header.Set("X-Tenant-ID", "999")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)

	assert.Equal(t, http.StatusOK, recorder.Code)
	assert.JSONEq(t, `{"user_id":"","evil":"","org_id":"","tenant":""}`, recorder.Body.String())
}

func TestJWTAuthWithConfig_OverwritesSpoofedIdentityHeadersWithSingleTrustedValues(t *testing.T) {
	headers := make(http.Header)
	for _, value := range []string{"attacker-1", "attacker-2"} {
		headers.Add("X-User-ID", value)
		headers.Add("X-Organization-ID", value)
	}
	headers.Set("X-User-Evil", "admin")
	headers.Set("X-Tenant-ID", "999")
	headers.Set("X-Membership-Version", "999")

	recorder := serveProtectedRequest(t, validAccessClaims(), headers)
	assert.Equal(t, http.StatusOK, recorder.Code)

	var forwarded map[string][]string
	assert.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &forwarded))
	assert.Equal(t, []string{"42"}, forwarded[http.CanonicalHeaderKey("X-User-ID")])
	assert.Equal(t, []string{"42"}, forwarded[http.CanonicalHeaderKey("X-User-Sub")])
	assert.Equal(t, []string{"100"}, forwarded[http.CanonicalHeaderKey("X-Tenant-ID")])
	assert.Equal(t, []string{"101"}, forwarded[http.CanonicalHeaderKey("X-Organization-ID")])
	assert.Equal(t, []string{"102"}, forwarded[http.CanonicalHeaderKey("X-Membership-ID")])
	assert.Equal(t, []string{"3"}, forwarded[http.CanonicalHeaderKey("X-Membership-Version")])
	assert.Equal(t, []string{"4"}, forwarded[http.CanonicalHeaderKey("X-Session-Version")])
	assert.Equal(t, []string{"session-42"}, forwarded[http.CanonicalHeaderKey("X-Session-ID")])
	assert.Equal(t, []string{"5"}, forwarded[http.CanonicalHeaderKey("X-Authorization-Version")])
	assert.Empty(t, forwarded[http.CanonicalHeaderKey("X-User-Evil")])
}

func TestJWTAuthWithConfig_RejectsMissingRequiredClaims(t *testing.T) {
	required := []string{
		"token_version", "token_type", "user_id", "root_tenant_id", "organization_id",
		"membership_id", "membership_version", "session_version", "session_id", "authorization_version",
		"sub", "iss", "aud", "jti", "iat", "nbf", "exp",
	}
	for _, claim := range required {
		t.Run(claim, func(t *testing.T) {
			claims := validAccessClaims()
			delete(claims, claim)
			recorder := serveProtectedRequest(t, claims, make(http.Header))
			assert.Equal(t, http.StatusUnauthorized, recorder.Code)
		})
	}
}

func TestJWTAuthWithConfig_RejectsInvalidClaimValuesAndTokenKinds(t *testing.T) {
	tests := []struct {
		name  string
		claim string
		value any
	}{
		{name: "refresh token", claim: "token_type", value: "refresh"},
		{name: "break glass token", claim: "token_type", value: "break_glass"},
		{name: "wrong token version", claim: "token_version", value: float64(1)},
		{name: "wrong issuer", claim: "iss", value: "attacker"},
		{name: "wrong audience", claim: "aud", value: "inv-channel-refresh-test"},
		{name: "subject mismatch", claim: "sub", value: "7"},
		{name: "empty token id", claim: "jti", value: ""},
		{name: "zero user", claim: "user_id", value: float64(0)},
		{name: "zero tenant", claim: "root_tenant_id", value: float64(0)},
		{name: "zero organization", claim: "organization_id", value: float64(0)},
		{name: "zero membership", claim: "membership_id", value: float64(0)},
		{name: "zero membership version", claim: "membership_version", value: float64(0)},
		{name: "zero session version", claim: "session_version", value: float64(0)},
		{name: "zero authorization version", claim: "authorization_version", value: float64(0)},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			claims := validAccessClaims()
			claims[test.claim] = test.value
			recorder := serveProtectedRequest(t, claims, make(http.Header))
			assert.Equal(t, http.StatusUnauthorized, recorder.Code, "claim %s=%v", test.claim, test.value)
		})
	}
}

func TestJWTAuthWithConfig_RejectsNonHS256Algorithms(t *testing.T) {
	for _, method := range []jwt.SigningMethod{jwt.SigningMethodHS384, jwt.SigningMethodHS512} {
		t.Run(method.Alg(), func(t *testing.T) {
			router := gin.New()
			router.Use(strictJWTAuth())
			router.GET("/api/v1/devices", func(c *gin.Context) { c.Status(http.StatusOK) })

			token := jwt.NewWithClaims(method, validAccessClaims())
			signed, err := token.SignedString([]byte(testSecret))
			assert.NoError(t, err)
			request := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
			request.Header.Set("Authorization", "Bearer "+signed)
			recorder := httptest.NewRecorder()
			router.ServeHTTP(recorder, request)
			assert.Equal(t, http.StatusUnauthorized, recorder.Code)
		})
	}
}

func TestJWTAuthWithConfig_InjectsIntegerClaimsWithoutFloatFormatting(t *testing.T) {
	claims := validAccessClaims()
	claims["user_id"] = float64(9007199254740990)
	claims["sub"] = strconv.FormatInt(9007199254740990, 10)
	recorder := serveProtectedRequest(t, claims, make(http.Header))
	assert.Equal(t, http.StatusOK, recorder.Code)
}

func TestJWTAuth_ValidToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"user_id": c.GetHeader("X-User-ID"),
			"role":    c.GetHeader("X-User-Role"),
			"phone":   c.GetHeader("X-User-Phone"),
		})
	})

	claims := defaultAccessClaims()
	token := makeToken(claims, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, "42", body["user_id"])
	assert.Equal(t, "1", body["role"])
	assert.Equal(t, "13800001111", body["phone"])
}

func TestJWTAuth_ExpiredToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	token := makeToken(jwt.MapClaims{
		"user_id": float64(1),
		"exp":     float64(time.Now().Add(-time.Hour).Unix()),
	}, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_ForgedToken(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	// 用不同的 secret 签名
	token := makeToken(jwt.MapClaims{
		"user_id": float64(1),
		"exp":     float64(time.Now().Add(time.Hour).Unix()),
	}, "wrong-secret")

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_MissingAuthHeader(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusUnauthorized, w.Code)
}

func TestJWTAuth_InvalidAuthFormat(t *testing.T) {
	tests := []struct {
		name   string
		header string
	}{
		{"no Bearer prefix", "some-token"},
		{"empty Bearer", "Bearer "},
		{"only Bearer", "Bearer"},
	}

	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/devices", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{})
	})

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/api/v1/devices", nil)
			req.Header.Set("Authorization", tt.header)
			router.ServeHTTP(w, req)

			assert.Equal(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestJWTAuth_PublicPaths(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})
	router.GET("/api/v1/auth/login", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	tests := []struct {
		name string
		path string
	}{
		{"health", "/health"},
		{"login", "/api/v1/auth/login"},
		{"metrics", "/metrics"},
		{"captcha prefix", "/api/v1/captcha/generate"},
		{"uploads prefix", "/uploads/image.png"},
		{"firmware prefix", "/firmware/v1.bin"},
		{"ws prefix", "/ws/conn"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", tt.path, nil)
			router.ServeHTTP(w, req)

			// 公开路径不应返回 401
			assert.NotEqual(t, http.StatusUnauthorized, w.Code)
		})
	}
}

func TestJWTAuth_ClaimsPropagation(t *testing.T) {
	router := gin.New()
	router.Use(JWTAuth(testSecret))
	router.GET("/api/v1/stations", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"x-user-id":    c.GetHeader("X-User-ID"),
			"x-user-role":  c.GetHeader("X-User-Role"),
			"x-user-phone": c.GetHeader("X-User-Phone"),
			"x-user-sub":   c.GetHeader("X-User-Sub"),
		})
	})

	claims := defaultAccessClaims()
	claims["user_id"] = float64(99)
	claims["role"] = float64(0)
	claims["phone"] = "13900000000"
	claims["sub"] = "99"
	token := makeToken(claims, testSecret)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/stations", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var body map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &body)
	assert.Equal(t, "99", body["x-user-id"])
	assert.Equal(t, "0", body["x-user-role"])
	assert.Equal(t, "13900000000", body["x-user-phone"])
	assert.Equal(t, "99", body["x-user-sub"])
}

func TestIsPublicPath(t *testing.T) {
	tests := []struct {
		path   string
		expect bool
	}{
		{"/health", true},
		{"/metrics", true},
		{"/api/v1/auth/login", true},
		{"/api/v1/auth/register", true},
		{"/api/v1/timezones", true},
		{"/uploads/test.png", true},
		{"/firmware/v1.bin", true},
		{"/ws/conn", true},
		{"/api/v1/captcha/generate", true},
		{"/api/v1/devices", false},
		{"/api/v1/admin/users", false},
		{"/api/v1/stations", false},
	}

	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			assert.Equal(t, tt.expect, isPublicPath(tt.path))
		})
	}
}
