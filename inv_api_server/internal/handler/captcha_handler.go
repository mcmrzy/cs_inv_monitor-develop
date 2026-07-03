package handler

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"math/big"
	"time"

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
	Y          float64 `json:"y"`
}

// captchaRedisKey 生成 Redis key
func captchaRedisKey(key string) string {
	return fmt.Sprintf("captcha:%s", key)
}

// GenerateCaptcha 生成验证码图片
// 返回背景图和拼图的 base64 数据，以及验证码 key
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	// 生成随机位置 (拼图缺口位置)
	bgWidth := 320
	bgHeight := 160
	puzzleWidth := 60
	puzzleHeight := 60

	// 随机生成缺口位置 (确保拼图不会超出边界)
	maxX := bgWidth - puzzleWidth - 20
	maxY := bgHeight - puzzleHeight - 20

	x, _ := rand.Int(rand.Reader, big.NewInt(int64(maxX)))
	y, _ := rand.Int(rand.Reader, big.NewInt(int64(maxY)))

	offsetX := int(x.Int64()) + 10 // 保持边距
	offsetY := int(y.Int64()) + 10

	// 生成背景图（带缺口）
	bgImg := generateBackgroundImage(bgWidth, bgHeight, offsetX, offsetY, puzzleWidth, puzzleHeight)

	// 生成拼图块
	puzzleImg := generatePuzzleImage(puzzleWidth, puzzleHeight, bgImg, offsetX, offsetY)

	// 转换为 base64
	bgBase64, err := imageToBase64(bgImg)
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
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	captchaData := map[string]interface{}{
		"x":      offsetX,
		"y":      offsetY,
		"width":  puzzleWidth,
		"height": puzzleHeight,
	}

	jsonData, _ := json.Marshal(captchaData)
	h.rdb.Set(ctx, captchaRedisKey(captchaKey), string(jsonData), 5*time.Minute)

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

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

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

	// 验证滑块位置（允许 ±5 的误差）
	expectedX := captchaData["x"]
	tolerance := 5

	if int(req.X) >= expectedX-tolerance && int(req.X) <= expectedX+tolerance {
		// 验证成功，生成验证 token
		verifyToken := generateRandomKey()

		// 存储验证成功的 token，有效期 10 分钟
		h.rdb.Set(ctx, captchaRedisKey("verified:"+verifyToken), "1", 10*time.Minute)

		response.Success(c, gin.H{
			"verified":    true,
			"verifyToken": verifyToken,
		})
	} else {
		response.Error(c, 4031, "验证失败，请重试")
	}
}

// CheckCaptchaVerified 检查验证码是否已验证（用于登录接口）
func (h *CaptchaHandler) CheckCaptchaVerified(c *gin.Context) bool {
	verifyToken := c.GetHeader("X-Captcha-Token")
	if verifyToken == "" {
		verifyToken = c.Query("captchaToken")
	}

	if verifyToken == "" {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	exists, _ := h.rdb.Exists(ctx, captchaRedisKey("verified:"+verifyToken)).Result()
	if exists > 0 {
		// 验证成功后删除 token（一次性使用）
		h.rdb.Del(ctx, captchaRedisKey("verified:"+verifyToken))
		return true
	}

	return false
}

// generateBackgroundImage 生成带缺口的背景图
func generateBackgroundImage(width, height, puzzleX, puzzleY, puzzleW, puzzleH int) *image.RGBA {
	// 创建背景图
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// 生成渐变背景
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			// 蓝色渐变背景
			r := uint8(100 + x*50/width)
			g := uint8(150 + y*50/height)
			b := uint8(200 + (x+y)*30/(width+height))
			img.Set(x, y, color.RGBA{r, g, b, 255})
		}
	}

	// 绘制一些装饰元素
	drawDecorations(img, width, height)

	// 绘制缺口（半透明黑色区域）
	for y := puzzleY; y < puzzleY+puzzleH; y++ {
		for x := puzzleX; x < puzzleX+puzzleW; x++ {
			if x >= 0 && x < width && y >= 0 && y < height {
				// 半透明黑色
				img.Set(x, y, color.RGBA{0, 0, 0, 100})
			}
		}
	}

	// 绘制缺口边框
	for x := puzzleX; x < puzzleX+puzzleW; x++ {
		if x >= 0 && x < width {
			if puzzleY >= 0 && puzzleY < height {
				img.Set(x, puzzleY, color.RGBA{255, 255, 255, 200})
			}
			if puzzleY+puzzleH-1 >= 0 && puzzleY+puzzleH-1 < height {
				img.Set(x, puzzleY+puzzleH-1, color.RGBA{255, 255, 255, 200})
			}
		}
	}
	for y := puzzleY; y < puzzleY+puzzleH; y++ {
		if y >= 0 && y < height {
			if puzzleX >= 0 && puzzleX < width {
				img.Set(puzzleX, y, color.RGBA{255, 255, 255, 200})
			}
			if puzzleX+puzzleW-1 >= 0 && puzzleX+puzzleW-1 < width {
				img.Set(puzzleX+puzzleW-1, y, color.RGBA{255, 255, 255, 200})
			}
		}
	}

	return img
}

