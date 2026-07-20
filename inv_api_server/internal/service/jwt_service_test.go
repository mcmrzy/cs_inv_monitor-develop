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

	require.NoError(t, service.StoreRefreshToken(ctx, 7, "old", time.Hour))
	swapped, err := service.SwapRefreshToken(ctx, 7, "old", "new", time.Hour)
	require.NoError(t, err)
	require.True(t, swapped)
	require.False(t, service.ValidateRefreshToken(ctx, 7, "old"))
	require.True(t, service.ValidateRefreshToken(ctx, 7, "new"))

	swapped, err = service.SwapRefreshToken(ctx, 7, "old", "attacker", time.Hour)
	require.NoError(t, err)
	require.False(t, swapped)
	require.False(t, service.ValidateRefreshToken(ctx, 7, "attacker"))
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
	claims, err := service.ParseAccessToken(access)
	require.NoError(t, err)
	require.NoError(t, service.StoreRefreshToken(t.Context(), 9, refresh, time.Hour))

	require.NoError(t, service.RevokeAllUserTokens(t.Context(), 9))
	revoked, err := service.IsUserSessionRevoked(t.Context(), 9, claims.SessionIAT)
	require.NoError(t, err)
	require.True(t, revoked)
	require.False(t, service.ValidateRefreshToken(t.Context(), 9, refresh))
}
