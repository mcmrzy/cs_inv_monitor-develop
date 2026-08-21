package service

import (
	"bytes"
	"fmt"
	htmltemplate "html/template"
	"strings"
	texttemplate "text/template"
	"time"
)

// 统一邮件模板体系：
// 所有系统邮件共用一个品牌化「信封」（RenderEmailEnvelope），
// 各邮件类型只提供「内容块」（支持 Go template 占位变量），
// 渲染时由 EmailService 将内容块注入信封。
//
// 标准占位变量：
//   - Title / Summary / Content：标题、摘要、正文
//   - ButtonText / ButtonURL：主按钮文案与链接（可选）
//   - Code：验证码（大字号居中展示）
//   - FooterNote：页脚补充说明（渲染在信封页脚区）
//
// 各类型可同时携带原有业务变量（OrganizationName、DeviceSN 等），语义不丢失。

// 邮件模板 key（与 email_templates 表 template_key 对应）
const (
	EmailTemplateKeyVerification = "verification_code"
	EmailTemplateKeyInvitation   = "invitation_email"
	EmailTemplateKeyWelcome      = "welcome_email"
	EmailTemplateKeyPasswordRst  = "password_reset"
	EmailTemplateKeyTransfer     = "transfer_notification"
	EmailTemplateKeyNotification = "notification_email"
	EmailTemplateKeyDailyReport  = "daily_report"
	EmailTemplateKeyTest         = "test_email"
)

// emailBuiltinTemplate 内置默认模板（主题 + 内容块），
// 库内模板缺失/被禁用/渲染失败时回退使用，保证发信不因模板问题失败。
type emailBuiltinTemplate struct {
	Subject string
	Body    string
}

// emailButtonBlock 主按钮 HTML 片段（内联样式，邮件客户端兼容）。
// 移动端优化：100% 宽度，增大触控区域
const emailButtonBlock = `{{if and .ButtonText .ButtonURL}}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0 8px 0;">
    <tr>
        <td align="center" style="text-align:center;">
            <!--[if mso]>
            <v:shape xmlns:v="http://schemas.microsoft.com/vml/" href="{{.ButtonURL}}" fill="t" stroke="f" fillcolor="#1677ff" arcsize="6%" style="width:220px;height:44px;position:absolute;top:50%;transform:translateY(-50%);" type="button">
                <v:textbox style="mso-fit-shape-to-text:true" inset="12px,0px,12px,0px">
            <![endif]-->
            <a href="{{.ButtonURL}}" target="_blank" style="display:inline-block;padding:14px 32px;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;background-color:#1677ff;min-width:160px;text-align:center;">{{.ButtonText}}</a>
            <!--[if mso]>
                </v:textbox>
            </v:shape>
            <![endif]-->
        </td>
    </tr>
</table>
{{end}}`

// emailParagraphStyle 统一正文段落样式。
const emailParagraphStyle = "margin:0 0 14px 0;font-size:15px;line-height:1.7;color:#3E4A5E;"

// emailMutedStyle 统一次要文字样式。
const emailMutedStyle = "margin:0;font-size:13px;line-height:1.6;color:#8A94A6;"

