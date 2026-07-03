package service

import (
	"context"
	"crypto/rand"
	"crypto/tls"
	"fmt"
	"math/big"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gopkg.in/gomail.v2"
)

type EmailService struct {
	cache *redis.Client
	cfg   config.EmailConfig
}

func NewEmailService(cache *redis.Client, cfg config.EmailConfig) *EmailService {
	return &EmailService{cache: cache, cfg: cfg}
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

	if s.cfg.Host != "" && s.cfg.Host != "smtp.example.com" {
		if err := s.sendMail(email, code, codeType); err != nil {
			return fmt.Errorf("邮件发送失败: %v", err)
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

func (s *EmailService) sendMail(to, code, codeType string) error {
	m := gomail.NewMessage()
	m.SetHeader("From", s.cfg.From)
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
</head>
<body style="margin:0; padding:0; background:#f0f2f5; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans GB','Microsoft YaHei',sans-serif;">
    <div style="max-width:480px; margin:40px auto; padding:0 16px;">
        <!-- 主卡片 -->
        <div style="background:#ffffff; border-radius:16px; box-shadow:0 4px 24px rgba(0,0,0,0.08); overflow:hidden;">
            
            <!-- 顶部装饰条 -->
            <div style="height:4px; background:linear-gradient(90deg,#4f6ef7,#6366f1,#818cf8);"></div>
            
            <!-- 内容区域 -->
            <div style="padding:40px 32px;">
                
                <!-- Logo 区域 -->
                <div style="text-align:center; margin-bottom:32px;">
                    <div style="display:inline-block; width:56px; height:56px; background:linear-gradient(135deg,#4f6ef7,#6366f1); border-radius:14px; line-height:56px; text-align:center; margin-bottom:16px;">
                        <span style="font-size:28px; color:#fff;">⚡</span>
                    </div>
                    <h1 style="margin:0; font-size:24px; font-weight:700; color:#1a1a2e;">CSERGY</h1>
                    <p style="margin:4px 0 0; font-size:13px; color:#94a3b8; letter-spacing:1px;">光伏逆变器智能运维平台</p>
                </div>
                
                <!-- 验证码标题 -->
                <div style="text-align:center; margin-bottom:24px;">
                    <h2 style="margin:0; font-size:20px; font-weight:600; color:#1e293b;">%s</h2>
                    <p style="margin:8px 0 0; font-size:14px; color:#64748b;">请使用以下验证码完成操作</p>
                </div>
                
                <!-- 验证码展示区 -->
                <div style="background:linear-gradient(135deg,#f8fafc,#f1f5f9); border:1px dashed #cbd5e1; border-radius:12px; padding:24px; margin:24px 0; text-align:center;">
                    <div style="font-size:42px; font-weight:800; letter-spacing:8px; color:#4f6ef7; font-family:'SF Mono','JetBrains Mono',monospace;">
                        %s
                    </div>
                </div>
                
                <!-- 提示信息 -->
                <div style="background:#fffbeb; border-left:3px solid #f59e0b; border-radius:0 8px 8px 0; padding:12px 16px; margin:24px 0;">
                    <p style="margin:0; font-size:13px; color:#92400e; line-height:1.6;">
                        <strong>🔒 安全提示：</strong>验证码 5 分钟内有效，请勿泄露给他人。如非本人操作，请忽略此邮件。
                    </p>
                </div>
                
                <!-- 底部信息 -->
                <div style="margin-top:32px; padding-top:24px; border-top:1px solid #e2e8f0; text-align:center;">
                    <p style="margin:0 0 8px; font-size:12px; color:#94a3b8;">此邮件由系统自动发送，请勿回复</p>
                    <p style="margin:0; font-size:12px; color:#cbd5e1;">© 2024 CSERGY · 智慧光伏解决方案</p>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
`, subject, code))

	d := gomail.NewDialer(s.cfg.Host, s.cfg.Port, s.cfg.Username, s.cfg.Password)
	if s.cfg.UseSSL {
		d.SSL = true
		d.TLSConfig = &tls.Config{
			ServerName:         s.cfg.Host,
			InsecureSkipVerify: s.cfg.TLSInsecure,
		}
	}

	return d.DialAndSend(m)
}

func generateEmailCode(length int) string {
	code := make([]byte, length)
	for i := range code {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		code[i] = byte('0' + n.Int64())
	}
	return string(code)
}
