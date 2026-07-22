# Email Service Setup Guide

## Overview

The INV-MQTT platform includes a comprehensive email service for sending notifications including:
- User registration verification codes
- Password reset emails
- Organization invitations
- Device transfer notifications
- Welcome emails
- System alerts

## Architecture

The email service is built on `gopkg.in/gomail.v2` with HTML template support using Go's `html/template` package.

### Components

1. **EmailService** (`business-api/internal/service/email_service.go`)
   - Core SMTP client with TLS/SSL support
   - Template rendering engine
   - Email validation and masking utilities
   - Fallback mechanisms for template errors

2. **Email Templates** (`business-api/internal/templates/`)
   - `invitation_email.tmpl` - Organization invitation emails
   - `transfer_notification.tmpl` - Device transfer notifications
   - `verification_code.tmpl` - Verification code emails (inline fallback)
   - `welcome_email.tmpl` - Welcome emails for new users
   - `password_reset.tmpl` - Password reset emails

3. **Configuration** (`business-api/internal/config/config.go`)
   - EmailConfig struct with SMTP settings
   - Environment variable support
   - Default values for development

## Configuration

### Production Configuration

Update `business-api/config.docker.yaml`:

```yaml
email:
  host: smtp.example.com          # SMTP server address
  port: 587                       # SMTP port (587 for TLS, 465 for SSL)
  username: your-email@example.com
  password: ${EMAIL_PASSWORD}     # Use environment variable
  from: noreply@yourdomain.com    # Sender email address
  use_ssl: false                  # Use SSL (true for 465, false for 587)
  tls_insecure: false             # Skip cert verification (dev only!)
  sender_name: "CSERGY Platform"  # Display name for recipients
```

### Environment Variables

Set these in your deployment environment:

```bash
EMAIL_HOST=smtp.example.com
EMAIL_PORT=587
EMAIL_USER=your-email@example.com
EMAIL_PASS=your-smtp-password
EMAIL_FROM=noreply@yourdomain.com
EMAIL_SENDER_NAME="CSERGY Smart Energy Platform"
```

### Common SMTP Settings

| Provider      | Host                      | Port | Use SSL | TLS |
|---------------|---------------------------|------|---------|-----|
| Gmail         | smtp.gmail.com            | 587  | false   | yes |
| QQ Mail       | smtp.qq.com               | 465  | true    | no  |
| Outlook       | smtp.office365.com        | 587  | false   | yes |
| Aliyun        | smtp.aliyun.com           | 465  | true    | no  |
| Custom SMTP   | mail.yourcompany.com      | 587  | false   | yes |

## Usage Examples

### Sending Invitation Emails

```go
// In handler code
if h.emailService != nil {
    err := h.emailService.SendInvitationEmail(
        recipientEmail,
        rawToken[:8],              // First 8 chars only (for security)
        roleNames[roleID],
        organizationName,
        expiresHours,
        cfg.Email.SenderName,
    )
    if err != nil {
        logger.Warn("Failed to send invitation email", zap.Error(err))
        // Continue operation - don't fail the request
    }
}
```

### Sending Transfer Notifications

```go
err := emailService.SendTransferNotification(
    adminEmail,                    // Recipient (admin)
    deviceSN,                      // Device serial number
    sourceOrgName,                 // From organization
    targetOrgName,                 // To organization
    reasonForTransfer,             // Reason
    cfg.Email.SenderName,          // Sender name
)
```

## Testing

### Local Development with MailHog

MailHog is a testing SMTP server that captures emails and provides a web UI.

#### Option 1: Using Docker Compose

```bash
# Start MailHog
cd deploy
docker-compose -f docker-compose.email-test.yml up -d mailhog

# Verify it's running
curl http://localhost:1025/
```

#### Option 2: Manual Setup

```bash
# Install MailHog
brew install mailhog  # macOS
# or download from https://github.com/mailhog/MailHog

# Start MailHog
MailHog
```

#### Test Configuration

```yaml
# business-api/config.docker.yaml
email:
  host: localhost
  port: 1025
  username: ""
  password: ""
  from: "noreply@test.local"
  use_ssl: false
```

### Sending Test Emails

```bash
# Create invitation (triggers email)
curl -X POST http://localhost:8080/api/v1/invitations/create \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "email": "test-user@example.com",
    "role_id": 2,
    "organization_id": 1,
    "expires_hours": 24
  }'

# View captured email
open http://localhost:8025
```

### Using EtherealSMTP (Test Email Service)

EtherealSMTP provides a mock SMTP server for automated testing.

```bash
# Start EtherealSMTP
docker-compose -f docker-compose.email-test.yml up -d ethereal-smtp
```

Configuration:
```yaml
email:
  host: localhost
  port: 1026
  username: test_user
  password: test_pass
  from: "noreply@ethereal.email"
```

