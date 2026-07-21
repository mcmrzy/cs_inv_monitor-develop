package service

import (
	"testing"
	"time"

	appjwt "inv-api-server/pkg/jwt"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestSwapRefreshTokenIsSingleUse(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	jwtInstance := appjwt.NewJWT(&appjwt.JWTConfig{
		Secret:            "test-secret",
		ExpireTime:        time.Hour,
		RefreshExpireTime: 24 * time.Hour,
		Issuer:            "test",
	})
	service := NewJWTService(jwtInstance, rdb)
	ctx := t.Context()
	oldToken, err := jwtInstance.GenerateRefreshTokenForSession(7, 1, "single-use-session")
	require.NoError(t, err)
	newToken, err := jwtInstance.GenerateRefreshTokenForSession(7, 1, "single-use-session")
	require.NoError(t, err)
	attackerToken, err := jwtInstance.GenerateRefreshTokenForSession(7, 1, "single-use-session")
	require.NoError(t, err)

	require.NoError(t, service.StoreRefreshToken(ctx, 7, oldToken, time.Hour))
	swapped, err := service.SwapRefreshToken(ctx, 7, oldToken, newToken, time.Hour)
	require.NoError(t, err)
	require.True(t, swapped)
	require.False(t, service.ValidateRefreshToken(ctx, 7, oldToken))
	require.True(t, service.ValidateRefreshToken(ctx, 7, newToken))

	swapped, err = service.SwapRefreshToken(ctx, 7, oldToken, attackerToken, time.Hour)
	require.NoError(t, err)
	require.False(t, swapped)
	require.False(t, service.ValidateRefreshToken(ctx, 7, attackerToken))
	require.False(t, service.ValidateRefreshToken(ctx, 7, newToken))
}

func TestBlacklistRejectsEmptyJTI(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	service := NewJWTService(nil, rdb)
	require.Error(t, service.AddToBlacklist(t.Context(), "", time.Hour))
	require.True(t, service.IsBlacklisted(t.Context(), ""))
}

func TestRevokeAllUserTokensInvalidatesIssuedSession(t *testing.T) {
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer rdb.Close()
	jwtInstance := appjwt.NewJWT(&appjwt.JWTConfig{
		Secret:            "test-secret",
		ExpireTime:        time.Hour,
		RefreshExpireTime: 24 * time.Hour,
		Issuer:            "test",
	})
	service := NewJWTService(jwtInstance, rdb)
	access, refresh, err := service.GenerateToken(9, "13800138000", 5)
	require.NoError(t, err)
	claims, err := service.ParseToken(access)
	require.NoError(t, err)
	require.NoError(t, service.StoreRefreshToken(t.Context(), 9, refresh, time.Hour))

	require.NoError(t, service.RevokeAllUserTokens(t.Context(), 9))
	revoked, err := service.IsUserSessionRevoked(t.Context(), 9, claims.IssuedAt.Time.UnixMilli())
	require.NoError(t, err)
	require.True(t, revoked)
	require.False(t, service.ValidateRefreshToken(t.Context(), 9, refresh))
}
