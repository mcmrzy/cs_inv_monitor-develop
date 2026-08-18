package handler

import (
	"net/http"
	"strings"

	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// EmailTemplateHandler 系统邮件模板管理端点（仅系统管理员）。
// GET  /api/v1/email/templates        模板列表
// PUT  /api/v1/email/templates/:key   更新模板（主题/内容块/启用状态）
// POST /api/v1/email/test             发送测试邮件
type EmailTemplateHandler struct {
	repo     *repository.EmailTemplateRepository
	emailSvc *service.EmailService
}

func NewEmailTemplateHandler(repo *repository.EmailTemplateRepository, emailSvc *service.EmailService) *EmailTemplateHandler {
	return &EmailTemplateHandler{repo: repo, emailSvc: emailSvc}
}

// emailTemplateItem 模板列表返回项
type emailTemplateItem struct {
	TemplateKey string `json:"template_key"`
	Subject     string `json:"subject"`
	HTMLBody    string `json:"html_body"`
	Enabled     bool   `json:"enabled"`
	UpdatedAt   string `json:"updated_at"`
}

// List 获取全部邮件模板
func (h *EmailTemplateHandler) List(c *gin.Context) {
	list, err := h.repo.List(c.Request.Context())
	if err != nil {
		logger.Error("获取邮件模板列表失败", zap.Error(err))
		response.InternalError(c, "获取邮件模板列表失败")
		return
	}

	items := make([]emailTemplateItem, 0, len(list))
	for _, t := range list {
		items = append(items, emailTemplateItem{
			TemplateKey: t.TemplateKey,
			Subject:     t.Subject,
			HTMLBody:    t.HTMLBody,
			Enabled:     t.Enabled,
			UpdatedAt:   t.UpdatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	response.Success(c, items)
}

// updateEmailTemplateRequest 模板更新请求体
type updateEmailTemplateRequest struct {
	Subject  string `json:"subject"`
	HTMLBody string `json:"html_body"`
	Enabled  *bool  `json:"enabled"`
}

// Update 更新指定模板（主题、内容块、启用状态）
func (h *EmailTemplateHandler) Update(c *gin.Context) {
	key := c.Param("key")

	known := false
	for _, k := range service.KnownEmailTemplateKeys() {
		if k == key {
			known = true
			break
		}
	}
	if !known {
		response.BadRequest(c, "未知的邮件模板类型")
		return
	}

	var req updateEmailTemplateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请求参数无效")
		return
	}
	if strings.TrimSpace(req.Subject) == "" {
		response.BadRequest(c, "邮件主题不能为空")
		return
	}
	if strings.TrimSpace(req.HTMLBody) == "" {
		response.BadRequest(c, "模板内容不能为空")
		return
	}
	// 提前校验模板语法，防止保存损坏的模板
	if err := service.ValidateEmailTemplate(req.Subject, req.HTMLBody); err != nil {
		response.BadRequest(c, "模板语法错误："+err.Error())
		return
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}

	tpl := &repository.EmailTemplate{
		TemplateKey: key,
		Subject:     req.Subject,
		HTMLBody:    req.HTMLBody,
		Enabled:     enabled,
	}
	if err := h.repo.Upsert(c.Request.Context(), tpl); err != nil {
		logger.Error("保存邮件模板失败", zap.String("template_key", key), zap.Error(err))
		response.InternalError(c, "保存邮件模板失败")
		return
	}

	logger.Info("邮件模板已更新",
		zap.String("template_key", key), zap.Bool("enabled", enabled))
	response.SuccessWithMessage(c, "模板保存成功", nil)
}

// sendTestEmailRequest 测试邮件请求体
type sendTestEmailRequest struct {
	Email string `json:"email"`
}

// SendTest 用当前 SMTP 配置发送一封测试邮件（通用模板示例内容）
func (h *EmailTemplateHandler) SendTest(c *gin.Context) {
	var req sendTestEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请求参数无效")
		return
	}
	email := strings.TrimSpace(req.Email)
	if email == "" || !strings.Contains(email, "@") || strings.HasPrefix(email, "@") || strings.HasSuffix(email, "@") {
		response.BadRequest(c, "收件人邮箱格式无效")
		return
	}

	if err := h.emailSvc.SendTestEmail(c.Request.Context(), email); err != nil {
		logger.Warn("发送测试邮件失败", zap.String("to", email), zap.Error(err))
		response.Error(c, http.StatusInternalServerError, "测试邮件发送失败："+err.Error())
		return
	}

	logger.Info("测试邮件已发送", zap.String("to", email))
	response.SuccessWithMessage(c, "测试邮件已发送", nil)
}
