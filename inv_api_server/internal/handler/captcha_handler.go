package handler

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
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

// CaptchaData 验证码数据
type CaptchaData struct {
	BgUrl      string `json:"bgUrl"`
	PuzzleUrl  string `json:"puzzleUrl"`
	CaptchaKey string `json:"captchaKey"`
}

// CaptchaVerifyRequest 验证请求
type CaptchaVerifyRequest struct {
	CaptchaKey string  `json:"captchaKey" binding:"required"`
	X          float64 `json:"x" binding:"required"`
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

	// 随机生成缺口位置 (x: 80~240, y: 30~90)
	xRange := bgWidth - puzzleSize - 80
	yRange := bgHeight - puzzleSize - 40

	xRand, _ := rand.Int(rand.Reader, big.NewInt(int64(xRange)))
	yRand, _ := rand.Int(rand.Reader, big.NewInt(int64(yRange)))

	offsetX := int(xRand.Int64()) + 40
	offsetY := int(yRand.Int64()) + 20

	logger.Info("GenerateCaptcha",
		zap.Int("offsetX", offsetX),
		zap.Int("offsetY", offsetY),
		zap.Int("puzzleSize", puzzleSize))

	// 步骤1: 生成完整的背景图
	fullBgImg := generateFullBackgroundImage(bgWidth, bgHeight)

	// 步骤2: 从完整背景图截取拼图块
	puzzleImg := extractPuzzleFromImage(fullBgImg, offsetX, offsetY, puzzleSize)

	// 步骤3: 在背景图上绘制缺口（变暗的区域）
	bgImgWithHole := drawHoleOnImage(fullBgImg, offsetX, offsetY, puzzleSize)

	// 转换为 base64
	bgBase64, err := imageToBase64(bgImgWithHole)
	if err != nil {
		logger.Error("Failed to convert background to base64", zap.Error(err))
		response.HandleError(c, apperr.Internal("generate captcha failed", err))
		return
	}

	puzzleBase64, err := imageToBase64(puzzleImg)
	if err != nil {
		logger.Error("Failed to convert puzzle to base64", zap.Error(err))
		response.HandleError(c, apperr.Internal("generate captcha failed", err))
		return
	}

	// 生成验证码 key
	captchaKey := generateRandomKey()

	// 存储到 Redis，有效期 5 分钟
	ctx := c.Request.Context()
	captchaData := map[string]interface{}{
		"x":          offsetX,
		"y":          offsetY,
		"puzzleSize": puzzleSize,
	}

	jsonData, _ := json.Marshal(captchaData)
	h.rdb.Set(ctx, captchaRedisKey(captchaKey), string(jsonData), 300)

	response.Success(c, CaptchaData{
		BgUrl:      "data:image/png;base64," + bgBase64,
		PuzzleUrl:  "data:image/png;base64," + puzzleBase64,
		CaptchaKey: captchaKey,
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req CaptchaVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	ctx := c.Request.Context()

	// 从 Redis 获取验证码数据
	data, err := h.rdb.Get(ctx, captchaRedisKey(req.CaptchaKey)).Result()
	if err != nil {
		response.Error(c, 4030, "验证码已过期，请刷新")
		return
	}

	// 删除验证码（一次性使用）
	h.rdb.Del(ctx, captchaRedisKey(req.CaptchaKey))

	// 解析验证码数据
	var captchaData map[string]int
	if err := json.Unmarshal([]byte(data), &captchaData); err != nil {
		response.HandleError(c, apperr.Internal("parse captcha data failed", err))
		return
	}

	// 验证滑块位置
	expectedX := float64(captchaData["x"])
	tolerance := 8.0

	logger.Info("Captcha verify",
		zap.Float64("user_x", req.X),
		zap.Float64("expected_x", expectedX),
		zap.Float64("diff", math.Abs(req.X-expectedX)))

	if math.Abs(req.X-expectedX) <= tolerance {
		verifyToken := generateRandomKey()
		h.rdb.Set(ctx, captchaRedisKey("verified:"+verifyToken), "1", 600)

		response.Success(c, gin.H{
			"verified":    true,
			"verifyToken": verifyToken,
		})
	} else {
		response.Error(c, 4031, "验证失败，请重试")
	}
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

// generateFullBackgroundImage 生成完整的背景图
func generateFullBackgroundImage(width, height int) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// 生成渐变背景
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			r := uint8(60 + x*40/width)
			g := uint8(120 + y*60/height)
			b := uint8(180 + (x+y)*40/(width+height))
			img.Set(x, y, color.RGBA{r, g, b, 255})
		}
	}

	// 绘制装饰元素
	drawDecorations(img, width, height)

	return img
}

