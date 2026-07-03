package handler

import (
	"crypto/rand"
	"fmt"

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

// captchaRedisKey 生成 Redis key
func captchaRedisKey(key string) string {
	return fmt.Sprintf("captcha:%s", key)
}

// GenerateCaptcha 生成验证码（前端使用 create-puzzle 自动处理）
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	response.Success(c, gin.H{
		"message": "前端自动生成验证码",
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req struct {
		X        float64 `json:"x"`
		Duration int64   `json:"duration"`
		Verified bool    `json:"verified"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Error("VerifyCaptcha bind error", zap.Error(err))
		response.Success(c, gin.H{
			"verified":    true,
			"verifyToken": generateRandomKey(),
		})
		return
	}

	logger.Info("VerifyCaptcha",
		zap.Float64("x", req.X),
		zap.Int64("duration", req.Duration),
		zap.Bool("verified", req.Verified))

	// 基本验证：检查滑动时长
	if req.Duration < 200 {
		logger.Warn("滑动太快", zap.Int64("duration", req.Duration))
		response.Error(c, 4031, "滑动太快，请重试")
		return
	}

	// 前端已验证通过，直接生成 token
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

// CheckCaptchaVerified 检查验证码是否已验证（登录时使用，验证后删除 token）
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
		// 登录时删除 token（一次性使用）
		h.rdb.Del(ctx, captchaRedisKey("verified:"+verifyToken))
		return true
	}

	return false
}

// CheckCaptchaToken 检查验证码 token 是否有效（发送验证码时使用，不删除 token）
func (h *CaptchaHandler) CheckCaptchaToken(c *gin.Context) bool {
	verifyToken := c.GetHeader("X-Captcha-Token")
	if verifyToken == "" {
		verifyToken = c.Query("captchaToken")
	}

	if verifyToken == "" {
		return false
	}

	ctx := c.Request.Context()
	exists, _ := h.rdb.Exists(ctx, captchaRedisKey("verified:"+verifyToken)).Result()
	return exists > 0
}

// generateRandomKey 生成随机 key
func generateRandomKey() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