// builtinEmailTemplates 各邮件类型的内置默认模板。
// 内容与 database/migrations/102_add_email_templates.up.sql 中的 seed 保持一致。
var builtinEmailTemplates = map[string]emailBuiltinTemplate{
	// 验证码（注册/登录/重置密码等）：验证码大字号居中突出显示
	EmailTemplateKeyVerification: {
		Subject: "【CSERGY】{{.Title}}",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
{{if .Code}}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
    <tr>
        <td align="center" style="background-color:#F0F7FF;border:2px solid #BAE0FF;border-radius:12px;padding:32px 16px;">
            <div style="font-size:36px;font-weight:800;letter-spacing:10px;color:#1677ff;font-family:Consolas,'Courier New',monospace;">{{.Code}}</div>
            <div style="margin-top:14px;font-size:13px;color:#8A94A6;line-height:1.5;">验证码 5 分钟内有效，请勿泄露给他人</div>
        </td>
    </tr>
</table>
{{end}}
{{if .Content}}<p style="` + emailParagraphStyle + `">{{.Content}}</p>{{end}}`,
	},

	// 组织邀请
	EmailTemplateKeyInvitation: {
		Subject: "【CSERGY】邀请加入组织 · {{.OrganizationName}}",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #1677ff;">
    <tr>
        <td class="mobile-card" style="padding:20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>
` + emailButtonBlock + `
<p style="` + emailMutedStyle + `">如按钮无法点击，请复制以下链接到浏览器打开：<br><span style="word-break:break-all;">{{.ButtonURL}}</span></p>`,
	},

	// 欢迎邮件
	EmailTemplateKeyWelcome: {
		Subject: "【CSERGY】欢迎加入平台",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<p style="` + emailParagraphStyle + `">{{.Content}}</p>
` + emailButtonBlock,
	},

	// 密码重置
	EmailTemplateKeyPasswordRst: {
		Subject: "【CSERGY】重置密码",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<p style="` + emailParagraphStyle + `">{{.Content}}</p>
` + emailButtonBlock + `
<p style="` + emailMutedStyle + `;">出于安全考虑，重置链接中的令牌仅显示前缀；请勿将重置链接提供给他人。</p>`,
	},

	// 设备转移通知
	EmailTemplateKeyTransfer: {
		Subject: "【CSERGY】设备转移通知",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #00D4FF;">
    <tr>
        <td class="mobile-card" style="padding:20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>
` + emailButtonBlock,
	},

	// 设备告警 / OTA/工单等系统通知
	EmailTemplateKeyNotification: {
		Subject: "【CSERGY】{{.Title}}",
		Body: `{{if .DeviceSN}}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 18px 0;">
    <tr>
        <td style="background-color:#F0F7FF;border:2px solid #BAE0FF;border-radius:8px;padding:10px 16px;font-size:14px;font-weight:600;color:#1677ff;letter-spacing:1px;">设备 SN：{{.DeviceSN}}</td>
    </tr>
</table>
{{end}}
<p style="` + emailParagraphStyle + `">{{.Content}}</p>
{{if .Summary}}<p style="` + emailMutedStyle + `">{{.Summary}}</p>{{end}}
` + emailButtonBlock,
	},

	// 每日发电统计报告
	EmailTemplateKeyDailyReport: {
		Subject: "【CSERGY】每日发电统计报告",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:18px 0;background-color:#F7F9FC;border-radius:10px;border-left:4px solid #1677ff;">
    <tr>
        <td class="mobile-card" style="padding:20px;font-size:14px;line-height:1.8;color:#3E4A5E;">{{.Content}}</td>
    </tr>
</table>`,
	},

	// 测试邮件（管理后台验证 SMTP 配置）
	EmailTemplateKeyTest: {
		Subject: "【CSERGY】测试邮件 / Test Email",
		Body: `<p style="` + emailParagraphStyle + `">{{.Summary}}</p>
<p style="` + emailParagraphStyle + `">{{.Content}}</p>
` + emailButtonBlock + `
<p style="` + emailMutedStyle + `">{{.FooterNote}}</p>`,
	},
}

