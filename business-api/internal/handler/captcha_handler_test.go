package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func newCaptchaTestHandler(t *testing.T) (*CaptchaHandler, *miniredis.Miniredis) {
	t.Helper()
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{Addr: server.Addr()})
	t.Cleanup(func() { _ = client.Close() })
	return NewCaptchaHandler(client), server
}

func performCaptchaVerify(handler *CaptchaHandler, body string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/captcha/verify", handler.VerifyCaptcha)
	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/captcha/verify", bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	router.ServeHTTP(recorder, request)
	return recorder
}

func performCaptchaGenerate(handler *CaptchaHandler) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/captcha/generate", handler.GenerateCaptcha)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/captcha/generate", nil))
	return recorder
}

func decodeCaptchaResponse(t *testing.T, recorder *httptest.ResponseRecorder) map[string]interface{} {
	t.Helper()
	var body map[string]interface{}
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &body))
	return body
}

func TestVerifyCaptchaRejectsMalformedJSON(t *testing.T) {
	handler, _ := newCaptchaTestHandler(t)
	recorder := performCaptchaVerify(handler, `{not-json`)
	require.Equal(t, http.StatusBadRequest, recorder.Code)
	require.Equal(t, float64(http.StatusBadRequest), decodeCaptchaResponse(t, recorder)["code"])
}

func createCaptchaChallenge(t *testing.T, handler *CaptchaHandler, redisServer *miniredis.Miniredis) (string, string) {
	t.Helper()
	recorder := performCaptchaGenerate(handler)
	require.Equal(t, http.StatusOK, recorder.Code)
	body := decodeCaptchaResponse(t, recorder)
	require.Equal(t, float64(0), body["code"])
	data := body["data"].(map[string]interface{})
	challengeID := data["challengeId"].(string)
	require.Contains(t, data["bgUrl"], "data:image/png;base64,")
	require.Contains(t, data["puzzleUrl"], "data:image/png;base64,")
	require.NotContains(t, data, "x")
	expectedX, err := redisServer.Get(captchaRedisKey("challenge:" + challengeID))
	require.NoError(t, err)
	return challengeID, expectedX
}

func TestVerifyCaptchaRejectsMissingChallenge(t *testing.T) {
	handler, _ := newCaptchaTestHandler(t)
	recorder := performCaptchaVerify(handler, `{"x":100,"duration":800}`)
	require.Equal(t, http.StatusBadRequest, recorder.Code)
}

func TestVerifyCaptchaRejectsImplausibleMovement(t *testing.T) {
	handler, redisServer := newCaptchaTestHandler(t)
	for _, values := range []struct {
		x        float64
		duration int64
	}{
		{x: -1, duration: 800},
		{x: 321, duration: 800},
		{x: 100, duration: 100},
		{x: 100, duration: 120001},
	} {
		challengeID, _ := createCaptchaChallenge(t, handler, redisServer)
		body := fmt.Sprintf(`{"challengeId":%q,"x":%v,"duration":%d}`, challengeID, values.x, values.duration)
		recorder := performCaptchaVerify(handler, body)
		require.Equal(t, float64(4031), decodeCaptchaResponse(t, recorder)["code"])
	}
}

func TestVerifyCaptchaStoresOneTimeToken(t *testing.T) {
	handler, redisServer := newCaptchaTestHandler(t)
	challengeID, expectedX := createCaptchaChallenge(t, handler, redisServer)
	requestBody := fmt.Sprintf(`{"challengeId":%q,"x":%s,"duration":800}`, challengeID, expectedX)
	recorder := performCaptchaVerify(handler, requestBody)
	body := decodeCaptchaResponse(t, recorder)
	require.Equal(t, float64(0), body["code"])
	data := body["data"].(map[string]interface{})
	token := data["verifyToken"].(string)
	require.True(t, redisServer.Exists(captchaRedisKey("verified:"+token)))

	replay := performCaptchaVerify(handler, requestBody)
	require.Equal(t, float64(4031), decodeCaptchaResponse(t, replay)["code"])
}

func TestVerifyCaptchaRejectsWrongCoordinateAndConsumesChallenge(t *testing.T) {
	handler, redisServer := newCaptchaTestHandler(t)
	challengeID, expectedRaw := createCaptchaChallenge(t, handler, redisServer)
	expected, err := strconv.Atoi(expectedRaw)
	require.NoError(t, err)
	wrongX := expected + captchaTolerance + 5
	if wrongX > captchaWidth {
		wrongX = expected - captchaTolerance - 5
	}
	requestBody := fmt.Sprintf(`{"challengeId":%q,"x":%d,"duration":800}`, challengeID, wrongX)

	recorder := performCaptchaVerify(handler, requestBody)
	require.Equal(t, float64(4031), decodeCaptchaResponse(t, recorder)["code"])
	require.False(t, redisServer.Exists(captchaRedisKey("challenge:"+challengeID)))
}
