package handler

import (
	"context"
	"fmt"
	"regexp"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// NotifyPrefsHandler 用户通知偏好接口。
// 供 App「消息通知设置」页面读写，推送链路发送前读取该偏好。
type NotifyPrefsHandler struct {
	repo *repository.NotifyPrefsRepository
}

func NewNotifyPrefsHandler(repo *repository.NotifyPrefsRepository) *NotifyPrefsHandler {
	return &NotifyPrefsHandler{repo: repo}
}

var timeFormatRegex = regexp.MustCompile(`^([01]\d|2[0-3]):[0-5]\d$`)

// Get 返回当前用户的通知偏好。
func (h *NotifyPrefsHandler) Get(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	prefs, err := h.repo.GetPrefs(ctx, userID)
	if err != nil {
		response.Error(c, 500, "system error")
		return
	}
	response.Success(c, prefs)
}

// Update 保存当前用户的通知偏好。
func (h *NotifyPrefsHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req model.NotifyPrefs
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request body")
		return
	}
	req.UserID = userID

	// 时间字段格式校验
	if !timeFormatRegex.MatchString(req.DailyReportTime) {
		req.DailyReportTime = "20:00"
	}
	if !timeFormatRegex.MatchString(req.DndStart) {
		req.DndStart = "22:00"
	}
	if !timeFormatRegex.MatchString(req.DndEnd) {
		req.DndEnd = "07:00"
	}
	if req.DndStart == req.DndEnd {
		response.Error(c, 400, "免打扰开始与结束时间不能相同")
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	if err := h.repo.SavePrefs(ctx, &req); err != nil {
		response.Error(c, 500, fmt.Sprintf("save notify prefs: %v", err))
		return
	}
	response.Success(c, gin.H{"updated": true})
}
