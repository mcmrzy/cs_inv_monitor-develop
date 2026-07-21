package service

import (
	"context"
	"testing"
	"time"

	jwtpkg "inv-api-server/pkg/jwt"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func newSecurityJWTService(t *testing.T) (*JWTService, *miniredis.Miniredis, *redis.Client) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	jwtInstance := jwtpkg.NewJWT(&jwtpkg.JWTConfig{
		Secret: "test-secret", Issuer: "inv-api-server",
		ExpireTime: time.Minute, RefreshExpireTime: time.Hour,
	})
	return NewJWTService(jwtInstance, rdb), mr, rdb
}

func TestJWTServiceStoresRefreshTokenByDigestAndRotatesOnce(t *testing.T) {
	service, mr, rdb := newSecurityJWTService(t)
	defer rdb.Close()
	ctx := context.Background()
	oldToken, err := service.GenerateRefreshTokenWithVersion(7, 1)
	require.NoError(t, err)
	oldClaims, err := service.ParseRefreshToken(oldToken)
	require.NoError(t, err)
	newToken, err := service.GenerateRefreshTokenForSession(7, 1, oldClaims.SessionID)
	require.NoError(t, err)

	require.NoError(t, service.StoreRefreshToken(ctx, 7, oldToken, time.Hour))
	for _, key := range mr.Keys() {
		require.NotContains(t, key, oldToken)
	}
	require.True(t, service.ValidateRefreshToken(ctx, 7, oldToken))

	swapped, err := service.SwapRefreshToken(ctx, 7, oldToken, newToken, time.Hour)
	require.NoError(t, err)
	require.True(t, swapped)
	replayOutput, err := service.GenerateRefreshTokenForSession(7, 1, oldClaims.SessionID)
	require.NoError(t, err)
	swapped, err = service.SwapRefreshToken(ctx, 7, oldToken, replayOutput, time.Hour)
	require.NoError(t, err)
	require.False(t, swapped)
	require.False(t, service.ValidateRefreshToken(ctx, 7, newToken))
}

func TestJWTServiceBlacklistFailsClosedWhenRedisUnavailable(t *testing.T) {
	service, mr, rdb := newSecurityJWTService(t)
	mr.Close()
	defer rdb.Close()
	require.True(t, service.IsBlacklisted(context.Background(), "jti"))
}
