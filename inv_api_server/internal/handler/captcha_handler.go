package handler

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"math/big"

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

// captchaRedisKey 生成 Redis key
func captchaRedisKey(key string) string {
	return fmt.Sprintf("captcha:%s", key)
}

// GenerateCaptcha 生成验证码图片
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	bgWidth := 320
	bgHeight := 160
	puzzleSize := 50

	// 随机生成缺口位置 (x: 60~220)
	xRange := bgWidth - puzzleSize - 80
	xRand, _ := rand.Int(rand.Reader, big.NewInt(int64(xRange)))
	offsetX := int(xRand.Int64()) + 40

	logger.Info("GenerateCaptcha",
		zap.Int("bgWidth", bgWidth),
		zap.Int("bgHeight", bgHeight),
		zap.Int("puzzleSize", puzzleSize),
		zap.Int("offsetX", offsetX))

	// 创建背景图
	bgImg := image.NewRGBA(image.Rect(0, 0, bgWidth, bgHeight))

	// 填充蓝色背景
	for y := 0; y < bgHeight; y++ {
		for x := 0; x < bgWidth; x++ {
			bgImg.Set(x, y, color.RGBA{70, 130, 200, 255})
		}
	}

	// 绘制一些装饰
	for i := 0; i < 8; i++ {
		cx := 20 + i*38
		cy := 80
		for dy := -15; dy <= 15; dy++ {
			for dx := -15; dx <= 15; dx++ {
				if dx*dx+dy*dy <= 15*15 {
					px, py := cx+dx, cy+dy
					if px >= 0 && px < bgWidth && py >= 0 && py < bgHeight {
						bgImg.Set(px, py, color.RGBA{100, 160, 220, 255})
					}
				}
			}
		}
	}

	// 从背景图截取拼图块（在绘制缺口之前）
	puzzleImg := image.NewRGBA(image.Rect(0, 0, puzzleSize, puzzleSize))
	for y := 0; y < puzzleSize; y++ {
		for x := 0; x < puzzleSize; x++ {
			srcX := offsetX + x
			srcY := y
			if srcX < bgWidth && srcY < bgHeight {
				puzzleImg.Set(x, y, bgImg.At(srcX, srcY))
			}
		}
	}

	// 给拼图块添加白色边框
	for i := 0; i < puzzleSize; i++ {
		puzzleImg.Set(i, 0, color.RGBA{255, 255, 255, 200})
		puzzleImg.Set(i, puzzleSize-1, color.RGBA{255, 255, 255, 200})
		puzzleImg.Set(0, i, color.RGBA{255, 255, 255, 200})
		puzzleImg.Set(puzzleSize-1, i, color.RGBA{255, 255, 255, 200})
	}

	// 在背景图上绘制缺口（变暗的区域）
	for y := 0; y < puzzleSize; y++ {
		for x := 0; x < puzzleSize; x++ {
			px := offsetX + x
			if px < bgWidth && y < bgHeight {
				// 变暗
				bgImg.Set(px, y, color.RGBA{30, 60, 100, 255})
			}
		}
	}

	// 给缺口添加白色边框
	for i := 0; i < puzzleSize; i++ {
		bgImg.Set(offsetX+i, 0, color.RGBA{255, 255, 255, 200})
		bgImg.Set(offsetX+i, puzzleSize-1, color.RGBA{255, 255, 255, 200})
		bgImg.Set(offsetX, i, color.RGBA{255, 255, 255, 200})
		bgImg.Set(offsetX+puzzleSize-1, i, color.RGBA{255, 255, 255, 200})
	}

	// 转换为 base64
	bgBase64 := imageToBase64(bgImg)
	puzzleBase64 := imageToBase64(puzzleImg)

	// 生成验证码 key
	captchaKey := generateRandomKey()

	// 存储到 Redis
	ctx := c.Request.Context()
	captchaData := map[string]interface{}{
		"x":          offsetX,
		"puzzleSize": puzzleSize,
	}
	jsonData, _ := json.Marshal(captchaData)
	h.rdb.Set(ctx, captchaRedisKey(captchaKey), string(jsonData), 300)

	logger.Info("验证码生成成功",
		zap.String("captchaKey", captchaKey),
		zap.Int("offsetX", offsetX))

	response.Success(c, gin.H{
		"bgUrl":      "data:image/png;base64," + bgBase64,
		"puzzleUrl":  "data:image/png;base64," + puzzleBase64,
		"captchaKey": captchaKey,
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req struct {
		CaptchaKey string      `json:"captchaKey"`
		X          float64     `json:"x"`
		Y          float64     `json:"y"`
		Duration   int64       `json:"duration"`
		Trail      [][]float64 `json:"trail"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Error("VerifyCaptcha bind error", zap.Error(err))
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	logger.Info("VerifyCaptcha",
		zap.String("captchaKey", req.CaptchaKey),
		zap.Float64("x", req.X),
		zap.Int64("duration", req.Duration))

	// 从 Redis 获取验证码数据
	ctx := c.Request.Context()
	data, err := h.rdb.Get(ctx, captchaRedisKey(req.CaptchaKey)).Result()
	if err != nil {
		response.Error(c, 4030, "验证码已过期，请刷新")
		return
	}

	// 删除验证码
	h.rdb.Del(ctx, captchaRedisKey(req.CaptchaKey))

	// 解析验证码数据
	var captchaData map[string]int
	json.Unmarshal([]byte(data), &captchaData)

	// 验证位置
	expectedX := float64(captchaData["x"])
	tolerance := 8.0

	logger.Info("验证比较",
		zap.Float64("userX", req.X),
		zap.Float64("expectedX", expectedX),
		zap.Float64("diff", math.Abs(req.X-expectedX)))

	if math.Abs(req.X-expectedX) <= tolerance {
		verifyToken := generateRandomKey()
		h.rdb.Set(ctx, captchaRedisKey("verified:"+verifyToken), "1", 600)

		logger.Info("验证成功", zap.String("token", verifyToken))

		response.Success(c, gin.H{
			"verified":    true,
			"verifyToken": verifyToken,
		})
	} else {
		response.Error(c, 4031, "验证失败，请重试")
	}
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

// imageToBase64 图片转 base64
func imageToBase64(img image.Image) string {
	var buf bytes.Buffer
	png.Encode(&buf, img)
	return base64.StdEncoding.EncodeToString(buf.Bytes())
}

// generateRandomKey 生成随机 key
func generateRandomKey() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
