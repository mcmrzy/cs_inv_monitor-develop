package handler

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

const (
	maxAvatarSize   = 2 << 20 // 2 MiB
	avatarUploadDir = "/data/uploads/avatars"
	avatarURLPrefix = "/uploads/avatars"
)

var allowedAvatarTypes = map[string]bool{
	"image/jpeg": true,
	"image/png":  true,
	"image/gif":  true,
	"image/webp": true,
}

// UploadHandler handles file upload operations.
type UploadHandler struct {
	serverURL string
}

// NewUploadHandler creates a new UploadHandler.
func NewUploadHandler(serverURL string) *UploadHandler {
	return &UploadHandler{serverURL: serverURL}
}

// UploadAvatar handles avatar image upload.
// POST /api/v1/upload/avatar
func (h *UploadHandler) UploadAvatar(c *gin.Context) {
	userID := middleware.GetUserID(c)
	if userID <= 0 {
		response.Error(c, http.StatusUnauthorized, "unauthorized")
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.Error(c, http.StatusBadRequest, "请选择头像文件")
		return
	}
	defer file.Close()

	// Validate file size
	if header.Size <= 0 || header.Size > maxAvatarSize {
		response.Error(c, http.StatusBadRequest, "头像文件大小必须在 1 字节到 2 MiB 之间")
		return
	}

	// Validate file type
	contentType := header.Header.Get("Content-Type")
	if !allowedAvatarTypes[contentType] {
		// Try to detect from extension
		ext := strings.ToLower(filepath.Ext(header.Filename))
		switch ext {
		case ".jpg", ".jpeg":
			contentType = "image/jpeg"
		case ".png":
			contentType = "image/png"
		case ".gif":
			contentType = "image/gif"
		case ".webp":
			contentType = "image/webp"
		default:
			response.Error(c, http.StatusBadRequest, "只支持 JPEG、PNG、GIF、WebP 格式的图片")
			return
		}
	}

	// Create upload directory
	if err := os.MkdirAll(avatarUploadDir, 0755); err != nil {
		response.Error(c, http.StatusInternalServerError, "创建上传目录失败")
		return
	}

	// Generate unique filename
	randBytes := make([]byte, 16)
	if _, err := rand.Read(randBytes); err != nil {
		response.Error(c, http.StatusInternalServerError, "生成文件名失败")
		return
	}

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		switch contentType {
		case "image/jpeg":
			ext = ".jpg"
		case "image/png":
			ext = ".png"
		case "image/gif":
			ext = ".gif"
		case "image/webp":
			ext = ".webp"
		}
	}

	filename := fmt.Sprintf("avatar_%d_%s_%d%s", userID, hex.EncodeToString(randBytes), time.Now().UnixMilli(), ext)
	savePath := filepath.Join(avatarUploadDir, filename)

	// Sanitize filename to prevent path traversal
	safeFilename := filepath.Base(filename)
	if safeFilename == "." || safeFilename == ".." || safeFilename != filename {
		response.Error(c, http.StatusBadRequest, "invalid filename")
		return
	}

	// Ensure save path is within upload directory
	savePath = filepath.Join(avatarUploadDir, safeFilename)
	absSavePath, pathErr := filepath.Abs(savePath)
	if pathErr != nil || !strings.HasPrefix(absSavePath, avatarUploadDir) {
		response.Error(c, http.StatusBadRequest, "invalid file path")
		return
	}

	// Save file
	if err := c.SaveUploadedFile(header, absSavePath); err != nil {
		response.Error(c, http.StatusInternalServerError, "保存文件失败")
		return
	}

	// Build URL
	avatarURL := fmt.Sprintf("%s%s/%s", h.serverURL, avatarURLPrefix, filename)

	c.JSON(http.StatusOK, gin.H{
		"code":    0,
		"message": "success",
		"data": gin.H{
			"url":      avatarURL,
			"filename": filename,
		},
	})
}
