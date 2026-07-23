package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	jwtpkg "inv-api-server/pkg/jwt"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

type fakeAuthorizationContextResolver struct {
	context model.AuthorizationSessionContext
	err     error
}

func (f fakeAuthorizationContextResolver) ResolveAuthorizationSessionContext(context.Context, int64, int64) (model.AuthorizationSessionContext, error) {
	return f.context, f.err
}

func (f fakeAuthorizationContextResolver) ResolveUserSessionVersion(context.Context, int64) (int64, error) {
	return f.context.SessionVersion, f.err
}

func (f fakeAuthorizationContextResolver) ResolveDefaultSessionContext(context.Context, int64) (model.AuthorizationSessionContext, error) {
	return f.context, f.err
}

func TestRequireRefreshSwapRejectsReplay(t *testing.T) {
	err := requireRefreshSwap(false, nil)
	var appErr *apperr.AppError
	require.ErrorAs(t, err, &appErr)
	require.Equal(t, http.StatusUnauthorized, appErr.HTTPCode)
}

func TestRequireRefreshSwapPreservesStoreFailure(t *testing.T) {
	storeErr := errors.New("redis unavailable")
	require.ErrorIs(t, requireRefreshSwap(false, storeErr), storeErr)
}

func TestSetAuthCookiesUsesStrictSameSiteAndHTTPOnly(t *testing.T) {
	gin.SetMode(gin.TestMode)
	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)

	setAuthCookies(ctx, "access", "refresh", time.Minute, time.Hour)
	cookies := recorder.Result().Cookies()
	require.Len(t, cookies, 2)
	for _, cookie := range cookies {
		require.True(t, cookie.HttpOnly)
		require.Equal(t, http.SameSiteStrictMode, cookie.SameSite)
	}
}

func TestAuthorizationContextIssuesOrganizationBoundAccessAndRotatesRefresh(t *testing.T) {
	gin.SetMode(gin.TestMode)
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	jwtInstance := jwtpkg.NewJWT(&jwtpkg.JWTConfig{
		Secret: "context-secret", Issuer: "inv-api-server",
		ExpireTime: 15 * time.Minute, RefreshExpireTime: 7 * 24 * time.Hour,
	})
	jwtService := service.NewJWTService(jwtInstance, rdb)
	refreshToken, err := jwtService.GenerateRefreshTokenWithVersion(7, 3)
	require.NoError(t, err)
	require.NoError(t, jwtService.StoreRefreshToken(context.Background(), 7, refreshToken, time.Hour))

	handler := &AuthHandler{
		jwtService: jwtService,
		contextResolver: fakeAuthorizationContextResolver{context: model.AuthorizationSessionContext{
			Actor:                model.ActorContext{UserID: 7, RootTenantID: 100, OrganizationID: 101, MembershipID: 102, MembershipVersion: 4},
			AuthorizationVersion: 5, SessionVersion: 3, Phone: "13800138000", LegacyRole: 5,
		}},
	}
	router := gin.New()
	router.POST("/api/v1/auth/context", handler.AuthorizationContext)
	body, _ := json.Marshal(gin.H{"organization_id": 101, "refresh_token": refreshToken})
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/context", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())

	var envelope struct {
		Data struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &envelope))
	claims, err := jwtService.ParseAccessToken(envelope.Data.AccessToken)
	require.NoError(t, err)
	require.Equal(t, int64(101), claims.OrganizationID)
	require.Equal(t, int64(5), claims.AuthorizationVersion)
	require.False(t, jwtService.ValidateRefreshToken(context.Background(), 7, refreshToken))
	require.True(t, jwtService.ValidateRefreshToken(context.Background(), 7, envelope.Data.RefreshToken))

	replayRequest := httptest.NewRequest(http.MethodPost, "/api/v1/auth/context", bytes.NewReader(body))
	replayRequest.Header.Set("Content-Type", "application/json")
	replayRecorder := httptest.NewRecorder()
	router.ServeHTTP(replayRecorder, replayRequest)
	require.Equal(t, http.StatusOK, replayRecorder.Code)
	var replayResp map[string]interface{}
	require.NoError(t, json.Unmarshal(replayRecorder.Body.Bytes(), &replayResp))
	require.Equal(t, float64(500), replayResp["code"], "body: %s", replayRecorder.Body.String())
	require.False(t, jwtService.ValidateRefreshToken(context.Background(), 7, envelope.Data.RefreshToken), "refresh replay must revoke the whole user session family")
}
