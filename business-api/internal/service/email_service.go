package service

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"html/template"
	"math/big"
	"path/filepath"
	"strings"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gopkg.in/gomail.v2"
)

type EmailService struct {
	cache  *redis.Client
	cfg    config.EmailConfig
	cfgSvc *ConfigService
}

func NewEmailService(cache *redis.Client, cfg config.EmailConfig, cfgSvc *ConfigService) *EmailService {
	return &EmailService{cache: cache, cfg: cfg, cfgSvc: cfgSvc}
}

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

	emailCfg := s.cfg
	if s.cfgSvc != nil {
		emailCfg = s.cfgSvc.GetEmailConfig(ctx)
	}

	if emailCfg.Host != "" && emailCfg.Host != "smtp.example.com" {
		// Use template for better formatting
		data := map[string]string{
			"ToEmail": email,
			"Code":    code,
			"Subject": getSubjectByCodeType(codeType),
		}
		if err := s.sendMailWithTemplate(email, data, "verification_code.tmpl", emailCfg); err != nil {
			return fmt.Errorf("邮件发送失败：%v", err)
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

func (s *EmailService) sendMail(to, code, codeType string, cfg config.EmailConfig) error {
	m := gomail.NewMessage()
	m.SetHeader("From", cfg.From)
	m.SetHeader("To", to)

	subject := "验证码"
	switch codeType {
	case "register":
		subject = "注册验证码"
	case "reset_password":
		subject = "重置密码验证码"
	}

	m.SetHeader("Subject", subject)
	m.SetBody("text/html", fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>CSERGY 验证码</title>
</head>
<body style="margin:0; padding:0; background-color:#EFF2F7; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Helvetica, Arial, sans-serif;">
    <div style="max-width:520px; margin:30px auto; padding:20px 16px;">
        <!-- 主卡片：圆角+阴影+微光边框 -->
        <div style="background:#FFFFFF; border-radius:32px; box-shadow:0 25px 45px -12px rgba(0,0,0,0.15), 0 2px 6px rgba(0,0,0,0.02); overflow:hidden; transition: all 0.2s;">
            
            <!-- 装饰条：科技蓝渐变光效 -->
            <div style="height:6px; background: linear-gradient(90deg, #1E88E5, #64B5F6, #90CAF9, #1E88E5); background-size: 200%% auto;"></div>
            
            <!-- 内边距区域 -->
            <div style="padding: 36px 32px 44px 32px;">
                
                <!-- 品牌区 + 太阳能标识 -->
                <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; flex-wrap: wrap;">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <span style="font-size: 28px;">☀️</span>
                        <span style="font-weight: 600; font-size: 20px; color: #1F2A3E; letter-spacing: 0.5px;">CSERGY</span>
                        <span style="background:#EFF2F9; padding:4px 12px; border-radius:40px; font-size: 12px; font-weight:500; color:#1E88E5; margin-left:6px;">智慧能源</span>
                    </div>
                    <div style="display: flex; gap: 8px; margin-top: 8px;">
                        <span style="font-size: 20px;">⚡</span>
                        <span style="font-size: 20px;">🔋</span>
                    </div>
                </div>
                
                <!-- 动态标题 (subject) -->
                <h2 style="font-size: 26px; font-weight: 700; color: #0A1C2F; margin: 12px 0 8px 0; letter-spacing: -0.3px;">%s</h2>
                
                <!-- 温馨分隔文字 -->
                <div style="height: 2px; width: 60px; background: linear-gradient(90deg, #1E88E5, #B0D4FF); margin: 12px 0 20px 0; border-radius: 4px;"></div>
                
                <!-- 正文描述 -->
                <p style="font-size: 16px; line-height: 1.5; color: #3E4A5E; margin: 0 0 16px 0; font-weight: 400;">
                    感谢您注册<span style="font-weight:600; color:#1E88E5;"> CSERGY光伏逆变器智能监控APP</span>，请使用以下验证码完成账户验证：
                </p>
                
                <!-- 验证码展示区：高端光晕 + 等宽字体 -->
                <div style="background: linear-gradient(135deg, #F0F7FF 0%%, #FFFFFF 100%%); border-radius: 24px; padding: 24px 20px; margin: 28px 0 20px 0; text-align: center; border: 1px solid rgba(30,136,229,0.2); box-shadow: inset 0 1px 2px rgba(0,0,0,0.02), 0 6px 12px -6px rgba(30,136,229,0.12);">
                    <div style="letter-spacing: 6px; font-size: 46px; font-weight: 800; font-family: 'SF Mono', 'JetBrains Mono', 'Fira Code', monospace; color: #1363B3; background: #FFFFFF; display: inline-block; padding: 8px 24px; border-radius: 60px; box-shadow: 0 2px 8px rgba(0,0,0,0.03);">
                        %s
                    </div>
                </div>
                
                <!-- 安全提示卡片 -->
                <div style="background: #F8F9FC; border-radius: 20px; padding: 16px 20px; margin: 16px 0 24px 0; border-left: 4px solid #1E88E5;">
                    <p style="margin: 0 0 6px 0; font-size: 14px; font-weight: 500; color: #1F2A3E;">
                        🔐 安全性提示
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #5B6A84; line-height: 1.4;">
                        验证码<span style="font-weight:600;"> 5分钟 </span>内有效，请勿将验证码告知他人。<br>
                        CSERGY工作人员<span style="font-weight:600;">绝不会</span>向您索要任何验证码。
                    </p>
                </div>
                
                <!-- 操作指引（轻微淡化辅助） -->
                <div style="margin: 20px 0 10px 0; text-align: center;">
                    <span style="font-size: 13px; color: #9AA6B9;">如果非本人操作，请忽略此邮件，您的账号依然安全。</span>
                </div>
                
                <!-- 底部公司信息 + 光伏场景 -->
                <div style="margin-top: 32px; padding-top: 20px; border-top: 1px solid #ECF0F5; text-align: center;">
                    <div style="display: flex; justify-content: center; gap: 12px; margin-bottom: 12px; flex-wrap: wrap;">
                        <span style="font-size: 13px; color: #7E8A9E;">© CSERGY · 智慧光伏解决方案</span>
                        <span style="width:4px; height:4px; background:#C0CCDA; border-radius:50%%; display:inline-block;"></span>
                        <span style="font-size: 13px; color: #7E8A9E;">让能源更智能</span>
                    </div>
                    <div style="font-size: 12px; color: #B7C1D2;">
                        CSERGY | 清洁能源 · 高效逆变
                    </div>
                </div>
            </div>
        </div>
        
        <!-- 额外占位自然留白 -->
        <div style="text-align: center; margin-top: 24px;">
            <p style="font-size: 12px; color: #A6B1C6; margin: 0;">此邮件由CSERGY系统自动发出，请勿直接回复</p>
        </div>
    </div>
</body>
</html>
`, subject, code))

	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, cfg.Password)
	if cfg.UseSSL {
		d.SSL = true
		d.TLSConfig = &tls.Config{
			ServerName: cfg.Host,
		}
	}

	return d.DialAndSend(m)
}

// sendMailWithTemplate sends email using HTML templates
func (s *EmailService) sendMailWithTemplate(to string, data map[string]string, templateName string, cfg config.EmailConfig) error {
	// Get the directory of this file
	currentDir := "./internal/templates"
	templatePath := filepath.Join(currentDir, templateName)
	
	// Check if template exists, if not use inline fallback
	tmpl, err := template.ParseFiles(templatePath)
	if err != nil {
		logger.Warn("Template file not found, using inline verification code template", 
			zap.String("template", templateName), zap.Error(err))
		// Use inline template for verification code as fallback
		if templateName == "verification_code.tmpl" {
			return s.sendInlineVerificationCode(to, data["Code"], data["Subject"], cfg)
		}
		// For other templates, create a minimal fallback
		tmpl = template.Must(template.New("fallback").Parse(s.getFallbackHTML(data)))
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, data); err != nil {
		return fmt.Errorf("execute template: %w", err)
	}

	m := gomail.NewMessage()
	m.SetHeader("From", cfg.From)
	m.SetHeader("To", to)
	m.SetHeader("Subject", "邀请加入组织")
	m.SetBody("text/html", buf.String())

	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, cfg.Password)
	if cfg.UseSSL {
		d.SSL = true
		d.TLSConfig = &tls.Config{
			ServerName: cfg.Host,
		}
	}

	return d.DialAndSend(m)
}

// sendInlineVerificationCode is the original inline method for verification codes
func (s *EmailService) sendInlineVerificationCode(to, code, subject string, cfg config.EmailConfig) error {
	m := gomail.NewMessage()
	m.SetHeader("From", cfg.From)
	m.SetHeader("To", to)
	m.SetHeader("Subject", subject)
	m.SetBody("text/html", fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>CSERGY 验证码</title>
</head>
<body style="margin:0; padding:0; background-color:#EFF2F7; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Helvetica, Arial, sans-serif;">
    <div style="max-width:520px; margin:30px auto; padding:20px 16px;">
        <!-- 主卡片：圆角 + 阴影 + 微光边框 -->
        <div style="background:#FFFFFF; border-radius:32px; box-shadow:0 25px 45px -12px rgba(0,0,0,0.15), 0 2px 6px rgba(0,0,0,0.02); overflow:hidden; transition: all 0.2s;">
            
            <!-- 装饰条：科技蓝渐变光效 -->
            <div style="height:6px; background: linear-gradient(90deg, #1E88E5, #64B5F6, #90CAF9, #1E88E5); background-size: 200%% auto;"></div>
            
            <!-- 内边距区域 -->
            <div style="padding: 36px 32px 44px 32px;">
                
                <!-- 品牌区 + 太阳能标识 -->
                <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; flex-wrap: wrap;">
                    <div style="display: flex; align-items: center; gap: 10px;">
                        <span style="font-size: 28px;">☀️</span>
                        <span style="font-weight: 600; font-size: 20px; color: #1F2A3E; letter-spacing: 0.5px;">CSERGY</span>
                        <span style="background:#EFF2F9; padding:4px 12px; border-radius:40px; font-size: 12px; font-weight:500; color:#1E88E5; margin-left:6px;">智慧能源</span>
                    </div>
                    <div style="display: flex; gap: 8px; margin-top: 8px;">
                        <span style="font-size: 20px;">⚡</span>
                        <span style="font-size: 20px;">🔋</span>
                    </div>
                </div>
                
                <!-- 动态标题 (subject) -->
                <h2 style="font-size: 26px; font-weight: 700; color: #0A1C2F; margin: 12px 0 8px 0; letter-spacing: -0.3px;">%s</h2>
                
                <!-- 温馨分隔文字 -->
                <div style="height: 2px; width: 60px; background: linear-gradient(90deg, #1E88E5, #B0D4FF); margin: 12px 0 20px 0; border-radius: 4px;"></div>
                
                <!-- 正文描述 -->
                <p style="font-size: 16px; line-height: 1.5; color: #3E4A5E; margin: 0 0 16px 0; font-weight: 400;">
                    感谢您注册<span style="font-weight:600; color:#1E88E5;"> CSERGY 光伏逆变器智能监控 APP</span>，请使用以下验证码完成账户验证：
                </p>
                
                <!-- 验证码展示区：高端光晕 + 等宽字体 -->
                <div style="background: linear-gradient(135deg, #F0F7FF 0%%, #FFFFFF 100%%); border-radius: 24px; padding: 24px 20px; margin: 28px 0 20px 0; text-align: center; border: 1px solid rgba(30,136,229,0.2); box-shadow: inset 0 1px 2px rgba(0,0,0,0.02), 0 6px 12px -6px rgba(30,136,229,0.12);">
                    <div style="letter-spacing: 6px; font-size: 46px; font-weight: 800; font-family: 'SF Mono', 'JetBrains Mono', 'Fira Code', monospace; color: #1363B3; background: #FFFFFF; display: inline-block; padding: 8px 24px; border-radius: 60px; box-shadow: 0 2px 8px rgba(0,0,0,0.03);">
                        %s
                    </div>
                </div>
                
                <!-- 安全提示卡片 -->
                <div style="background: #F8F9FC; border-radius: 20px; padding: 16px 20px; margin: 16px 0 24px 0; border-left: 4px solid #1E88E5;">
                    <p style="margin: 0 0 6px 0; font-size: 14px; font-weight: 500; color: #1F2A3E;">
                        🔐 安全性提示
                    </p>
                    <p style="margin: 0; font-size: 14px; color: #5B6A84; line-height: 1.4;">
                        验证码<span style="font-weight:600;"> 5分钟 </span>内有效，请勿将验证码告知他人。<br>
                        CSERGY 工作人员<span style="font-weight:600;">绝不会</span>向您索要任何验证码。
                    </p>
                </div>
                
                <!-- 操作指引（轻微淡化辅助） -->
                <div style="margin: 20px 0 10px 0; text-align: center;">
                    <span style="font-size: 13px; color: #9AA6B9;">如果非本人操作，请忽略此邮件，您的账号依然安全。</span>
                </div>
                
                <!-- 底部公司信息 + 光伏场景 -->
                <div style="margin-top: 32px; padding-top: 20px; border-top: 1px solid #ECF0F5; text-align: center;">
                    <div style="display: flex; justify-content: center; gap: 12px; margin-bottom: 12px; flex-wrap: wrap;">
                        <span style="font-size: 13px; color: #7E8A9E;">© CSERGY · 智慧光伏解决方案</span>
                        <span style="width:4px; height:4px; background:#C0CCDA; border-radius:50%%; display:inline-block;"></span>
                        <span style="font-size: 13px; color: #7E8A9E;">让能源更智能</span>
                    </div>
                    <div style="font-size: 12px; color: #B7C1D2;">
                        CSERGY | 清洁能源 · 高效逆变
                    </div>
                </div>
            </div>
        </div>
        
        <!-- 额外占位自然留白 -->
        <div style="text-align: center; margin-top: 24px;">
            <p style="font-size: 12px; color: #A6B1C6; margin: 0;">此邮件由 CSERGY 系统自动发出，请勿直接回复</p>
        </div>
    </div>
</body>
</html>
`, subject, code))

	d := gomail.NewDialer(cfg.Host, cfg.Port, cfg.Username, cfg.Password)
	if cfg.UseSSL {
		d.SSL = true
		d.TLSConfig = &tls.Config{
			ServerName: cfg.Host,
		}
	}

	return d.DialAndSend(m)
}

// getFallbackHTML provides a simple HTML fallback when template files are missing
func (s *EmailService) getFallbackHTML(data map[string]string) string {
	return fmt.Sprintf(`
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Email Notification</title>
</head>
<body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
    <div style="background: #f9f9f9; padding: 20px; border-radius: 8px;">
        <h2 style="color: #1E88E5;">Notification</h2>
        <p>To: %s</p>
        <p>Data: %v</p>
    </div>
</body>
</html>`, data["ToEmail"], data)
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
	default:
		return "验证码"
	}
}