// emailEnvelope 统一品牌信封模板。
// 表格布局 + 内联 CSS + 响应式媒体查询，不使用外部资源、position/float，
// 兼容 Gmail / Outlook / QQ 邮箱等主流客户端（渐变在 Outlook 下回退为纯色 #1677ff）。
// 响应式设计：PC 端固定宽度，移动端全宽自适应。
const emailEnvelope = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<title>{{.Title}}</title>
<style>
/* 移动端响应式样式 */
@media screen and (max-width: 600px) {
  .mobile-padding { padding: 24px 20px !important; }
  .mobile-button { width: 100% !important; box-sizing: border-box; padding: 14px 20px !important; font-size: 16px !important; }
  .mobile-text { font-size: 14px !important; line-height: 1.6 !important; }
  .mobile-card { padding: 14px 16px !important; }
  .mobile-header { padding: 20px 20px !important; }
  h1 { font-size: 20px !important; }
}
</style>
</head>
<body style="margin:0;padding:0;background-color:#F0F4FA;">
<div style="display:none;max-height:0;overflow:hidden;">{{.Title}}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F0F4FA;">
<tr>
<td align="center" style="padding:24px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;font-family:'PingFang SC','Microsoft YaHei',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;">
    <!-- 顶部品牌区：主色 #1677ff，点缀 #00D4FF -->
    <tr>
        <td class="mobile-header" style="background-color:#1677ff;background-image:linear-gradient(135deg,#1677ff 0%,#00D4FF 100%);border-radius:16px 16px 0 0;padding:20px 24px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                    <td style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:1px;">&#9728;&#65039; CSERGY</td>
                    <td align="right" style="color:#E6F7FF;font-size:12px;letter-spacing:1px;">光伏逆变器监控平台</td>
                </tr>
            </table>
        </td>
    </tr>
    <!-- 正文区 -->
    <tr>
        <td class="mobile-padding" style="background-color:#ffffff;padding:32px 24px;">
            <h1 style="margin:0 0 8px 0;font-size:20px;line-height:1.4;color:#1F2A3E;font-weight:700;">{{.Title}}</h1>
            <div style="height:3px;width:48px;background-color:#1677ff;border-radius:2px;margin:0 0 18px 0;"></div>
            {{.Content}}
        </td>
    </tr>
    <!-- 页脚：版权 + 免回复提示 -->
    <tr>
        <td style="background-color:#ffffff;border-radius:0 0 16px 16px;padding:16px 24px 20px;border-top:1px solid #EEF1F6;">
            {{if .FooterNote}}<p style="margin:0 0 8px 0;font-size:12px;line-height:1.6;color:#8A94A6;">{{.FooterNote}}</p>{{end}}
            <p style="margin:0;font-size:11px;line-height:1.5;color:#B0B8C4;">© {{.Year}} CSERGY · 光伏逆变器监控平台 Solar Inverter Monitoring<br>此邮件由系统自动发出，请勿直接回复。This is an automated message, please do not reply.</p>
        </td>
    </tr>
