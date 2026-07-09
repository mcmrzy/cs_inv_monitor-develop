package security

import (
	"regexp"
	"testing"
	"time"

	j "inv-api-server/pkg/jwt"
	"inv-api-server/pkg/sn"
	"inv-api-server/pkg/timezone"
)

// ==================== JWT 性能基准测试 ====================

func BenchmarkJWT_GenerateToken(b *testing.B) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "benchmark-secret-key-32bytes-long-enough!!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "benchmark",
	})

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, err := jwtService.GenerateToken(1, "13800138000", 5)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkJWT_ParseToken(b *testing.B) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "benchmark-secret-key-32bytes-long-enough!!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "benchmark",
	})

	token, _, _ := jwtService.GenerateToken(1, "13800138000", 5)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := jwtService.ParseToken(token)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkJWT_GenerateAndParse(b *testing.B) {
	jwtService := j.NewJWT(&j.JWTConfig{
		Secret:            "benchmark-secret-key-32bytes-long-enough!!!",
		ExpireTime:        15 * time.Minute,
		RefreshExpireTime: 7 * 24 * time.Hour,
		Issuer:            "benchmark",
	})

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		token, _, err := jwtService.GenerateToken(1, "13800138000", 5)
		if err != nil {
			b.Fatal(err)
		}
		_, err = jwtService.ParseToken(token)
		if err != nil {
			b.Fatal(err)
		}
	}
}

// ==================== SN 性能基准测试 ====================

func BenchmarkSN_Generate(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_, err := sn.GenerateSN("HI", "CN", "A001", time.Now(), i%99999)
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkSN_Validate(b *testing.B) {
	info, err := sn.GenerateSN("HI", "CN", "A001", time.Now(), 12345)
	if err != nil {
		b.Fatal(err)
	}
	testSN := info.String()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		sn.ValidateSN(testSN)
	}
}

func BenchmarkSN_Parse(b *testing.B) {
	info, err := sn.GenerateSN("HI", "CN", "A001", time.Now(), 12345)
	if err != nil {
		b.Fatal(err)
	}
	testSN := info.String()

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, err := sn.ParseSN(testSN)
		if err != nil {
			b.Fatal(err)
		}
	}
}

// ==================== 时区 性能基准测试 ====================

func BenchmarkTimezone_LoadLocation_Hit(b *testing.B) {
	// 预热缓存
	timezone.LoadLocation("Asia/Shanghai")

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		timezone.LoadLocation("Asia/Shanghai")
	}
}

func BenchmarkTimezone_LoadLocation_Miss(b *testing.B) {
	locations := []string{
		"America/New_York",
		"Europe/London",
		"Asia/Tokyo",
		"Australia/Sydney",
		"Pacific/Auckland",
		"Africa/Cairo",
		"America/Los_Angeles",
		"Europe/Berlin",
		"Asia/Kolkata",
		"America/Sao_Paulo",
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		timezone.LoadLocation(locations[i%len(locations)])
	}
}

// ==================== 输入验证性能基准测试 ====================

func BenchmarkContainsSQLInjection_Negative(b *testing.B) {
	input := "normal user input that is perfectly safe"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsSQLInjection(input)
	}
}

func BenchmarkContainsSQLInjection_Positive(b *testing.B) {
	input := "'; DROP TABLE users; --"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsSQLInjection(input)
	}
}

func BenchmarkContainsXSS_Negative(b *testing.B) {
	input := "normal text without any xss payload"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsXSS(input)
	}
}

func BenchmarkContainsXSS_Positive(b *testing.B) {
	input := `<script>alert('xss')</script>`

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsXSS(input)
	}
}

func BenchmarkContainsPathTraversal_Negative(b *testing.B) {
	input := "/firmware/v2.0.0.bin"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsPathTraversal(input)
	}
}

func BenchmarkContainsPathTraversal_Positive(b *testing.B) {
	input := "../../../etc/passwd"

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		containsPathTraversal(input)
	}
}

// ==================== 综合性能基准测试 ====================

func BenchmarkValidateSN(b *testing.B) {
	validSNRegex := regexp.MustCompile(`^[A-Z0-9-]{8,64}$`)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		validSNRegex.MatchString("CSI5000PRO")
	}
}
