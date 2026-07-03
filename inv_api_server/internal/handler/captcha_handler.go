package handler

import (
	"crypto/rand"
	"fmt"
	"math"

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

// CaptchaVerifyRequest 验证请求（接收轨迹数据）
type CaptchaVerifyRequest struct {
	// 轨迹数据
	Trail         []Point `json:"trail"`
	Duration      int64   `json:"duration"`       // 滑动时长（毫秒）
	SliderOffsetX float64 `json:"sliderOffsetX"`   // 滑块偏移量
	X             float64 `json:"x"`               // 拼图 x 轴移动值
	Y             float64 `json:"y"`               // y 轴移动值
	TargetType    string  `json:"targetType"`      // 操作目标类型
	ErrorCount    int     `json:"errorCount"`      // 连续错误次数
}

// Point 轨迹点
type Point struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

// captchaRedisKey 生成 Redis key
func captchaRedisKey(key string) string {
	return fmt.Sprintf("captcha:%s", key)
}

// GenerateCaptcha 生成验证码（前端自动处理，此接口可选）
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	// 前端使用 rc-slider-captcha 自动生成图片，后端不需要生成图片
	// 但为了兼容性，返回一个简单的响应
	response.Success(c, gin.H{
		"message": "前端自动生成验证码",
	})
}

// VerifyCaptcha 验证滑块位置（基于轨迹数据）
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req CaptchaVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Error("VerifyCaptcha bind error", zap.Error(err))
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	logger.Info("VerifyCaptcha request",
		zap.Float64("x", req.X),
		zap.Float64("y", req.Y),
		zap.Int64("duration", req.Duration),
		zap.Int("trail_length", len(req.Trail)),
		zap.Int("error_count", req.ErrorCount),
		zap.String("target_type", req.TargetType))

	// 验证逻辑：
	// 1. 检查滑动时长是否合理（不能太快，可能是机器人）
	// 2. 检查轨迹是否合理（不能是直线，可能是脚本）
	// 3. 检查连续错误次数

	// 检查滑动时长（至少 300ms，最多 10s）
	if req.Duration < 300 {
		logger.Warn("滑动太快", zap.Int64("duration", req.Duration))
		response.Error(c, 4031, "滑动太快，请重试")
		return
	}

	if req.Duration > 10000 {
		logger.Warn("滑动超时", zap.Int64("duration", req.Duration))
		response.Error(c, 4031, "操作超时，请重试")
		return
	}

	// 检查轨迹点数量（至少 5 个点）
	if len(req.Trail) < 5 {
		logger.Warn("轨迹点太少", zap.Int("trail_length", len(req.Trail)))
		response.Error(c, 4031, "验证失败，请重试")
		return
	}

	// 检查轨迹是否是直线（通过计算轨迹的标准差）
	if isLinearTrail(req.Trail) {
		logger.Warn("轨迹过于直线")
		response.Error(c, 4031, "验证失败，请重试")
		return
	}

	// 检查连续错误次数
	if req.ErrorCount >= 3 {
		logger.Warn("连续错误次数过多", zap.Int("error_count", req.ErrorCount))
		response.Error(c, 4031, "错误次数过多，请刷新重试")
		return
	}

	// 验证成功
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

// isLinearTrail 检查轨迹是否过于直线
func isLinearTrail(trail []Point) bool {
	if len(trail) < 3 {
		return true
	}

	// 计算 y 值的标准差
	var sumY float64
	for _, p := range trail {
		sumY += p.Y
	}
	meanY := sumY / float64(len(trail))

	var sumSqDiff float64
	for _, p := range trail {
		diff := p.Y - meanY
		sumSqDiff += diff * diff
	}
	stddev := math.Sqrt(sumSqDiff / float64(len(trail)))

	// 如果 y 值的标准差太小，说明轨迹过于直线
	return stddev < 2.0
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
