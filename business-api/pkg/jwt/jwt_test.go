package jwt

import (
	"testing"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
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

	accessToken, refreshToken, err := j.GenerateToken(1, "13800138000", ptrInt(5))
	require.NoError(t, err)
	assert.NotEmpty(t, accessToken, "accessToken 不应为空")
	assert.NotEmpty(t, refreshToken, "refreshToken 不应为空")
	assert.NotEqual(t, accessToken, refreshToken, "两个 token 应不同")
}

func TestGenerateToken_不同用户生成不同Token(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token1, _, err := j.GenerateToken(1, "13800138000", ptrInt(5))
	require.NoError(t, err)

	token2, _, err := j.GenerateToken(2, "13900139000", ptrInt(1))
	require.NoError(t, err)

	assert.NotEqual(t, token1, token2)
}

// ==================== ParseToken ====================

func TestParseToken_正常解析(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	accessToken, _, err := j.GenerateToken(42, "13800138000", ptrInt(5))
	require.NoError(t, err)

	claims, err := j.ParseToken(accessToken)
	require.NoError(t, err)
	assert.Equal(t, int64(42), claims.UserID)
	assert.Equal(t, "13800138000", claims.Phone)
	if claims.Role != nil {
		assert.Equal(t, 5, *claims.Role)
	}
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

	accessToken, _, err := j.GenerateToken(1, "13800138000", ptrInt(5))
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

	token, _, err := j1.GenerateToken(1, "13800138000", ptrInt(5))
	require.NoError(t, err)

	claims, err := j2.ParseToken(token)
	assert.Error(t, err)
	assert.Nil(t, claims)
}

// ==================== GetJTI ====================

func TestGetJTI_AccessToken使用RegisteredClaimsID(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token, _, err := j.GenerateToken(1, "13800138000", ptrInt(5))
	require.NoError(t, err)

	claims, err := j.ParseToken(token)
	require.NoError(t, err)

	assert.NotEmpty(t, claims.ID)
	assert.Equal(t, claims.ID, j.GetJTI(claims))
}

func TestRefreshToken使用RegisteredClaimsID(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	refreshToken, err := j.GenerateRefreshToken(1, "13800138000", 5)
	require.NoError(t, err)

	claims, err := j.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	assert.NotEmpty(t, claims.ID)
}

// ==================== RefreshToken ====================

func TestRefreshToken_正常刷新(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token, _, err := j.GenerateToken(1, "13800138000", ptrInt(5))
	require.NoError(t, err)

	// 等待 1 秒确保时间戳不同（JWT 使用秒级精度）
	time.Sleep(1100 * time.Millisecond)

	newToken, err := j.RefreshToken(token)
	require.NoError(t, err)
	assert.NotEmpty(t, newToken)
	assert.NotEqual(t, token, newToken)

	// 新 token 应能正常解析且保留原始用户信息
	claims, err := j.ParseToken(newToken)
	require.NoError(t, err)
	assert.Equal(t, int64(1), claims.UserID)
	assert.Equal(t, "13800138000", claims.Phone)
	if claims.Role != nil {
		assert.Equal(t, 5, *claims.Role)
	}
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

	claims, err := j.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	assert.Equal(t, int64(1), claims.UserID)
}

// ==================== Claims 字段验证 ====================