// drawDecorations 绘制装饰元素
func drawDecorations(img *image.RGBA, width, height int) {
	// 绘制圆形装饰
	for i := 0; i < 5; i++ {
		cx, _ := rand.Int(rand.Reader, big.NewInt(int64(width)))
		cy, _ := rand.Int(rand.Reader, big.NewInt(int64(height)))
		radius, _ := rand.Int(rand.Reader, big.NewInt(20))
		r := uint8(cx.Int64() % 256)
		g := uint8(cy.Int64() % 256)
		b := uint8((cx.Int64() + cy.Int64()) % 256)

		drawCircle(img, int(cx.Int64()), int(cy.Int64()), int(radius.Int64())+10, color.RGBA{r, g, b, 150})
	}

	// 绘制线条装饰
	for i := 0; i < 3; i++ {
		x1, _ := rand.Int(rand.Reader, big.NewInt(int64(width)))
		y1, _ := rand.Int(rand.Reader, big.NewInt(int64(height)))
		x2, _ := rand.Int(rand.Reader, big.NewInt(int64(width)))
		y2, _ := rand.Int(rand.Reader, big.NewInt(int64(height)))

		drawLine(img, int(x1.Int64()), int(y1.Int64()), int(x2.Int64()), int(y2.Int64()), color.RGBA{200, 200, 200, 100})
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

// drawLine 绘制线条
func drawLine(img *image.RGBA, x1, y1, x2, y2 int, c color.RGBA) {
	dx := abs(x2 - x1)
	dy := abs(y2 - y1)
	sx := 1
	sy := 1
	if x1 >= x2 {
		sx = -1
	}
	if y1 >= y2 {
		sy = -1
	}
	err := dx - dy

	for {
		if x1 >= 0 && x1 < img.Bounds().Dx() && y1 >= 0 && y1 < img.Bounds().Dy() {
			img.Set(x1, y1, c)
		}
		if x1 == x2 && y1 == y2 {
			break
		}
		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x1 += sx
		}
		if e2 < dx {
			err += dx
			y1 += sy
		}
	}
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// generatePuzzleImage 生成拼图块
func generatePuzzleImage(width, height int, bgImg *image.RGBA, offsetX, offsetY int) *image.RGBA {
	// 创建拼图块
	puzzle := image.NewRGBA(image.Rect(0, 0, width, height))

	// 从背景图中截取对应区域
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			bgX := offsetX + x
			bgY := offsetY + y
			if bgX >= 0 && bgX < bgImg.Bounds().Dx() && bgY >= 0 && bgY < bgImg.Bounds().Dy() {
				puzzle.Set(x, y, bgImg.At(bgX, bgY))
			}
		}
	}

	// 添加边框效果
	borderColor := color.RGBA{255, 255, 255, 200}
	for x := 0; x < width; x++ {
		puzzle.Set(x, 0, borderColor)
		puzzle.Set(x, height-1, borderColor)
	}
	for y := 0; y < height; y++ {
		puzzle.Set(0, y, borderColor)
		puzzle.Set(width-1, y, borderColor)
	}

	// 添加阴影效果
	shadowColor := color.RGBA{0, 0, 0, 80}
	for i := 0; i < 3; i++ {
		for y := 0; y < height; y++ {
			if width-1+i < width {
				puzzle.Set(width-1+i, y, shadowColor)
			}
		}
		for x := 0; x < width; x++ {
			if height-1+i < height {
				puzzle.Set(x, height-1+i, shadowColor)
			}
		}
	}

	return puzzle
}

// imageToBase64 将图片转换为 base64 字符串
func imageToBase64(img image.Image) (string, error) {
	var buf bytes.Buffer

	// 尝试编码为 PNG
	if err := png.Encode(&buf, img); err != nil {
		// 如果 PNG 失败，尝试 JPEG
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