// MaskEmail masks the email address for logging purposes
func maskEmail(email string) string {
	if len(email) <= 8 {
		return email
	}
	parts := strings.Split(email, "@")
	if len(parts) != 2 {
		return email
	}
	username := parts[0]
	domain := parts[1]
	maskedUsername := username[:2] + strings.Repeat("*", len(username)-2)
	return maskedUsername + "@" + domain
}

// SendInvitationEmail sends invitation emails to new users
func (s *EmailService) SendInvitationEmail(toEmail, tokenHint, roleName, organizationName string, expiresHours int, senderName string) error {
	ctx := context.Background()
	emailCfg := s.cfg
	if s.cfgSvc != nil {
		emailCfg = s.cfgSvc.GetEmailConfig(ctx)
	}
	if emailCfg.Host == "" || emailCfg.Host == "smtp.example.com" {
		logger.Warn("Email service not properly configured, skipping invitation email")
		return nil
	}

	data := map[string]string{
		"ToEmail":          toEmail,
		"TokenHint":        tokenHint,
		"RoleName":         roleName,
		"OrganizationName": organizationName,
		"ExpiresHours":     fmt.Sprintf("%d", expiresHours),
		"SenderName":       senderName,
		"CompanyName":      strings.Split(senderName, " ")[0], // Extract company name
	}

	return s.sendMailWithTemplate(toEmail, data, "invitation_email.tmpl", emailCfg)
}

