package handler

import (
	"crypto/rand"
	"fmt"

	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// CaptchaHandler 验证码处理器
type CaptchaHandler struct {
	rdb *redis.Client
}

// NewCaptchaHandler 创建验证码处理器
func NewCaptchaHandler(rdb *redis.Client) *CaptchaHandler {
	return &CaptchaHandler{rdb: rdb}
}

// CaptchaVerifyRequest 验证请求
type CaptchaVerifyRequest struct {
	X        float64           `json:"x"`
	Duration int64             `json:"duration"`
	Trail    [][]float64       `json:"trail"`
}

// captchaRedisKey 生成 Redis key
func captchaRedisKey(key string) string {
	return fmt.Sprintf("captcha:%s", key)
}

// GenerateCaptcha 生成验证码（前端使用 create-puzzle 自动处理）
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	// 前端使用 create-puzzle 库自动生成拼图，后端不需要生成图片
	response.Success(c, gin.H{
		"message": "前端自动生成验证码",
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req CaptchaVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Error("VerifyCaptcha bind error", zap.Error(err))
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	logger.Info("VerifyCaptcha request",
		zap.Float64("x", req.X),
		zap.Int64("duration", req.Duration),
		zap.Int("trail_length", len(req.Trail)))

	// 基本验证：
	// 1. 检查滑动时长（至少 300ms）
	if req.Duration < 300 {
		logger.Warn("滑动太快", zap.Int64("duration", req.Duration))
		response.Error(c, 4031, "滑动太快，请重试")
		return
	}

	// 2. 检查轨迹点数量（至少 5 个点）
	if len(req.Trail) < 5 {
		logger.Warn("轨迹点太少", zap.Int("trail_length", len(req.Trail)))
		response.Error(c, 4031, "验证失败，请重试")
		return
	}

	// 验证成功，生成 token
	verifyToken := generateRandomKey()

	// 存储验证成功的 token，有效期 10 分钟
	ctx := c.Request.Context()
	h.rdb.Set(ctx, captchaRedisKey("verified:"+verifyToken), "1", 600)

	logger.Info("验证成功", zap.String("token", verifyToken))

	response.Success(c, gin.H{
		"verified":    true,
		"verifyToken": verifyToken,
	})
}

// StoreToken 存储前端验证成功的 token
func (h *CaptchaHandler) StoreToken(c *gin.Context) {
	var req struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()
	h.rdb.Set(ctx, captchaRedisKey("verified:"+req.Token), "1", 600)

	response.SuccessWithMessage(c, "token stored", nil)
}

// CheckCaptchaVerified 检查验证码是否已验证
func (h *CaptchaHandler) CheckCaptchaVerified(c *gin.Context) bool {
	verifyToken := c.GetHeader("X-Captcha-Token")
	if verifyToken == "" {
		verifyToken = c.Query("captchaToken")
	}

	if verifyToken == "" {
		return false
	}

	ctx := c.Request.Context()
	exists, _ := h.rdb.Exists(ctx, captchaRedisKey("verified:"+verifyToken)).Result()
	if exists > 0 {
		h.rdb.Del(ctx, captchaRedisKey("verified:"+verifyToken))
		return true
	}

	return false
}

// generateRandomKey 生成随机 key
func generateRandomKey() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
