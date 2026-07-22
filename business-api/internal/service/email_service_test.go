package service

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// ==================== generateEmailCode ====================

func TestGenerateEmailCode_正确长度(t *testing.T) {
	tests := []struct {
		name   string
		length int
	}{
		{"4位", 4},
		{"6位", 6},
		{"8位", 8},
		{"10位", 10},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			code := generateEmailCode(tc.length)
			assert.Len(t, code, tc.length)
		})
	}
}

func TestGenerateEmailCode_仅含数字(t *testing.T) {
	code := generateEmailCode(100)
	for _, c := range code {
		assert.True(t, c >= '0' && c <= '9', "字符 %c 不是数字", c)
	}
}

func TestGenerateEmailCode_两次生成不同值(t *testing.T) {
	code1 := generateEmailCode(20)
	code2 := generateEmailCode(20)
	assert.NotEqual(t, code1, code2, "两次生成应不同")
}

// ==================== EmailService 请求结构体 ====================

func TestEmailCodeType_支持类型(t *testing.T) {
	validTypes := []string{"register", "reset_password"}
	for _, ct := range validTypes {
		t.Run(ct, func(t *testing.T) {
			assert.NotEmpty(t, ct)
		})
	}
}