</table>
</td>
</tr>
</table>
</body>
</html>`

var emailEnvelopeTpl = htmltemplate.Must(htmltemplate.New("email_envelope").Parse(emailEnvelope))

// emailEnvelopeData 信封渲染数据。Content 为已渲染的内容块 HTML，
// 使用 htmltemplate.HTML 类型避免被二次转义。
type emailEnvelopeData struct {
	Title      string
	Content    htmltemplate.HTML
	FooterNote string
	Year       int
}

// RenderEmailEnvelope 渲染统一品牌信封：一个 Go 函数渲染信封，各类型只填内容块。
func RenderEmailEnvelope(title string, contentHTML string, footerNote string) (string, error) {
	var buf bytes.Buffer
	err := emailEnvelopeTpl.Execute(&buf, emailEnvelopeData{
		Title:      title,
		Content:    htmltemplate.HTML(contentHTML),
		FooterNote: footerNote,
		Year:       time.Now().Year(),
	})
	if err != nil {
		return "", fmt.Errorf("渲染邮件信封: %w", err)
	}
	return buf.String(), nil
}

// renderTemplateText 以 text/template 渲染主题（纯文本，不做 HTML 转义）。
func renderTemplateText(name, tplText string, vars map[string]interface{}) (string, error) {
	tpl, err := texttemplate.New(name).Option("missingkey=zero").Parse(tplText)
	if err != nil {
		return "", fmt.Errorf("解析模板 %s: %w", name, err)
	}
	var buf bytes.Buffer
	if err := tpl.Execute(&buf, vars); err != nil {
		return "", fmt.Errorf("执行模板 %s: %w", name, err)
	}
	return buf.String(), nil
}

// renderTemplateHTML 以 html/template 渲染内容块（变量值自动 HTML 转义）。
func renderTemplateHTML(name, tplText string, vars map[string]interface{}) (string, error) {
	tpl, err := htmltemplate.New(name).Option("missingkey=zero").Parse(tplText)
	if err != nil {
		return "", fmt.Errorf("解析模板 %s: %w", name, err)
	}
	var buf bytes.Buffer
	if err := tpl.Execute(&buf, vars); err != nil {
		return "", fmt.Errorf("执行模板 %s: %w", name, err)
	}
	return buf.String(), nil
}

// BuiltInEmailTemplate 返回指定类型的内置默认模板（主题+内容块），供服务与测试使用。
func BuiltInEmailTemplate(templateKey string) (subject, body string, ok bool) {
	t, found := builtinEmailTemplates[templateKey]
	if !found {
		return "", "", false
	}
	return t.Subject, t.Body, true
}

// KnownEmailTemplateKeys 返回全部已知模板 key（管理端校验用）。
func KnownEmailTemplateKeys() []string {
	return []string{
		EmailTemplateKeyVerification,
		EmailTemplateKeyInvitation,
		EmailTemplateKeyWelcome,
		EmailTemplateKeyPasswordRst,
		EmailTemplateKeyTransfer,
		EmailTemplateKeyNotification,
		EmailTemplateKeyDailyReport,
		EmailTemplateKeyTest,
	}
}

// ValidateEmailTemplate 校验主题与内容块模板语法是否可解析（管理端保存前校验）。
func ValidateEmailTemplate(subject, body string) error {
	if _, err := texttemplate.New("subject").Parse(subject); err != nil {
		return fmt.Errorf("主题模板语法错误: %w", err)
	}
	if _, err := htmltemplate.New("body").Parse(body); err != nil {
		return fmt.Errorf("内容模板语法错误: %w", err)
	}
	return nil
}

// testEmailSampleVars 测试邮件示例变量。
func testEmailSampleVars() map[string]interface{} {
	return map[string]interface{}{
		"Title":      "测试邮件 / Test Email",
		"Summary":    "这是一封来自 CSERGY 管理后台的测试邮件，用于验证 SMTP 配置与统一邮件模板。",
		"Content":    "如果您收到这封邮件，说明当前 SMTP 配置可以正常发信。This is a test message from the CSERGY admin console.",
		"ButtonText": "",
		"ButtonURL":  "",
		"Code":       "123456",
		"FooterNote": "本邮件为测试邮件，无需任何操作。This is a test email, no action is required.",
	}
}

// asString 从变量集合中安全取出字符串值。
func asString(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

// normalizeEmailVars 保证标准占位变量都存在（缺失补空串），模板渲染更稳定。
func normalizeEmailVars(vars map[string]interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(vars)+7)
	for k, v := range vars {
		out[k] = v
	}
	for _, k := range []string{"Title", "Summary", "Content", "ButtonText", "ButtonURL", "Code", "FooterNote"} {
		if _, ok := out[k]; !ok {
			out[k] = ""
		}
	}
	return out
}

// renderEmailParts 渲染主题与内容块；库内模板优先，失败回退内置默认。
// tplSubject/tplBody 为库内模板（空表示无库内模板或已禁用）。
func renderEmailParts(templateKey, tplSubject, tplBody string, vars map[string]interface{}) (subject, body string, err error) {
	vars = normalizeEmailVars(vars)
	def, ok := builtinEmailTemplates[templateKey]
	if !ok {
		return "", "", fmt.Errorf("未知邮件模板类型: %s", templateKey)
	}

	subjText := def.Subject
	if strings.TrimSpace(tplSubject) != "" {
		subjText = tplSubject
	}
	bodyText := def.Body
	if strings.TrimSpace(tplBody) != "" {
		bodyText = tplBody
	}

	subject, err = renderTemplateText(templateKey+":subject", subjText, vars)
	if err != nil && subjText != def.Subject {
		// 库内主题模板损坏：回退内置默认
		subject, err = renderTemplateText(templateKey+":subject:fallback", def.Subject, vars)
	}
	if err != nil {
		return "", "", fmt.Errorf("渲染邮件主题失败: %w", err)
	}

	body, err = renderTemplateHTML(templateKey+":body", bodyText, vars)
	if err != nil && bodyText != def.Body {
		// 库内内容块模板损坏：回退内置默认，保证发信不失败
		body, err = renderTemplateHTML(templateKey+":body:fallback", def.Body, vars)
	}
	if err != nil {
		return "", "", fmt.Errorf("渲染邮件内容块失败: %w", err)
	}
	return subject, body, nil
}
