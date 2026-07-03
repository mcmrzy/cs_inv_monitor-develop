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

	// 随机生成缺口位置
	xRange := bgWidth - puzzleSize - 60
	xRand, _ := rand.Int(rand.Reader, big.NewInt(int64(xRange)))
	offsetX := int(xRand.Int64()) + 30

	// 生成背景图
	bgImg := image.NewRGBA(image.Rect(0, 0, bgWidth, bgHeight))
	drawBackground(bgImg, bgWidth, bgHeight)

	// 从背景图截取拼图
	puzzleImg := image.NewRGBA(image.Rect(0, 0, puzzleSize, puzzleSize))
	for y := 0; y < puzzleSize; y++ {
		for x := 0; x < puzzleSize; x++ {
			bgX := offsetX + x
			if bgX < bgWidth {
				puzzleImg.Set(x, y, bgImg.At(bgX, y))
			}
		}
	}

	// 在背景图上绘制缺口
	drawHole(bgImg, offsetX, 0, puzzleSize, bgHeight)

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

	response.Success(c, gin.H{
		"bgUrl":      "data:image/png;base64," + bgBase64,
		"puzzleUrl":  "data:image/png;base64," + puzzleBase64,
		"captchaKey": captchaKey,
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req struct {
		CaptchaKey string    `json:"captchaKey"`
		X          float64   `json:"x"`
		Y          float64   `json:"y"`
		Duration   int64     `json:"duration"`
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

// drawBackground 绘制背景
func drawBackground(img *image.RGBA, width, height int) {
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			r := uint8(60 + x*40/width)
			g := uint8(120 + y*60/height)
			b := uint8(180 + (x+y)*40/(width+height))
			img.Set(x, y, color.RGBA{r, g, b, 255})
		}
	}

	// 绘制装饰圆形
	for i := 0; i < 5; i++ {
		cx := 30 + i*60
		cy := 80
		radius := 20
		for y := -radius; y <= radius; y++ {
			for x := -radius; x <= radius; x++ {
				if x*x+y*y <= radius*radius {
					px, py := cx+x, cy+y
					if px >= 0 && px < width && py >= 0 && py < height {
						img.Set(px, py, color.RGBA{100, 150, 200, 100})
					}
				}
			}
		}
	}
}

// drawHole 绘制缺口
func drawHole(img *image.RGBA, x, y, width, height int) {
	for dy := 0; dy < height; dy++ {
		for dx := 0; dx < width; dx++ {
			px := x + dx
			if px < img.Bounds().Dx() {
				original := img.RGBAAt(px, dy)
				img.Set(px, dy, color.RGBA{
					uint8(float64(original.R) * 0.3),
					uint8(float64(original.G) * 0.3),
					uint8(float64(original.B) * 0.3),
					255,
				})
			}
		}
	}

	// 绘制边框
	borderColor := color.RGBA{255, 255, 255, 200}
	for i := 0; i < width; i++ {
		if x+i < img.Bounds().Dx() {
			img.Set(x+i, y, borderColor)
			if y+height-1 < img.Bounds().Dy() {
				img.Set(x+i, y+height-1, borderColor)
			}
		}
	}
	for i := 0; i < height; i++ {
		if x < img.Bounds().Dx() {
			img.Set(x, y+i, borderColor)
		}
		if x+width-1 < img.Bounds().Dx() {
			img.Set(x+width-1, y+i, borderColor)
		}
	}
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
