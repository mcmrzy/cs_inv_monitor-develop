package service

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// ==================== maskPhone ====================

func TestMaskPhone_正常手机号(t *testing.T) {
	tests := []struct {
		name     string
		phone    string
		expected string
	}{
		{"11位手机号", "13800138000", "138****8000"},
		{"另一个号", "18612345678", "186****5678"},
		{"7位号码", "1234567", "123****4567"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := maskPhone(tc.phone)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestMaskPhone_短号码返回掩码(t *testing.T) {
	tests := []struct {
		name     string
		phone    string
		expected string
	}{
		{"空字符串", "", "***"},
		{"1位", "1", "***"},
		{"6位", "123456", "***"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := maskPhone(tc.phone)
			assert.Equal(t, tc.expected, result)
		})
	}
}

// ==================== maskEmail ====================

func TestMaskEmail_正常邮箱(t *testing.T) {
	tests := []struct {
		name     string
		email    string
		expected string
	}{
		{"标准邮箱", "test@example.com", "t***@example.com"},
		{"长用户名", "abcdefgh@gmail.com", "a***@gmail.com"},
		{"2位用户名", "ab@test.com", "a***@test.com"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := maskEmail(tc.email)
			assert.Equal(t, tc.expected, result)
		})
	}
}

func TestMaskEmail_边界情况(t *testing.T) {
	tests := []struct {
		name     string
		email    string
		expected string
	}{
		{"空字符串", "", "***"},
		{"无@符号", "noemail", "***"},
		{"@在首位", "@test.com", "***"},
		{"1位用户名+@", "a@b.com", "***"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := maskEmail(tc.email)
			assert.Equal(t, tc.expected, result)
		})
	}
}

// ==================== generateCode ====================

func TestGenerateCode_正确长度(t *testing.T) {
	tests := []struct {
		name   string
		length int
	}{
		{"4位", 4},
		{"6位", 6},
		{"8位", 8},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			code := generateCode(tc.length)
			assert.Len(t, code, tc.length)
		})
	}
}

func TestGenerateCode_仅含数字(t *testing.T) {
	code := generateCode(100) // 生成较长验证码以充分测试
	for _, c := range code {
		assert.True(t, c >= '0' && c <= '9', "字符 %c 不是数字", c)
	}
}

func TestGenerateCode_两次生成不同值(t *testing.T) {
	// 生成足够长的码以降低碰撞概率
	code1 := generateCode(20)
	code2 := generateCode(20)
	assert.NotEqual(t, code1, code2, "两次生成应不同")
}

// ==================== generateTaskID ====================

func TestGenerateTaskID_前缀正确(t *testing.T) {
	taskID := generateTaskID()
	assert.Contains(t, taskID, "cmd_")
	assert.Greater(t, len(taskID), 10, "taskID 应有足够长度")
}

func TestGenerateTaskID_两次生成不同值(t *testing.T) {
	id1 := generateTaskID()
	id2 := generateTaskID()
	assert.NotEqual(t, id1, id2, "两次生成应不同")
}

// ==================== systemCommands ====================

func TestSystemCommands_包含预期命令(t *testing.T) {
	expectedCommands := []string{
		"get_params", "set_params", "set_control",
		"set_alarm", "batch_config", "reset", "restart", "ota",
	}

	for _, cmd := range expectedCommands {
		t.Run(cmd, func(t *testing.T) {
			assert.True(t, systemCommands[cmd], "systemCommands 应包含 %s", cmd)
		})
	}
}

func TestSystemCommands_不包含普通命令(t *testing.T) {
	assert.False(t, systemCommands["unknown_cmd"])
	assert.False(t, systemCommands[""])
	assert.False(t, systemCommands["custom_field"])
}