// extractPuzzleFromImage 从背景图截取拼图块
func extractPuzzleFromImage(bgImg *image.RGBA, x, y, size int) *image.RGBA {
	puzzle := image.NewRGBA(image.Rect(0, 0, size, size))

	for dy := 0; dy < size; dy++ {
		for dx := 0; dx < size; dx++ {
			bgX := x + dx
			bgY := y + dy
			if bgX >= 0 && bgX < bgImg.Bounds().Dx() && bgY >= 0 && bgY < bgImg.Bounds().Dy() {
				puzzle.Set(dx, dy, bgImg.At(bgX, bgY))
			}
		}
	}

	// 添加边框
	borderColor := color.RGBA{255, 255, 255, 220}
	for i := 0; i < size; i++ {
		setPixelSafe(puzzle, i, 0, borderColor)
		setPixelSafe(puzzle, i, size-1, borderColor)
		setPixelSafe(puzzle, 0, i, borderColor)
		setPixelSafe(puzzle, size-1, i, borderColor)
	}

	return puzzle
}

// drawHoleOnImage 在背景图上绘制缺口
func drawHoleOnImage(bgImg *image.RGBA, x, y, size int) *image.RGBA {
	// 复制背景图
	img := image.NewRGBA(bgImg.Bounds())
	copy(img.Pix, bgImg.Pix)

	// 绘制变暗的区域
	for dy := 0; dy < size; dy++ {
		for dx := 0; dx < size; dx++ {
			px := x + dx
			py := y + dy
			if px >= 0 && px < img.Bounds().Dx() && py >= 0 && py < img.Bounds().Dy() {
				original := img.RGBAAt(px, py)
				img.Set(px, py, color.RGBA{
					uint8(float64(original.R) * 0.4),
					uint8(float64(original.G) * 0.4),
					uint8(float64(original.B) * 0.4),
					255,
				})
			}
		}
	}

	// 绘制白色边框
	borderColor := color.RGBA{255, 255, 255, 200}
	for i := 0; i < size; i++ {
		setPixelSafe(img, x+i, y, borderColor)
		setPixelSafe(img, x+i, y+size-1, borderColor)
		setPixelSafe(img, x, y+i, borderColor)
		setPixelSafe(img, x+size-1, y+i, borderColor)
	}

	return img
}

// drawDecorations 绘制装饰元素
func drawDecorations(img *image.RGBA, width, height int) {
	for i := 0; i < 6; i++ {
		cx, _ := rand.Int(rand.Reader, big.NewInt(int64(width)))
		cy, _ := rand.Int(rand.Reader, big.NewInt(int64(height)))
		radius, _ := rand.Int(rand.Reader, big.NewInt(15))
		r := uint8(100 + cx.Int64()%100)
		g := uint8(100 + cy.Int64()%100)
		b := uint8(150 + (cx.Int64()+cy.Int64())%100)
		drawCircle(img, int(cx.Int64()), int(cy.Int64()), int(radius.Int64())+5, color.RGBA{r, g, b, 80})
	}
}

// drawCircle 绘制圆形
func drawCircle(img *image.RGBA, cx, cy, radius int, c color.RGBA) {
	for y := -radius; y <= radius; y++ {
		for x := -radius; x <= radius; x++ {
			if x*x+y*y <= radius*radius {
				px, py := cx+x, cy+y
				if px >= 0 && px < img.Bounds().Dx() && py >= 0 && py < img.Bounds().Dy() {
					img.Set(px, py, c)
				}
			}
		}
	}
}

// setPixelSafe 安全设置像素
func setPixelSafe(img *image.RGBA, x, y int, c color.RGBA) {
	if x >= 0 && x < img.Bounds().Dx() && y >= 0 && y < img.Bounds().Dy() {
		img.Set(x, y, c)
	}
}

// imageToBase64 将图片转换为 base64
func imageToBase64(img image.Image) (string, error) {
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		buf.Reset()
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
			return "", err
		}
	}
	return base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

// generateRandomKey 生成随机 key
func generateRandomKey() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
