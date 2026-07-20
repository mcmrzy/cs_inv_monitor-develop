package jwt

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newTestJWT(expireTime time.Duration) *JWT {
	return NewJWT(&JWTConfig{
		Secret:            "test-secret-key-for-unit-tests",
		ExpireTime:        expireTime,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "inv-api-server-test",
	})
}

// ==================== GenerateToken ====================

func TestGenerateToken_成功生成Token对(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	accessToken, refreshToken, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)
	assert.NotEmpty(t, accessToken, "accessToken 不应为空")
	assert.NotEmpty(t, refreshToken, "refreshToken 不应为空")
	assert.NotEqual(t, accessToken, refreshToken, "两个 token 应不同")
}

func TestGenerateToken_不同用户生成不同Token(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token1, _, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)

	token2, _, err := j.GenerateToken(2, "13900139000", 1)
	require.NoError(t, err)

	assert.NotEqual(t, token1, token2)
}

// ==================== ParseToken ====================

func TestParseToken_正常解析(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	accessToken, _, err := j.GenerateToken(42, "13800138000", 5)
	require.NoError(t, err)

	claims, err := j.ParseToken(accessToken)
	require.NoError(t, err)
	assert.Equal(t, int64(42), claims.UserID)
	assert.Equal(t, "13800138000", claims.Phone)
	assert.Equal(t, 5, claims.Role)
	assert.Equal(t, TokenTypeAccess, claims.TokenType)
	assert.Equal(t, "inv-api-server-test", claims.Issuer)
}

func TestParseToken_无效Token返回错误(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	tests := []struct {
		name  string
		token string
	}{
		{"空字符串", ""},
		{"随机字符串", "not.a.valid.token"},
		{"篡改的token", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxfQ.tampered"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			claims, err := j.ParseToken(tc.token)
			assert.Error(t, err)
			assert.Nil(t, claims)
		})
	}
}

func TestParseToken_过期Token返回错误(t *testing.T) {
	// 使用极短过期时间
	j := newTestJWT(1 * time.Millisecond)

	accessToken, _, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)

	// 等待 token 过期
	time.Sleep(5 * time.Millisecond)

	claims, err := j.ParseToken(accessToken)
	assert.Error(t, err)
	assert.Nil(t, claims)
}

func TestParseToken_不同Secret无法解析(t *testing.T) {
	j1 := newTestJWT(15 * time.Minute)
	j2 := NewJWT(&JWTConfig{
		Secret:     "different-secret",
		ExpireTime: 15 * time.Minute,
		Issuer:     "other",
	})

	token, _, err := j1.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)

	claims, err := j2.ParseToken(token)
	assert.Error(t, err)
	assert.Nil(t, claims)
}

// ==================== GetJTI ====================

func TestGetJTI_AccessToken包含唯一JTI(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token, _, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)

	claims, err := j.ParseToken(token)
	require.NoError(t, err)

	assert.NotEmpty(t, claims.ID)
	assert.Equal(t, claims.ID, j.GetJTI(claims))
	assert.Equal(t, TokenTypeAccess, claims.TokenType)
}

func TestGetJTI_RefreshToken包含唯一JTI(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	refreshToken, err := j.GenerateRefreshToken(1, "13800138000", 5)
	require.NoError(t, err)

	claims, err := j.ParseToken(refreshToken)
	require.NoError(t, err)

	jti := j.GetJTI(claims)
	assert.NotEmpty(t, jti)
	assert.Equal(t, TokenTypeRefresh, claims.TokenType)
}

// ==================== RefreshToken ====================

func TestRefreshToken_正常刷新(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	_, token, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)

	// 等待 1 秒确保时间戳不同（JWT 使用秒级精度）
	time.Sleep(1100 * time.Millisecond)

	newToken, err := j.RefreshToken(token)
	require.NoError(t, err)
	assert.NotEmpty(t, newToken)
	assert.NotEqual(t, token, newToken)

	// 新 token 应能正常解析且保留原始用户信息
	claims, err := j.ParseAccessToken(newToken)
	require.NoError(t, err)
	assert.Equal(t, int64(1), claims.UserID)
	assert.Equal(t, "13800138000", claims.Phone)
	assert.Equal(t, 5, claims.Role)
}

func TestRefreshToken_拒绝AccessToken(t *testing.T) {
	j := newTestJWT(15 * time.Minute)
	accessToken, _, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)
	newToken, err := j.RefreshToken(accessToken)
	assert.Error(t, err)
	assert.Empty(t, newToken)
}

func TestRefreshToken_无效Token返回错误(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	newToken, err := j.RefreshToken("invalid-token")
	assert.Error(t, err)
	assert.Empty(t, newToken)
}

// ==================== GenerateRefreshToken ====================

func TestGenerateRefreshToken_独立生成(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	refreshToken, err := j.GenerateRefreshToken(1, "13800138000", 5)
	require.NoError(t, err)
	assert.NotEmpty(t, refreshToken)

	// refresh token 应能解析
	claims, err := j.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	assert.Equal(t, int64(1), claims.UserID)
}

// ==================== Claims 字段验证 ====================

func TestClaims_包含正确的时间声明(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	before := time.Now().UTC()
	token, _, err := j.GenerateToken(1, "13800138000", 5)
	require.NoError(t, err)
	after := time.Now().UTC()

	claims, err := j.ParseToken(token)
	require.NoError(t, err)

	// IssuedAt 应在 before 和 after 之间
	assert.True(t, !claims.IssuedAt.Time.Before(before.Add(-1*time.Second)))
	assert.True(t, !claims.IssuedAt.Time.After(after.Add(1*time.Second)))

	// ExpiresAt 应约为 IssuedAt + 15分钟
	expectedExpiry := claims.IssuedAt.Time.Add(15 * time.Minute)
	assert.WithinDuration(t, expectedExpiry, claims.ExpiresAt.Time, 1*time.Second)
}
