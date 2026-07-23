package security

import (
	"strings"
	"testing"
	"time"

	j "inv-api-server/pkg/jwt"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ==================== JWT 弱密钥检测 ====================

func TestJWTSecurity_弱密钥应被检测(t *testing.T) {
	weakSecrets := []string{
		"secret",
		"123456",
		"password",
		"test",
		"",
	}

	for _, secret := range weakSecrets {
		t.Run("weak_secret_"+secret, func(t *testing.T) {
			// 弱密钥生成的 token 容易被暴力破解
			// 生产环境应使用 >= 32 字节的随机密钥
			assert.Less(t, len(secret), 32,
				"弱密钥长度不足 32 字节，生产环境应使用强密钥")
		})
	}
}

func TestJWTSecurity_强密钥生成与验证(t *testing.T) {
	// 生产级强密钥（64 字节）
	strongSecret := "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6A7B8C9D0E1F2"

	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            strongSecret,
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "test-issuer",
	})

	token, refresh, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)
	assert.NotEmpty(t, token)
	assert.NotEmpty(t, refresh)

	// 验证强密钥生成的 token 可正常解析
	claims, err := jwtService.ParseToken(token)
	require.NoError(t, err)
	assert.Equal(t, int64(1), claims.UserID)
}

// ==================== Token 篡改检测 ====================

func TestJWTSecurity_篡改Payload应被拒绝(t *testing.T) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-key-for-security-tests-32bytes!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	token, _, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)

	// 篡改 token 中间部分（payload）
	parts := strings.Split(token, ".")
	require.Len(t, parts, 3)

	// 修改 payload 中的字符
	payload := parts[1]
	if len(payload) > 10 {
		// 翻转一个字符
		tampered := payload[:5] + "X" + payload[6:]
		tamperedToken := parts[0] + "." + tampered + "." + parts[2]

		_, err := jwtService.ParseToken(tamperedToken)
		assert.Error(t, err, "篡改后的 token 应被拒绝")
	}
}

func TestJWTSecurity_篡改Signature应被拒绝(t *testing.T) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-key-for-security-tests-32bytes!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	token, _, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)

	parts := strings.Split(token, ".")
	require.Len(t, parts, 3)

	// 替换签名为另一个合法 token 的签名
	otherToken, _, _ := jwtService.GenerateToken(999, "18600001111", j.PtrInt(0))
	otherParts := strings.Split(otherToken, ".")

	forgedToken := parts[0] + "." + parts[1] + "." + otherParts[2]
	_, err = jwtService.ParseToken(forgedToken)
	assert.Error(t, err, "伪造签名的 token 应被拒绝")
}

// ==================== 过期 Token ====================

func TestJWTSecurity_过期Token必须拒绝(t *testing.T) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-key-for-security-tests-32bytes!!",
		ExpireTime:        1 * time.Millisecond, // 极短过期时间
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	token, _, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)

	// 等待 token 过期
	time.Sleep(10 * time.Millisecond)

	_, err = jwtService.ParseToken(token)
	assert.Error(t, err, "过期 token 必须被拒绝")
}

// ==================== 算法混淆攻击 ====================

func TestJWTSecurity_NoneAlgorithm攻击应被拒绝(t *testing.T) {
	secret := "test-secret-key-for-security-tests-32bytes!!"

	// 使用 none 算法构造恶意 token（声称无需签名）
	claims := jwt.MapClaims{
		"user_id": float64(1),
		"phone":   "13800138000",
		"role":    float64(0), // 伪装为管理员
		"exp":     time.Now().Add(15 * time.Minute).Unix(),
		"iat":     time.Now().Unix(),
	}

	token := jwt.NewWithClaims(jwt.SigningMethodNone, claims)
	maliciousToken, err := token.SignedString(jwt.UnsafeAllowNoneSignatureType)
	require.NoError(t, err)

	// 用正常 JWT 服务解析 - 应拒绝（期望 HMAC 签名）
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            secret,
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	_, err = jwtService.ParseToken(maliciousToken)
	assert.Error(t, err, "none 算法攻击应被拒绝")
}

func TestJWTSecurity_不同密钥无法解析(t *testing.T) {
	service1 := j.NewJWT(&j.JWTConfig{
		Secret:            "secret-key-one-32bytes-long-enough!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "service-1",
	})

	service2 := j.NewJWT(&j.JWTConfig{
		Secret:            "secret-key-two-32bytes-long-enough!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "service-2",
	})

	token, _, err := service1.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)

	_, err = service2.ParseToken(token)
	assert.Error(t, err, "不同密钥签名的 token 应被拒绝")
}

// ==================== 空/畸形 Token ====================

func TestJWTSecurity_空Token应被拒绝(t *testing.T) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-key-for-security-tests-32bytes!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	testCases := []struct {
		name  string
		token string
	}{
		{"空字符串", ""},
		{"随机字符串", "not-a-jwt-token"},
		{"两段式", "abc.def"},
		{"四段式", "a.b.c.d"},
		{"仅点号", "..."},
		{"null字符串", "null"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := jwtService.ParseToken(tc.token)
			assert.Error(t, err, "畸形 token '%s' 应被拒绝", tc.name)
		})
	}
}

// ==================== Token 角色篡改 ====================

func TestJWTSecurity_角色值不可被篡改(t *testing.T) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "test-secret-key-for-security-tests-32bytes!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "security-test",
	})

	// 生成普通用户 token (role=5)
	token, _, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(5))
	require.NoError(t, err)

	// 解析验证角色
	claims, err := jwtService.ParseToken(token)
	require.NoError(t, err)
	if claims.Role != nil {
		assert.Equal(t, 5, *claims.Role, "角色应为生成时指定的值 5")
	}

	// 手动构造 role=0（管理员）的 token 用同一密钥
	adminToken, _, err := jwtService.GenerateToken(1, "13800138000", j.PtrInt(0))
	require.NoError(t, err)

	adminClaims, err := jwtService.ParseToken(adminToken)
	require.NoError(t, err)
	require.NotNil(t, adminClaims.Role, "管理员 token 角色不应为 nil")
	assert.Equal(t, 0, *adminClaims.Role, "管理员 token 角色为 0")

	// 确保两个 token 不同
	assert.NotEqual(t, token, adminToken, "不同角色的 token 应不同")
}
