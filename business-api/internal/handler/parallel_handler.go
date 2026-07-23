package handler

import (
	"errors"
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

// ParallelHandler 处理并联组（parallel-groups）的 CRUD 请求。
type ParallelHandler struct {
	parallelService *service.ParallelService
}

func NewParallelHandler(parallelService *service.ParallelService) *ParallelHandler {
	return &ParallelHandler{parallelService: parallelService}
}

// List 返回分页的并联组列表（仅管理员可查看）
func (h *ParallelHandler) List(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.Error(c, 403, "仅管理员可操作")
		return
	}

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize := getPageSize(c, 20)
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	search := c.Query("search")
	var stationID *int64
	if sidStr := c.Query("station_id"); sidStr != "" {
		if sid, err := strconv.ParseInt(sidStr, 10, 64); err == nil && sid > 0 {
			stationID = &sid
		}
	}

	groups, total, err := h.parallelService.List(c.Request.Context(), page, pageSize, search, stationID)
	if err != nil {
		response.Error(c, 500, "查询并联组列表失败")
		return
	}
	response.Page(c, groups, total, page, pageSize)
}

// Get 返回单个并联组详情（仅管理员可查看）
func (h *ParallelHandler) Get(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.Error(c, 403, "仅管理员可操作")
		return
	}

	id, ok := parseParallelGroupID(c)
	if !ok {
		return
	}

	group, err := h.parallelService.GetByID(c.Request.Context(), id)
	if err != nil {
		response.Error(c, 500, "查询并联组失败")
		return
	}
	if group == nil {
		response.Error(c, 404, "并联组不存在")
		return
	}
	response.Success(c, group)
}

// Create 创建并联组（仅管理员）
func (h *ParallelHandler) Create(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.Error(c, 403, "仅管理员可操作")
		return
	}

	var req service.CreateParallelGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "无效的请求参数: "+err.Error())
		return
	}

	group, err := h.parallelService.Create(c.Request.Context(), &req)
	if err != nil {
		if errors.Is(err, service.ErrValidation) {
			response.Error(c, 400, err.Error())
			return
		}
		response.Error(c, 500, "创建并联组失败")
		return
	}
	response.SuccessWithMessage(c, "并联组创建成功", group)
}

// Update 更新并联组（仅管理员）
func (h *ParallelHandler) Update(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.Error(c, 403, "仅管理员可操作")
		return
	}

	id, ok := parseParallelGroupID(c)
	if !ok {
		return
	}

	var req service.UpdateParallelGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "无效的请求参数: "+err.Error())
		return
	}

	if err := h.parallelService.Update(c.Request.Context(), id, &req); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			response.Error(c, 404, "并联组不存在")
			return
		}
		if errors.Is(err, service.ErrValidation) {
			response.Error(c, 400, err.Error())
			return
		}
		response.Error(c, 500, "更新并联组失败")
		return
	}
	response.SuccessWithMessage(c, "并联组更新成功", gin.H{"id": id})
}

// Delete 删除并联组（仅管理员）
func (h *ParallelHandler) Delete(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.Error(c, 403, "仅管理员可操作")
		return
	}

	id, ok := parseParallelGroupID(c)
	if !ok {
		return
	}

	if err := h.parallelService.Delete(c.Request.Context(), id); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			response.Error(c, 404, "并联组不存在")
			return
		}
		response.Error(c, 500, "删除并联组失败")
		return
	}
	response.SuccessWithMessage(c, "并联组已删除", gin.H{"id": id})
}

// parseParallelGroupID extracts and validates the group ID from the URL path.
func parseParallelGroupID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "无效的并联组ID")
		return 0, false
	}
	return id, true
}
