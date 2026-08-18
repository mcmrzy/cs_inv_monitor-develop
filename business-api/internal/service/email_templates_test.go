package service

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// allTestVars 覆盖所有内置模板可能用到的变量。
func allTestVars() map[string]interface{} {
	vars := testEmailSampleVars()
	for k, v := range map[string]interface{}{
		"ToEmail":          "user@example.com",
		"OrganizationName": "示例组织",
		"RoleName":         "运维人员",
		"SenderName":       "管理员",
		"ExpiresHours":     "72",
		"TokenHint":        "abcd",
		"CompanyName":      "示例",
		"DeviceSN":         "SN123456",
		"FromOrg":          "组织A",
		"ToOrg":              "组织B",
		"Reason":           "转移",
		"ActionURL":        "https://example.com/organizations",
		"InviteURL":        "https://example.com/invite/abcd",
		"Username":         "tester",
		"Token":            "abcd1234****",
	} {
		vars[k] = v
	}
	return vars
}

// TestBuiltinTemplates_全部可渲染 所有内置模板（主题+内容块+信封）必须渲染成功。
func TestBuiltinTemplates_全部可渲染(t *testing.T) {
	for _, key := range KnownEmailTemplateKeys() {
		t.Run(key, func(t *testing.T) {
			subject, body, err := renderEmailParts(key, "", "", allTestVars())
			require.NoError(t, err)
			assert.NotEmpty(t, subject)
			assert.NotEmpty(t, body)

			html, err := RenderEmailEnvelope("标题", body, "页脚说明")
			require.NoError(t, err)
			assert.Contains(t, html, "CS-INV")
			assert.Contains(t, html, "#1677ff")
		})
	}
}

// TestRenderEmailParts_库内模板损坏回退内置 库内内容块语法错误时回退内置默认，不报错。
func TestRenderEmailParts_库内模板损坏回退内置(t *testing.T) {
	subject, body, err := renderEmailParts(
		EmailTemplateKeyNotification,
		"【CS-INV】{{.Title}", // 损坏的主题（多余大括号）
		"{{.Content",          // 损坏的内容块
		allTestVars(),
	)
	require.NoError(t, err)
	assert.Contains(t, subject, "测试邮件")
	assert.NotEmpty(t, body)
}

// TestRenderEmailParts_库内模板优先 库内模板有效时优先使用。
func TestRenderEmailParts_库内模板优先(t *testing.T) {
	subject, body, err := renderEmailParts(
		EmailTemplateKeyNotification,
		"自定义主题：{{.Title}}",
		"<p>自定义内容 {{.Content}}</p>",
		allTestVars(),
	)
	require.NoError(t, err)
	assert.Equal(t, "自定义主题：测试邮件 / Test Email", subject)
	assert.Contains(t, body, "自定义内容")
}

// TestRenderEmailEnvelope_品牌要素 信封包含品牌区、页脚与字体栈。
func TestRenderEmailEnvelope_品牌要素(t *testing.T) {
	html, err := RenderEmailEnvelope("注册验证码", "<p>内容</p>", "忽略提示")
	require.NoError(t, err)
	assert.Contains(t, html, "光伏逆变器监控平台")
	assert.Contains(t, html, "PingFang SC")
	assert.Contains(t, html, "Microsoft YaHei")
	assert.Contains(t, html, "请勿直接回复")
	assert.Contains(t, html, "忽略提示")
	assert.Contains(t, html, "max-width:600px")
}

// TestValidateEmailTemplate 保存前语法校验。
func TestValidateEmailTemplate(t *testing.T) {
	assert.NoError(t, ValidateEmailTemplate("【CS-INV】{{.Title}}", "<p>{{.Content}}</p>"))
	assert.Error(t, ValidateEmailTemplate("{{.Title", "<p>ok</p>"))
	assert.Error(t, ValidateEmailTemplate("ok", "<p>{{.Content</p>"))
}

// TestNormalizeEmailVars 标准占位变量补齐。
func TestNormalizeEmailVars(t *testing.T) {
	out := normalizeEmailVars(map[string]interface{}{"Title": "t"})
	for _, k := range []string{"Title", "Summary", "Content", "ButtonText", "ButtonURL", "Code", "FooterNote"} {
		_, ok := out[k]
		assert.True(t, ok, "缺少标准变量 %s", k)
	}
	assert.Equal(t, "t", out["Title"])
}

// TestVerificationCode_验证码突出显示 验证码邮件内容块必须包含大字号验证码展示。
func TestVerificationCode_验证码突出显示(t *testing.T) {
	vars := allTestVars()
	vars["Code"] = "654321"
	_, body, err := renderEmailParts(EmailTemplateKeyVerification, "", "", vars)
	require.NoError(t, err)
	assert.True(t, strings.Contains(body, "654321"))
	assert.True(t, strings.Contains(body, "font-size:36px"), "验证码应大字号显示")
}