func TestClaims_包含正确的时间声明(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	before := time.Now().UTC()
	token, _, err := j.GenerateToken(1, "13800138000", ptrInt(5))
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

func TestStrictAccessTokenContainsBoundAuthorizationContext(t *testing.T) {
	j := newTestJWT(15 * time.Minute)

	token, err := j.GenerateContextAccessToken(42, 100, 101, 1001, 3, 7, 11)
	require.NoError(t, err)

	claims, err := j.ParseAccessToken(token)
	require.NoError(t, err)
	assert.Equal(t, int64(42), claims.UserID)
	assert.Equal(t, int64(100), claims.RootTenantID)
	assert.Equal(t, int64(101), claims.OrganizationID)
	assert.Equal(t, int64(1001), claims.MembershipID)
	assert.Equal(t, int64(3), claims.MembershipVersion)
	assert.Equal(t, int64(7), claims.AuthorizationVersion)
	assert.Equal(t, int64(11), claims.SessionVersion)
	assert.Equal(t, TokenTypeAccess, claims.TokenType)
	assert.Equal(t, DefaultAccessAudience, claims.Audience[0])
	assert.NotEmpty(t, claims.ID)
	assert.Equal(t, claims.ID, j.GetJTI(claims))
}

func TestAccessAndRefreshTokensAreNotInterchangeable(t *testing.T) {
	j := newTestJWT(15 * time.Minute)
	accessToken, err := j.GenerateContextAccessToken(42, 100, 101, 1001, 3, 7, 11)
	require.NoError(t, err)
	refreshToken, err := j.GenerateRefreshToken(42, "13800138000", 5)
	require.NoError(t, err)

	_, err = j.ParseAccessToken(refreshToken)
	assert.Error(t, err)
	_, err = j.ParseRefreshToken(accessToken)
	assert.Error(t, err)
	_, err = j.ParseToken(refreshToken)
	assert.Error(t, err, "legacy ParseToken must remain access-only")

	refreshClaims, err := j.ParseRefreshToken(refreshToken)
	require.NoError(t, err)
	assert.Equal(t, TokenTypeRefresh, refreshClaims.TokenType)
	assert.Equal(t, int64(2), refreshClaims.TokenVersion)
	assert.Equal(t, DefaultRefreshAudience, refreshClaims.Audience[0])
	assert.NotEmpty(t, refreshClaims.ID)
}

func TestParseAccessTokenRejectsWrongAlgorithmIssuerAndAudience(t *testing.T) {
	j := newTestJWT(15 * time.Minute)
	now := time.Now().UTC()
	base := AccessClaims{
		UserID: 42, RootTenantID: 100, OrganizationID: 101, MembershipID: 1001,
		MembershipVersion: 3, AuthorizationVersion: 7, SessionVersion: 11,
		TokenType: TokenTypeAccess,
		RegisteredClaims: jwtlib.RegisteredClaims{
			Issuer: "inv-api-server-test", Audience: jwtlib.ClaimStrings{DefaultAccessAudience},
			ID: "strict-jti", IssuedAt: jwtlib.NewNumericDate(now), NotBefore: jwtlib.NewNumericDate(now),
			ExpiresAt: jwtlib.NewNumericDate(now.Add(15 * time.Minute)),
		},
	}

	wrongAlgorithm, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS384, base).SignedString([]byte("test-secret-key-for-unit-tests"))
	require.NoError(t, err)
	_, err = j.ParseAccessToken(wrongAlgorithm)
	assert.Error(t, err)

	wrongIssuer := base
	wrongIssuer.Issuer = "attacker"
	wrongIssuerToken, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, wrongIssuer).SignedString([]byte("test-secret-key-for-unit-tests"))
	require.NoError(t, err)
	_, err = j.ParseAccessToken(wrongIssuerToken)
	assert.Error(t, err)

	wrongAudience := base
	wrongAudience.Audience = jwtlib.ClaimStrings{"break-glass"}
	wrongAudienceToken, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, wrongAudience).SignedString([]byte("test-secret-key-for-unit-tests"))
	require.NoError(t, err)
	_, err = j.ParseAccessToken(wrongAudienceToken)
	assert.Error(t, err)
}

func TestParseAccessTokenRejectsMissingRequiredAuthorizationClaims(t *testing.T) {
	j := newTestJWT(15 * time.Minute)
	valid := AccessClaims{
		UserID: 42, RootTenantID: 100, OrganizationID: 101, MembershipID: 1001,
		MembershipVersion: 3, AuthorizationVersion: 7, SessionVersion: 11,
		TokenType: TokenTypeAccess,
	}
	tests := []struct {
		name   string
		mutate func(*AccessClaims)
	}{
		{"user", func(c *AccessClaims) { c.UserID = 0 }},
		{"root tenant", func(c *AccessClaims) { c.RootTenantID = 0 }},
		{"organization", func(c *AccessClaims) { c.OrganizationID = 0 }},
		{"membership", func(c *AccessClaims) { c.MembershipID = 0 }},
		{"membership version", func(c *AccessClaims) { c.MembershipVersion = 0 }},
		{"authorization version", func(c *AccessClaims) { c.AuthorizationVersion = 0 }},
		{"session version", func(c *AccessClaims) { c.SessionVersion = 0 }},
		{"token type", func(c *AccessClaims) { c.TokenType = "" }},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			claims := valid
			tc.mutate(&claims)
			now := time.Now().UTC()
			claims.RegisteredClaims = jwtlib.RegisteredClaims{
				Issuer: "inv-api-server-test", Audience: jwtlib.ClaimStrings{DefaultAccessAudience}, ID: "jti-" + tc.name,
				IssuedAt: jwtlib.NewNumericDate(now), NotBefore: jwtlib.NewNumericDate(now),
				ExpiresAt: jwtlib.NewNumericDate(now.Add(15 * time.Minute)),
			}
			token, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims).SignedString([]byte("test-secret-key-for-unit-tests"))
			require.NoError(t, err)
			_, err = j.ParseAccessToken(token)
			assert.Error(t, err)
		})
	}
}
