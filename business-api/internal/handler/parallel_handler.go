package handler

import (
	"errors"
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
)

// ParallelHandler 处理并联组（parallel-groups）的 CRUD 与设备并机命令。
type ParallelHandler struct {
	parallelService *service.ParallelService
	deviceService   *service.DeviceService
}

func NewParallelHandler(parallelService *service.ParallelService, deviceService *service.DeviceService) *ParallelHandler {
	return &ParallelHandler{parallelService: parallelService, deviceService: deviceService}
}

// List 返回分页的并联组列表（仅管理员可查看）
func (h *ParallelHandler) List(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
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
	if !middleware.GetIsSystemAdmin(c) {
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
	if !middleware.GetIsSystemAdmin(c) {
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
	if !middleware.GetIsSystemAdmin(c) {
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
	if !middleware.GetIsSystemAdmin(c) {
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

// Sync 向并联组内设备批量下发并机配置命令（协议驱动：V2.1 控制参数 set_master_slave）。
// 主机 → set_master_slave=1；组内其余成员 → set_master_slave=0。
// 逐台复用 SendCommand 通道（含 command_logs 审计 + desired 状态闭环 + 离线队列）。
func (h *ParallelHandler) Sync(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
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

	// 校验：组必须包含主机且主机在成员列表内，成员非空
	if group.MasterSN == "" {
		response.Error(c, 400, "并联组未配置主机，无法同步")
		return
	}
	members := append([]string{}, group.DeviceSNs...)
	if len(members) == 0 {
		response.Error(c, 400, "并联组没有成员设备，无法同步")
		return
	}

	type result struct {
		SN      string `json:"sn"`
		Role    string `json:"role"`
		TaskID  string `json:"task_id,omitempty"`
		Error   string `json:"error,omitempty"`
		Queued  bool   `json:"queued,omitempty"`
	}
	results := make([]result, 0, len(members))

	for _, sn := range members {
		setMaster := sn == group.MasterSN
		res := result{SN: sn, Role: "slave"}
		if setMaster {
			res.Role = "master"
		}

		value := 0
		if setMaster {
			value = 1
		}
		taskID, err := h.deviceService.SendCommand(c.Request.Context(), sn, "set_master_slave", map[string]interface{}{"value": value})
		if err != nil {
			res.Error = err.Error()
		} else {
			res.TaskID = taskID
		}
		results = append(results, res)
	}

	logger.Info("Parallel group sync dispatched",
		zap.Int64("group_id", id),
		zap.String("master_sn", group.MasterSN),
		zap.Int("members", len(members)))
	response.Success(c, gin.H{"group_id": id, "results": results})
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
