package handler

import (
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type OTAHandler struct {
	otaService *service.OTAService
}

func NewOTAHandler(otaService *service.OTAService) *OTAHandler {
	return &OTAHandler{otaService: otaService}
}

type CreateFirmwareRequest struct {
	Model      string `json:"model" binding:"required"`
	Version    string `json:"version" binding:"required"`
	FileURL    string `json:"file_url" binding:"required"`
	FileSize   int64  `json:"file_size"`
	FileMD5    string `json:"file_md5"`
	FileSHA256 string `json:"file_sha256"`
	Changelog  string `json:"changelog"`
	IsForce    bool   `json:"is_force"`
}

func (h *OTAHandler) CreateFirmware(c *gin.Context) {
	var req CreateFirmwareRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	fw := &service.CreateFirmwareReq{
		Model:      req.Model,
		Version:    req.Version,
		FileURL:    req.FileURL,
		FileSize:   req.FileSize,
		FileMD5:    req.FileMD5,
		FileSHA256: req.FileSHA256,
		Changelog:  req.Changelog,
		IsForce:    req.IsForce,
	}
	if err := h.otaService.CreateFirmware(c.Request.Context(), fw); err != nil {
		response.InternalError(c, "创建固件失败")
		return
	}
	response.SuccessWithMessage(c, "固件创建成功", nil)
}

func (h *OTAHandler) ListFirmware(c *gin.Context) {
	model := c.Query("model")
	list, err := h.otaService.ListFirmware(c.Request.Context(), model)
	if err != nil {
		response.InternalError(c, "查询固件列表失败")
		return
	}
	response.Success(c, list)
}

func (h *OTAHandler) GetFirmware(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.BadRequest(c, "invalid id")
		return
	}
	fw, err := h.otaService.GetFirmware(c.Request.Context(), id)
	if err != nil {
		response.NotFound(c, "固件不存在")
		return
	}
	response.Success(c, fw)
}

func (h *OTAHandler) DeleteFirmware(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.BadRequest(c, "invalid id")
		return
	}
	if err := h.otaService.DeleteFirmware(c.Request.Context(), id); err != nil {
		response.InternalError(c, "删除固件失败")
		return
	}
	response.SuccessWithMessage(c, "固件已删除", nil)
}

type CreateTaskRequest struct {
	Name        string   `json:"name" binding:"required"`
	FirmwareID  int64    `json:"firmware_id" binding:"required"`
	Model       string   `json:"model" binding:"required"`
	TargetType  string   `json:"target_type" binding:"required"`
	TargetValue string   `json:"target_value"`
	DeviceSNs   []string `json:"device_sns"`
	Description string   `json:"description"`
}

func (h *OTAHandler) CreateTask(c *gin.Context) {
	var req CreateTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	task, err := h.otaService.CreateTask(c.Request.Context(), &service.CreateTaskReq{
		Name:        req.Name,
		FirmwareID:  req.FirmwareID,
		Model:       req.Model,
		TargetType:  req.TargetType,
		TargetValue: req.TargetValue,
		DeviceSNs:   req.DeviceSNs,
		Description: req.Description,
	})
	if err != nil {
		response.InternalError(c, "创建任务失败: "+err.Error())
		return
	}
	response.Success(c, task)
}

func (h *OTAHandler) ListTasks(c *gin.Context) {
	status := c.Query("status")
	page := parseInt(c.DefaultQuery("page", "1"))
	pageSize := parseInt(c.DefaultQuery("page_size", "20"))
	if pageSize > 100 {
		pageSize = 100
	}

	tasks, total, err := h.otaService.ListTasks(c.Request.Context(), status, page, pageSize)
	if err != nil {
		response.InternalError(c, "查询任务列表失败")
		return
	}
	response.Success(c, gin.H{"items": tasks, "total": total})
}

func (h *OTAHandler) GetTask(c *gin.Context) {
	id := c.Param("id")
	task, err := h.otaService.GetTask(c.Request.Context(), id)
	if err != nil {
		response.NotFound(c, "任务不存在")
		return
	}
	devices, _ := h.otaService.ListTaskDevices(c.Request.Context(), id)
	response.Success(c, gin.H{"task": task, "devices": devices})
}

func (h *OTAHandler) DispatchTask(c *gin.Context) {
	id := c.Param("id")
	if err := h.otaService.DispatchTask(c.Request.Context(), id); err != nil {
		response.InternalError(c, "任务下发失败: "+err.Error())
		return
	}
	response.SuccessWithMessage(c, "任务已下发", nil)
}
