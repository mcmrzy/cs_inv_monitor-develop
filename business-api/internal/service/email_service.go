package service

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"html/template"
	"math/big"
	"strings"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gopkg.in/gomail.v2"
)

// EmailService 邮件发送服务。
// 所有系统邮件统一走「品牌信封 + 类型内容块」渲染（见 email_templates.go）：
// 渲染时优先读取 email_templates 表内的库内模板，读取失败/模板损坏时
// 自动回退内置默认模板，保证不因模板问题导致发信失败。
type EmailService struct {
	cache        *redis.Client
	cfg          config.EmailConfig
	cfgSvc       *ConfigService
	frontendURL  string
	templateRepo *repository.EmailTemplateRepository
}

func NewEmailService(cache *redis.Client, cfg config.EmailConfig, cfgSvc *ConfigService, frontendURL string, templateRepo *repository.EmailTemplateRepository) *EmailService {
	return &EmailService{cache: cache, cfg: cfg, cfgSvc: cfgSvc, frontendURL: frontendURL, templateRepo: templateRepo}
}

// effectiveEmailConfig 获取生效的 SMTP 配置（优先运行时配置，回退启动配置）。
func (s *EmailService) effectiveEmailConfig(ctx context.Context) config.EmailConfig {
	if s.cfgSvc != nil {
		return s.cfgSvc.GetEmailConfig(ctx)
	}
	return s.cfg
}

// isDevEmailConfig 未配置 SMTP 时视为开发模式（只记日志不实际发信）。
func isDevEmailConfig(cfg config.EmailConfig) bool {
	return cfg.Host == "" || cfg.Host == "smtp.example.com"
}

// validateSMTPConfig 校验 SMTP 认证信息完整性。
func validateSMTPConfig(cfg config.EmailConfig) error {
	if cfg.Username == "" || cfg.Password == "" || cfg.From == "" {
		logger.Error("SMTP配置不完整",
			zap.String("host", cfg.Host),
			zap.Bool("username_empty", cfg.Username == ""),
			zap.Bool("password_empty", cfg.Password == ""),
			zap.Bool("from_empty", cfg.From == ""))
		return fmt.Errorf("邮件服务配置错误：SMTP认证信息不完整")
	}
	return nil
}

// RenderEmail 渲染指定类型邮件的主题与完整 HTML。
// 库内模板优先，缺失/禁用/损坏时回退内置默认模板。
func (s *EmailService) RenderEmail(ctx context.Context, templateKey string, vars map[string]interface{}) (subject, html string, err error) {
	var tplSubject, tplBody string
	if s.templateRepo != nil {
		tpl, rerr := s.templateRepo.Get(ctx, templateKey)
		if rerr != nil {
			logger.Warn("读取库内邮件模板失败，回退内置默认模板",
				zap.String("template_key", templateKey), zap.Error(rerr))
		} else if tpl != nil && tpl.Enabled {
			tplSubject, tplBody = tpl.Subject, tpl.HTMLBody
		}
	}

	subject, body, err := renderEmailParts(templateKey, tplSubject, tplBody, vars)
	if err != nil {
		return "", "", fmt.Errorf("渲染邮件 %s: %w", templateKey, err)
	}

	vars = normalizeEmailVars(vars)
	html, err = RenderEmailEnvelope(asString(vars["Title"]), body, asString(vars["FooterNote"]))
	if err != nil {
		return "", "", fmt.Errorf("渲染邮件信封 %s: %w", templateKey, err)
	}
	return subject, html, nil
}

// renderAndSend 统一发送入口：渲染 + SMTP 发送。
// dev 模式（未配置 SMTP）下仅记录日志并返回 nil，保持原有降级语义。
func (s *EmailService) renderAndSend(ctx context.Context, templateKey, to string, vars map[string]interface{}) error {
	emailCfg := s.effectiveEmailConfig(ctx)
	if isDevEmailConfig(emailCfg) {
		logger.Warn("Email service not properly configured, skipping email",
			zap.String("template_key", templateKey))
		return nil
	}
	if err := validateSMTPConfig(emailCfg); err != nil {
		return err
	}

	subject, html, err := s.RenderEmail(ctx, templateKey, vars)
	if err != nil {
		return fmt.Errorf("渲染邮件失败: %w", err)
	}
	if err := s.sendHTML(to, subject, html, emailCfg); err != nil {
		return fmt.Errorf("邮件发送失败: %w", err)
	}
	return nil
}

// sendHTML 通过 SMTP 发送一封 HTML 邮件。
func (s *EmailService) sendHTML(to, subject, html string, cfg config.EmailConfig) error {
	m := gomail.NewMessage()
	m.SetHeader("From", cfg.From)
	m.SetHeader("To", to)
	m.SetHeader("Subject", subject)
	m.SetBody("text/html", html)

	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, cfg.Password)
	if cfg.UseSSL {
		d.SSL = true
		d.TLSConfig = &tls.Config{
			ServerName: cfg.Host,
		}
	}

	return d.DialAndSend(m)
}