// SendTransferNotification sends device transfer notification emails
func (s *EmailService) SendTransferNotification(requesterEmail, deviceSN, fromOrg, toOrg, reason string, senderName string) error {
	ctx := context.Background()
	emailCfg := s.cfg
	if s.cfgSvc != nil {
		emailCfg = s.cfgSvc.GetEmailConfig(ctx)
	}
	if emailCfg.Host == "" || emailCfg.Host == "smtp.example.com" {
		logger.Warn("Email service not properly configured, skipping transfer notification")
		return nil
	}

	data := map[string]string{
		"DeviceSN":  deviceSN,
		"FromOrg":   fromOrg,
		"ToOrg":     toOrg,
		"Reason":    reason,
		"SenderName": senderName,
	}

	return s.sendMailWithTemplate("admin@example.com", data, "transfer_notification.tmpl", emailCfg)
}

// SendWelcomeEmail sends welcome emails to new users
func (s *EmailService) SendWelcomeEmail(toEmail, username string, senderName string) error {
	ctx := context.Background()
	emailCfg := s.cfg
	if s.cfgSvc != nil {
		emailCfg = s.cfgSvc.GetEmailConfig(ctx)
	}
	if emailCfg.Host == "" || emailCfg.Host == "smtp.example.com" {
		logger.Warn("Email service not properly configured, skipping welcome email")
		return nil
	}

	data := map[string]string{
		"ToEmail":  toEmail,
		"Username": username,
		"SenderName": senderName,
	}

	return s.sendMailWithTemplate(toEmail, data, "welcome_email.tmpl", emailCfg)
}

// SendPasswordReset sends password reset emails
func (s *EmailService) SendPasswordReset(token, username, userEmail string, senderName string) error {
	ctx := context.Background()
	emailCfg := s.cfg
	if s.cfgSvc != nil {
		emailCfg = s.cfgSvc.GetEmailConfig(ctx)
	}
	if emailCfg.Host == "" || emailCfg.Host == "smtp.example.com" {
		logger.Warn("Email service not properly configured, skipping password reset email")
		return nil
	}

	data := map[string]string{
		"Username": username,
		"Token":    token[:8] + "****", // Only show first 8 chars for security
		"ToEmail":  userEmail,
		"SenderName": senderName,
	}

	return s.sendMailWithTemplate(userEmail, data, "password_reset.tmpl", emailCfg)
}