View emails at: http://localhost:8026

## Security Best Practices

### 1. Never Log Full Tokens

```go
// ✅ GOOD - Only show first 8 characters
tokenHint := rawToken[:8] + "****"
logger.Info("Token generated", zap.String("hint", tokenHint))

// ❌ BAD - Log full token
logger.Info("Token generated", zap.String("full_token", rawToken))
```

### 2. Use Environment Variables for Credentials

```bash
# ✅ GOOD
EMAIL_PASS=$(openssl rand -base64 32)

# ❌ BAD
# EMAIL_PASS=actual_password_in_plaintext
```

### 3. Enable TLS for Production

```yaml
# ✅ GOOD - TLS encrypted connection
email:
  host: smtp.example.com
  port: 587
  use_ssl: false  # Will upgrade to TLS via STARTTLS

# ❌ BAD - Unencrypted connection
email:
  host: smtp.example.com
  port: 25
  use_ssl: false
```

### 4. Validate Email Addresses

Before sending, validate email format:

```go
import "net/mail"

func isValidEmail(email string) bool {
    _, err := mail.ParseAddress(email)
    return err == nil
}
```

## Error Handling Strategy

### Non-Fatal Errors (Log & Continue)

```go
go func() {
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    err := emailService.SendInvitationEmail(...)
    if err != nil {
        logger.Warn("Failed to send email", 
            zap.String("email", recipient),
            zap.Error(err))
        // Don't rollback transaction - continue operation
    }
}()
```

### Fatal Configuration Errors (Fail Open)

At startup, if email service can't be configured properly:

```go
if cfg.Email.Host == "" || cfg.Email.Host == "smtp.example.com" {
    logger.Warn("Email service not configured, skipping initialization")
    emailService = nil
} else {
    emailService = NewEmailService(...)
}
```

## Troubleshooting

### Issue: Email Not Sending

**Symptoms:** No error in logs, but email not received

**Debug Steps:**
1. Check SMTP configuration
   ```bash
   docker exec <container-name> cat /app/config.docker.yaml | grep -A 7 email:
   ```
2. Verify network connectivity
   ```bash
   telnet smtp.example.com 587
   nc -zv smtp.example.com 587
   ```
3. Check authentication credentials
   ```bash
   # Test with real SMTP
   docker run --rm -it python:3.9 bash
   python3
   >>> import smtplib
   >>> server = smtplib.SMTP('smtp.example.com', 587)
   >>> server.starttls()
   >>> server.login('user', 'pass')
   ```

### Issue: TLS Certificate Errors

**Symptoms:** `x509: certificate signed by unknown authority`

**Solutions:**
1. Install proper CA certificates (production)
2. Use trusted email provider (Gmail, QQ, etc.)
3. Dev only: Set `tls_insecure: true` (not recommended)

### Issue: Email Goes to Spam

**Check:**
- DKIM/SPF/DMARC records configured for domain
- Email content doesn't trigger spam filters
- Sender reputation good
- Include unsubscribe/opt-out link (for marketing)

## Performance Considerations

### Async Email Sending

Always send emails asynchronously to avoid blocking requests:

```go
// ✅ GOOD
go func() {
    emailService.SendEmail(...)
}()

// ❌ BAD - Blocks HTTP request
emailService.SendEmail(...)
```

### Connection Pooling

The gomail library handles connection pooling automatically. Reuse the same EmailService instance across requests.

### Rate Limiting

Most SMTP providers have rate limits:
- Gmail: ~500 emails/day
- QQ Mail: ~100 emails/day
- Enterprise SMTP: Variable (check with provider)

Implement retry logic with exponential backoff for transient failures.

## Monitoring and Observability

### Metrics to Track

- Emails sent per hour/day
- Send success/failure rates
- Average send time
- Template render errors

### Logging Format

```json
{
  "level": "info",
  "msg": "Invitation email sent",
  "invitation_id": 123,
  "email": "u***@example.com",
  "role_name": "Organizer",
  "duration_ms": 245
}
```

## Future Enhancements

1. **Email Queue System** - Implement Redis queue for bulk sends
2. **Template Caching** - Pre-load templates at startup
3. **Multi-provider Support** - Rotate between SMTP providers
4. **Email Analytics** - Track opens/clicks
5. **Scheduled Emails** - Cron-based email batching

## References

- [gomail Documentation](https://pkg.go.dev/gopkg.in/gomail.v2)
- [Go HTML Template](https://pkg.go.dev/html/template)
- [SMTP Security Best Practices](https://www.rfc-editor.org/rfc/rfc8314.html)
- [MailHog GitHub](https://github.com/mailhog/MailHog)

---

**Version:** 1.0  
**Last Updated:** 2026-07-21  
**Maintained By:** Backend Team