// SendCode 发送验证码邮件（注册/重置密码等），验证码在邮件中大字号突出显示。
func (s *EmailService) SendCode(ctx context.Context, email, codeType string) error {
	key := fmt.Sprintf("email:%s:%s", email, codeType)
	cooldownKey := fmt.Sprintf("email:%s:%s:cooldown", email, codeType)

	exists, err := s.cache.Exists(ctx, cooldownKey).Result()
	if err != nil {
		return err
	}

	if exists > 0 {
		ttl, _ := s.cache.TTL(ctx, cooldownKey).Result()
		return fmt.Errorf("请等待 %d 秒后再发送", int(ttl.Seconds()))
	}

	code := generateEmailCode(6)

	emailCfg := s.effectiveEmailConfig(ctx)
	if !isDevEmailConfig(emailCfg) {
		title := getSubjectByCodeType(codeType)
		vars := map[string]interface{}{
			"ToEmail":    email,
			"Code":       code,
			"Title":      title,
			"Summary":    "感谢您使用 CS-INV 光伏逆变器监控平台，请使用以下验证码完成账户验证：",
			"Content":    "",
			"FooterNote": "如果非本人操作，请忽略此邮件，您的账号依然安全。",
		}
		if err := s.renderAndSend(ctx, EmailTemplateKeyVerification, email, vars); err != nil {
			return fmt.Errorf("邮件发送失败：%w", err)
		}
	} else {
		logger.Debug("Email code generated (dev mode)", zap.String("email", maskEmail(email)), zap.String("type", codeType))
	}

	pipe := s.cache.Pipeline()
	pipe.Set(ctx, key, code, 5*time.Minute)
	pipe.Set(ctx, cooldownKey, "1", 60*time.Second)
	_, err = pipe.Exec(ctx)
	return err
}

func (s *EmailService) VerifyCode(ctx context.Context, email, code, codeType string) bool {
	key := fmt.Sprintf("email:%s:%s", email, codeType)
	failKey := fmt.Sprintf("email:%s:%s:fail", email, codeType)

	storedCode, err := s.cache.Get(ctx, key).Result()
	if err != nil {
		return false
	}

	// 检查验证码尝试次数
	failCount, _ := s.cache.Get(ctx, failKey).Int()
	if failCount >= 5 {
		return false
	}

	if storedCode == code {
		pipe := s.cache.Pipeline()
		pipe.Del(ctx, key)
		pipe.Del(ctx, failKey)
		pipe.Exec(ctx)
		return true
	}

	// 记录失败次数
	s.cache.Incr(ctx, failKey)
	s.cache.Expire(ctx, failKey, 5*time.Minute)
	return false
}

func generateEmailCode(length int) string {
	code := make([]byte, length)
	for i := range code {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		code[i] = byte('0' + n.Int64())
	}
	return string(code)
}

// Helper function for subject
func getSubjectByCodeType(codeType string) string {
	switch codeType {
	case "register":
		return "注册验证码"
	case "reset_password":
		return "重置密码验证码"
	case "login":
		return "登录验证码"
	default:
		return "验证码"
	}
}

// MaskEmail masks the email address for logging purposes
func maskEmail(email string) string {
	parts := strings.Split(email, "@")
	if len(parts) != 2 || parts[0] == "" {
		return "***"
	}
	username := parts[0]
	domain := parts[1]
	if len(username) < 2 || domain == "" {
		return "***"
	}
	return string(username[0]) + "***@" + domain
}

