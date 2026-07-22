package handler

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"math/big"
	"strconv"
	"time"

	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const (
	captchaWidth        = 320
	captchaHeight       = 160
	captchaPieceSize    = 60
	captchaTolerance    = 8
	captchaChallengeTTL = 5 * time.Minute
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

// GenerateCaptcha creates a one-time server-side image challenge. The expected
// x coordinate never leaves the server.
func (h *CaptchaHandler) GenerateCaptcha(c *gin.Context) {
	if h.rdb == nil {
		response.InternalError(c, "captcha service unavailable")
		return
	}

	x, err := secureRandomInt(captchaPieceSize, captchaWidth-captchaPieceSize)
	if err != nil {
		response.InternalError(c, "captcha generation failed")
		return
	}
	y, err := secureRandomInt(12, captchaHeight-captchaPieceSize-12)
	if err != nil {
		response.InternalError(c, "captcha generation failed")
		return
	}
	challengeID := generateRandomKey()
	bgURL, puzzleURL, err := generateCaptchaImages(x, y)
	if err != nil {
		logger.Error("generate captcha image failed", zap.Error(err))
		response.InternalError(c, "captcha generation failed")
		return
	}
	if err := h.rdb.Set(
		c.Request.Context(),
		captchaRedisKey("challenge:"+challengeID),
		strconv.Itoa(x),
		captchaChallengeTTL,
	).Err(); err != nil {
		logger.Error("store captcha challenge failed", zap.Error(err))
		response.InternalError(c, "captcha service unavailable")
		return
	}

	response.Success(c, gin.H{
		"challengeId": challengeID,
		"bgUrl":       bgURL,
		"puzzleUrl":   puzzleURL,
	})
}

// VerifyCaptcha 验证滑块位置
func (h *CaptchaHandler) VerifyCaptcha(c *gin.Context) {
	var req struct {
		ChallengeID string  `json:"challengeId" binding:"required"`
		X           float64 `json:"x"`
		Duration    int64   `json:"duration"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		logger.Error("VerifyCaptcha bind error", zap.Error(err))
		response.BadRequest(c, "invalid captcha request")
		return
	}

	if req.X < 0 || req.X > captchaWidth {
		response.Error(c, 4031, "验证码校验失败，请重试")
		return
	}

	// 基本验证：检查滑动时长
	if req.Duration < 200 || req.Duration > 120000 {
		logger.Warn("滑动太快", zap.Int64("duration", req.Duration))
		response.Error(c, 4031, "滑动太快，请重试")
		return
	}
	if h.rdb == nil {
		response.InternalError(c, "captcha service unavailable")
		return
	}

	challengeKey := captchaRedisKey("challenge:" + req.ChallengeID)
	expectedRaw, err := h.rdb.GetDel(c.Request.Context(), challengeKey).Result()
	if err != nil {
		response.Error(c, 4031, "验证码已失效，请重试")
		return
	}
	expectedX, err := strconv.Atoi(expectedRaw)
	if err != nil || absFloat(req.X-float64(expectedX)) > captchaTolerance {
		response.Error(c, 4031, "验证码校验失败，请重试")
		return
	}

	// 前端已验证通过，直接生成 token
	verifyToken := generateRandomKey()

	// 存储验证成功的 token，有效期 10 分钟
	ctx := c.Request.Context()
	if err := h.rdb.Set(ctx, captchaRedisKey("verified:"+verifyToken), "1", 10*time.Minute).Err(); err != nil {
		logger.Error("store captcha token failed", zap.Error(err))
		response.InternalError(c, "captcha service unavailable")
		return
	}

	response.Success(c, gin.H{
		"verified":    true,
		"verifyToken": verifyToken,
	})
}

func secureRandomInt(min, max int) (int, error) {
	if max <= min {
		return 0, fmt.Errorf("invalid random range")
	}
	n, err := rand.Int(rand.Reader, big.NewInt(int64(max-min+1)))
	if err != nil {
		return 0, err
	}
	return min + int(n.Int64()), nil
}

func absFloat(value float64) float64 {
	if value < 0 {
		return -value
	}
	return value
}

func generateCaptchaImages(pieceX, pieceY int) (string, string, error) {
	background := image.NewRGBA(image.Rect(0, 0, captchaWidth, captchaHeight))
	seedBytes := make([]byte, 3)
	if _, err := rand.Read(seedBytes); err != nil {
		return "", "", err
	}
	for y := 0; y < captchaHeight; y++ {
		for x := 0; x < captchaWidth; x++ {
			background.SetRGBA(x, y, color.RGBA{
				R: uint8((x + int(seedBytes[0]) + y/2) % 256),
				G: uint8((y*2 + int(seedBytes[1]) + x/3) % 256),
				B: uint8((x/2 + y + int(seedBytes[2])) % 256),
				A: 255,
			})
		}
	}

	puzzle := image.NewRGBA(image.Rect(0, 0, captchaPieceSize, captchaHeight))
	draw.Draw(
		puzzle,
		image.Rect(0, pieceY, captchaPieceSize, pieceY+captchaPieceSize),
		background,
		image.Point{X: pieceX, Y: pieceY},
		draw.Src,
	)

	hole := color.RGBA{R: 235, G: 238, B: 245, A: 255}
	draw.Draw(
		background,
		image.Rect(pieceX, pieceY, pieceX+captchaPieceSize, pieceY+captchaPieceSize),
		&image.Uniform{C: hole},
		image.Point{},
		draw.Src,
	)
	border := color.RGBA{R: 255, G: 255, B: 255, A: 255}
	for i := 0; i < captchaPieceSize; i++ {
		background.Set(pieceX+i, pieceY, border)
		background.Set(pieceX+i, pieceY+captchaPieceSize-1, border)
		background.Set(pieceX, pieceY+i, border)
		background.Set(pieceX+captchaPieceSize-1, pieceY+i, border)
	}

	bgURL, err := encodePNGDataURL(background)
	if err != nil {
		return "", "", err
	}
	puzzleURL, err := encodePNGDataURL(puzzle)
	if err != nil {
		return "", "", err
	}
	return bgURL, puzzleURL, nil
}

func encodePNGDataURL(img image.Image) (string, error) {
	var buffer bytes.Buffer
	if err := png.Encode(&buffer, img); err != nil {
		return "", err
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(buffer.Bytes()), nil
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
		logger.Warn("CheckCaptchaToken: token is empty")
		return false
	}

	ctx := c.Request.Context()
	key := captchaRedisKey("verified:" + verifyToken)
	exists, err := h.rdb.Exists(ctx, key).Result()
	if err != nil {
		logger.Error("CheckCaptchaToken redis error", zap.Error(err))
		return false
	}
	return exists > 0
}

// generateRandomKey 生成随机 key
func generateRandomKey() string {
	bytes := make([]byte, 16)
	rand.Read(bytes)
	return fmt.Sprintf("%x", bytes)
}