// SendInvitationEmail sends invitation emails to new users
func (s *EmailService) SendInvitationEmail(toEmail, tokenHint, roleName, organizationName string, expiresHours int, senderName, invitePath string) error {
	ctx := context.Background()
	inviteURL := strings.TrimRight(s.frontendURL, "/") + invitePath
	// Content 使用 template.HTML 类型以保留 HTML 标签（如 <br>）不被转义
	contentHTML := template.HTML(fmt.Sprintf("分配角色：%s<br>邀请有效期：%d 小时<br>点击下方按钮即可接受邀请，注册或登录后自动加入该组织。", roleName, expiresHours))
	vars := map[string]interface{}{
		"ToEmail":          toEmail,
		"TokenHint":        tokenHint,
		"RoleName":         roleName,
		"OrganizationName": organizationName,
		"ExpiresHours":     fmt.Sprintf("%d", expiresHours),
		"SenderName":       senderName,
		"CompanyName":      strings.Split(senderName, " ")[0],
		"InviteURL":        inviteURL,
		"Title":            "邀请加入组织",
		"Summary":          fmt.Sprintf("%s 邀请您加入组织「%s」。", senderName, organizationName),
		"Content":          contentHTML,
		"ButtonText":       "接受邀请",
		"ButtonURL":        inviteURL,
		"FooterNote":       "如果您并未发起此邀请，请忽略此邮件或联系管理员。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyInvitation, toEmail, vars)
}

// SendTransferNotification sends device transfer notification emails
func (s *EmailService) SendTransferNotification(requesterEmail, deviceSN, fromOrg, toOrg, reason string, senderName string) error {
	ctx := context.Background()
	actionURL := strings.TrimRight(s.frontendURL, "/") + "/organizations"
	// Content 使用 template.HTML 类型以保留 HTML 标签（如 <br>）不被转义
	contentHTML := template.HTML(fmt.Sprintf("设备 SN：%s<br>转出组织：%s<br>转入组织：%s<br>转移原因：%s", deviceSN, fromOrg, toOrg, reason))
	vars := map[string]interface{}{
		"DeviceSN":   deviceSN,
		"FromOrg":    fromOrg,
		"ToOrg":      toOrg,
		"Reason":     reason,
		"SenderName": senderName,
		"ActionURL":  actionURL,
		"Title":      "设备转移通知",
		"Summary":    fmt.Sprintf("操作人：%s", senderName),
		"Content":    contentHTML,
		"ButtonText": "查看组织",
		"ButtonURL":  actionURL,
		"FooterNote": "如非本人操作，请尽快联系系统管理员。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyTransfer, "admin@example.com", vars)
}

// SendWelcomeEmail sends welcome emails to new users
func (s *EmailService) SendWelcomeEmail(toEmail, username string, senderName string) error {
	ctx := context.Background()
	homeURL := strings.TrimRight(s.frontendURL, "/")
	vars := map[string]interface{}{
		"ToEmail":    toEmail,
		"Username":   username,
		"SenderName": senderName,
		"Title":      "欢迎加入 CS-INV",
		"Summary":    fmt.Sprintf("您好，%s！", username),
		"Content":    "您的账号已创建成功。CS-INV 光伏逆变器监控平台支持实时监控、告警通知、OTA 升级与工单管理，立即开始体验吧。",
		"ButtonText": "进入平台",
		"ButtonURL":  homeURL,
		"FooterNote": "如果您并未注册此账号，请忽略此邮件。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyWelcome, toEmail, vars)
}

// SendPasswordReset sends password reset emails
func (s *EmailService) SendPasswordReset(token, username, userEmail string, senderName string) error {
	ctx := context.Background()
	tokenDisplay := token
	if len(tokenDisplay) > 8 {
		tokenDisplay = tokenDisplay[:8] + "****" // Only show first 8 chars for security
	}
	vars := map[string]interface{}{
		"Username":   username,
		"Token":      tokenDisplay,
		"ToEmail":    userEmail,
		"SenderName": senderName,
		"Title":      "重置密码",
		"Summary":    fmt.Sprintf("您好，%s！", username),
		"Content":    fmt.Sprintf("我们收到了您账号（%s）的密码重置请求。重置令牌：%s。请通过发起重置的页面继续操作。", userEmail, tokenDisplay),
		"ButtonText": "",
		"ButtonURL":  "",
		"FooterNote": "如果非本人操作，请忽略此邮件并确认账号安全。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyPasswordRst, userEmail, vars)
}

// SendNotificationEmail sends device alarm / OTA / online / offline notification emails
func (s *EmailService) SendNotificationEmail(toEmail, title, content, deviceSN string) error {
	ctx := context.Background()
	vars := map[string]interface{}{
		"ToEmail":  toEmail,
		"Title":    title,
		"Content":  content,
		"DeviceSN": deviceSN,
		"Summary":  "您可以在 App「通知中心」中查看详细记录。如不需要此类通知，可在 App「我的 - 消息通知设置」中关闭。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyNotification, toEmail, vars)
}

// SendDailyReportEmail sends daily generation statistics report emails
func (s *EmailService) SendDailyReportEmail(toEmail, username, content string) error {
	ctx := context.Background()
	vars := map[string]interface{}{
		"ToEmail":  toEmail,
		"Username": username,
		"Content":  content,
		"Title":    "每日发电统计报告",
		"Summary":  fmt.Sprintf("您好，%s！以下是您昨日的发电统计摘要：", username),
		"FooterNote": "报告数据来自设备上报记录，如有疑问请以 App 内数据为准。",
	}
	return s.renderAndSend(ctx, EmailTemplateKeyDailyReport, toEmail, vars)
}

// SendTestEmail 发送测试邮件（管理后台验证 SMTP 配置用），内容为通用模板示例。
func (s *EmailService) SendTestEmail(ctx context.Context, to string) error {
	emailCfg := s.effectiveEmailConfig(ctx)
	if isDevEmailConfig(emailCfg) {
		return fmt.Errorf("邮件服务未配置 SMTP，无法发送测试邮件")
	}
	if err := validateSMTPConfig(emailCfg); err != nil {
		return err
	}

	vars := testEmailSampleVars()
	vars["ButtonURL"] = strings.TrimRight(s.frontendURL, "/")
	vars["ButtonText"] = "访问管理后台"

	subject, html, err := s.RenderEmail(ctx, EmailTemplateKeyTest, vars)
	if err != nil {
		return fmt.Errorf("渲染测试邮件失败: %w", err)
	}
	if err := s.sendHTML(to, subject, html, emailCfg); err != nil {
		return fmt.Errorf("测试邮件发送失败: %w", err)
	}
	return nil
}
