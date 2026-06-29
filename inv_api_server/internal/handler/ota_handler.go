package handler

import (
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"
	"io"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

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
	TargetChip string `json:"target_chip" binding:"required"`
	Version    string `json:"version"`
	FileURL    string `json:"file_url" binding:"required"`
	FileSize   int64  `json:"file_size"`
	FileMD5    string `json:"file_md5"`
	FileSHA256 string `json:"file_sha256"`
	Changelog  string `json:"changelog"`
	IsForce    bool   `json:"is_force"`
}

func (h *OTAHandler) CreateFirmware(c *gin.Context) {
	contentType := c.ContentType()

	// 支持 multipart/form-data 文件上传
	if contentType == "multipart/form-data" {
		model := strings.TrimSpace(c.PostForm("model"))
		targetChip := strings.TrimSpace(c.PostForm("target_chip"))
		version := strings.TrimSpace(c.PostForm("version"))
		changelog := c.PostForm("changelog")
		isForce := c.PostForm("is_force") == "true"

		if model == "" || targetChip == "" {
			response.BadRequest(c, "型号和目标芯片必填")
			return
		}

		safePattern := regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)
		if !safePattern.MatchString(model) {
			response.BadRequest(c, "型号包含非法字符")
			return
		}
		if version != "" && !safePattern.MatchString(version) {
			response.BadRequest(c, "版本号包含非法字符")
			return
		}

		file, err := c.FormFile("file")
		if err != nil {
			response.BadRequest(c, "请选择固件文件")
			return
		}

		// 保存文件到 /data/firmware/ 目录
		uploadDir := "/data/firmware"
		os.MkdirAll(uploadDir, 0755)

		ext := filepath.Ext(file.Filename)
		if ext != "" && !safePattern.MatchString(ext[1:]) {
			response.BadRequest(c, "文件扩展名包含非法字符")
			return
		}
		filename := fmt.Sprintf("%s_%s%s", model, version, ext)
		savePath := filepath.Join(uploadDir, filename)

		if err := c.SaveUploadedFile(file, savePath); err != nil {
			response.InternalError(c, "保存文件失败")
			return
		}

		// 计算文件MD5和SHA256
		f, err := os.Open(savePath)
		if err != nil {
			response.InternalError(c, "读取文件失败")
			return
		}
		defer f.Close()

		md5Hash := md5.New()
		sha256Hash := sha256.New()
		writer := io.MultiWriter(md5Hash, sha256Hash)
		if _, err := io.Copy(writer, f); err != nil {
			response.InternalError(c, "计算文件哈希失败")
			return
		}

		fileURL := fmt.Sprintf("/firmware/%s", filename)

		fw := &service.CreateFirmwareReq{
			Model:      model,
			TargetChip: targetChip,
			Version:    version,
			FileURL:    fileURL,
			FileSize:   file.Size,
			FileMD5:    fmt.Sprintf("%x", md5Hash.Sum(nil)),
			FileSHA256: fmt.Sprintf("%x", sha256Hash.Sum(nil)),
			Changelog:  changelog,
			IsForce:    isForce,
		}
		if err := h.otaService.CreateFirmware(c.Request.Context(), fw); err != nil {
			response.InternalError(c, "创建固件失败")
			return
		}
		response.SuccessWithMessage(c, "固件上传成功", nil)
		return
	}

	// 支持 JSON 方式
	var req CreateFirmwareRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	fw := &service.CreateFirmwareReq{
		Model:      req.Model,
		TargetChip: req.TargetChip,
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
	Name              string   `json:"name" binding:"required"`
	FirmwareID        int64    `json:"firmware_id" binding:"required"`
	Model             string   `json:"model" binding:"required"`
	TargetType        string   `json:"target_type" binding:"required"`
	TargetValue       string   `json:"target_value"`
	DeviceSNs         []string `json:"device_sns"`
	Description       string   `json:"description"`
	PushStrategy      string   `json:"push_strategy"`
	PushPercentage    int      `json:"push_percentage"`
	BatchSize         int      `json:"batch_size"`
	ScheduledAt       string   `json:"scheduled_at"`
	AutoRollback      bool     `json:"auto_rollback"`
	RollbackThreshold int      `json:"rollback_threshold"`
}

func parseScheduledAt(s string) *time.Time {
	if s == "" {
		return nil
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		t2, err2 := time.Parse("2006-01-02T15:04:05Z07:00", s)
		if err2 != nil {
			return nil
		}
		return &t2
	}
	return &t
}

func (h *OTAHandler) CreateTask(c *gin.Context) {
	var req CreateTaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	task, err := h.otaService.CreateTask(c.Request.Context(), &service.CreateTaskReq{
		Name:              req.Name,
		FirmwareID:        req.FirmwareID,
		Model:             req.Model,
		TargetType:        req.TargetType,
		TargetValue:       req.TargetValue,
		DeviceSNs:         req.DeviceSNs,
		Description:       req.Description,
		PushStrategy:      req.PushStrategy,
		PushPercentage:    req.PushPercentage,
		BatchSize:         req.BatchSize,
		ScheduledAt:       parseScheduledAt(req.ScheduledAt),
		AutoRollback:      req.AutoRollback,
		RollbackThreshold: req.RollbackThreshold,
	})
	if err != nil {
		log.Printf("[CreateTask] error: model=%s, err=%v", req.Model, err)
		response.InternalError(c, "创建任务失败，请稍后重试")
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
	response.Success(c, task)
}

// GetTaskDevices 获取任务设备列表
func (h *OTAHandler) GetTaskDevices(c *gin.Context) {
	id := c.Param("id")
	devices, err := h.otaService.ListTaskDevices(c.Request.Context(), id)
	if err != nil {
		response.InternalError(c, "获取任务设备列表失败")
		return
	}
	response.Success(c, devices)
}

func (h *OTAHandler) DispatchTask(c *gin.Context) {
	id := c.Param("id")
	if err := h.otaService.DispatchTask(c.Request.Context(), id); err != nil {
		log.Printf("[DispatchTask] error: id=%s, err=%v", id, err)
		response.InternalError(c, "任务下发失败，请稍后重试")
		return
	}
	response.SuccessWithMessage(c, "任务已下发", nil)
}

// NotifyDevices 通知设备有新版本可用（不立即执行升级）
func (h *OTAHandler) NotifyDevices(c *gin.Context) {
	id := c.Param("id")
	if err := h.otaService.NotifyDevices(c.Request.Context(), id); err != nil {
		log.Printf("[NotifyDevices] error: id=%s, err=%v", id, err)
		response.InternalError(c, "通知设备失败，请稍后重试")
		return
	}
	response.SuccessWithMessage(c, "已通知设备有新版本", nil)
}

// DeleteTask 删除任务
func (h *OTAHandler) DeleteTask(c *gin.Context) {
	id := c.Param("id")
	if err := h.otaService.DeleteTask(c.Request.Context(), id); err != nil {
		log.Printf("[DeleteTask] error: id=%s, err=%v", id, err)
		response.InternalError(c, "删除任务失败，请稍后重试")
		return
	}
	response.SuccessWithMessage(c, "任务已删除", nil)
}

// CheckUpdate 检查设备是否有可用更新
func (h *OTAHandler) CheckUpdate(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.BadRequest(c, "设备SN不能为空")
		return
	}
	targetChip := c.DefaultQuery("target_chip", "")

	// 优先检查是否有管理员推送的OTA任务
	task, fw, err := h.otaService.GetPendingOTAForDevice(c.Request.Context(), sn)
	if err == nil && task != nil && fw != nil {
		// 有管理员推送的OTA任务
		response.Success(c, gin.H{
			"has_update":    true,
			"firmware_id":   fw.ID,
			"main_version":  fw.MainVersion,
			"version":       fw.Version,
			"target_chip":   fw.TargetChip,
			"download_url":  fw.FileURL,
			"file_size":     fw.FileSize,
			"file_md5":      fw.FileMD5,
			"changelog":     fw.Changelog,
			"is_force":      fw.IsForce,
			"task_id":       task.ID,
			"task_name":     task.Name,
			"is_admin_push": true,
		})
		return
	}

	// 获取设备信息
	device, err := h.otaService.GetDeviceBySN(c.Request.Context(), sn)
	if err != nil || device == nil {
		response.NotFound(c, "设备不存在")
		return
	}

	// 获取该型号的最新固件
	firmware, err := h.otaService.GetLatestFirmware(c.Request.Context(), device.Model, targetChip)
	if err != nil || firmware == nil {
		response.Success(c, gin.H{"has_update": false, "message": "暂无可用固件"})
		return
	}

	// 比较版本
	hasUpdate := device.FirmwareVersion != firmware.Version
	response.Success(c, gin.H{
		"has_update":      hasUpdate,
		"firmware_id":     firmware.ID,
		"main_version":    firmware.MainVersion,
		"target_chip":     firmware.TargetChip,
		"current_version": device.FirmwareVersion,
		"download_url":    firmware.FileURL,
		"file_name":       firmware.Model + "_" + firmware.Version + ".bin",
		"file_size":       firmware.FileSize,
		"file_md5":        firmware.FileMD5,
		"changelog":       firmware.Changelog,
		"is_force":        firmware.IsForce,
		"is_admin_push":   false,
	})
}

// TriggerOTA 触发设备OTA升级
func (h *OTAHandler) TriggerOTA(c *gin.Context) {
	var req struct {
		SN         string `json:"sn" binding:"required"`
		FirmwareID int64  `json:"firmware_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	task, err := h.otaService.TriggerSingleDeviceOTA(c.Request.Context(), req.SN, req.FirmwareID)
	if err != nil {
		log.Printf("[TriggerOTA] error: sn=%s, firmware_id=%d, err=%v", req.SN, req.FirmwareID, err)
		response.InternalError(c, "触发升级失败，请稍后重试")
		return
	}
	response.Success(c, gin.H{"task_id": task.ID, "message": "升级任务已创建"})
}

// GetTaskProgress 获取任务进度
func (h *OTAHandler) GetTaskProgress(c *gin.Context) {
	taskID := c.Param("id")
	task, err := h.otaService.GetTask(c.Request.Context(), taskID)
	if err != nil {
		response.NotFound(c, "任务不存在")
		return
	}

	devices, _ := h.otaService.ListTaskDevices(c.Request.Context(), taskID)

	// 计算总体进度，包含正在升级中的设备进度
	total := len(devices)
	completed := 0
	failed := 0
	var totalProgress float64
	for _, d := range devices {
		switch d.Status {
		case "success":
			completed++
			totalProgress += 100
		case "failed":
			failed++
			totalProgress += 100
		case "upgrading", "running":
			totalProgress += float64(d.Progress)
		}
	}

	progress := 0.0
	if total > 0 {
		progress = totalProgress / float64(total)
	}

	response.Success(c, gin.H{
		"task_id":   task.ID,
		"status":    task.Status,
		"progress":  progress,
		"total":     total,
		"completed": completed,
		"failed":    failed,
	})
}

// GetDeviceOTAStatus 获取设备OTA状态
func (h *OTAHandler) GetDeviceOTAStatus(c *gin.Context) {
	sn := c.Param("sn")
	// 获取设备最新的OTA任务
	taskDevice, err := h.otaService.GetLatestTaskDevice(c.Request.Context(), sn)
	if err != nil || taskDevice == nil {
		response.Success(c, gin.H{"status": "idle", "message": "无升级任务"})
		return
	}
	response.Success(c, taskDevice)
}

// GetDeviceOTAHistory 获取设备OTA历史
func (h *OTAHandler) GetDeviceOTAHistory(c *gin.Context) {
	sn := c.Param("sn")
	page := parseInt(c.DefaultQuery("page", "1"))
	pageSize := parseInt(c.DefaultQuery("page_size", "20"))

	history, total, err := h.otaService.GetDeviceOTAHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.InternalError(c, "查询历史失败")
		return
	}
	response.Success(c, gin.H{"items": history, "total": total})
}

// GetAllFirmware 获取所有固件（不分页，供APP选择）
func (h *OTAHandler) GetAllFirmware(c *gin.Context) {
	list, err := h.otaService.ListFirmware(c.Request.Context(), "")
	if err != nil {
		response.InternalError(c, "查询固件列表失败")
		return
	}
	response.Success(c, list)
}

// ========== App版本管理 ==========

// CheckAppUpdate 检查App是否有新版本
func (h *OTAHandler) CheckAppUpdate(c *gin.Context) {
	platform := c.Query("platform")
	versionCodeStr := c.DefaultQuery("version_code", "0")

	if platform != "android" && platform != "ios" {
		response.BadRequest(c, "platform 必须是 android 或 ios")
		return
	}

	versionCode := parseInt(versionCodeStr)

	latest, hasUpdate, err := h.otaService.CheckAppUpdate(c.Request.Context(), platform, versionCode)
	if err != nil {
		// 没有记录也算无更新
		response.Success(c, gin.H{"has_update": false})
		return
	}

	response.Success(c, gin.H{
		"has_update":            hasUpdate,
		"latest_version_code":   latest.VersionCode,
		"latest_version_name":   latest.VersionName,
		"download_url":          latest.DownloadURL,
		"file_size":             latest.FileSize,
		"file_md5":              latest.FileMD5,
		"changelog":             latest.Changelog,
		"is_force":              latest.IsForce,
		"min_supported_version": latest.MinSupportedVersion,
		"should_force_update":   latest.IsForce || (latest.MinSupportedVersion > 0 && versionCode < latest.MinSupportedVersion),
	})
}

// CreateAppVersion 创建App版本（管理员）
func (h *OTAHandler) CreateAppVersion(c *gin.Context) {
	var req struct {
		Platform            string `json:"platform" binding:"required"`
		VersionCode         int    `json:"version_code" binding:"required"`
		VersionName         string `json:"version_name" binding:"required"`
		DownloadURL         string `json:"download_url"`
		FileSize            int64  `json:"file_size"`
		FileMD5             string `json:"file_md5"`
		Changelog           string `json:"changelog"`
		IsForce             bool   `json:"is_force"`
		MinSupportedVersion int    `json:"min_supported_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	if req.Platform != "android" && req.Platform != "ios" {
		response.BadRequest(c, "platform 必须是 android 或 ios")
		return
	}

	v := &model.AppVersion{
		Platform:            req.Platform,
		VersionCode:         req.VersionCode,
		VersionName:         req.VersionName,
		DownloadURL:         req.DownloadURL,
		FileSize:            req.FileSize,
		FileMD5:             req.FileMD5,
		Changelog:           req.Changelog,
		IsForce:             req.IsForce,
		MinSupportedVersion: req.MinSupportedVersion,
	}

	if err := h.otaService.CreateAppVersion(c.Request.Context(), v); err != nil {
		log.Printf("[CreateAppVersion] error: %v", err)
		response.InternalError(c, "创建版本失败")
		return
	}
	response.Success(c, v)
}

// ListAppVersions 列出App版本（管理员）
func (h *OTAHandler) ListAppVersions(c *gin.Context) {
	platform := c.Query("platform")
	list, err := h.otaService.ListAppVersions(c.Request.Context(), platform)
	if err != nil {
		response.InternalError(c, "查询版本列表失败")
		return
	}
	response.Success(c, list)
}

// DeleteAppVersion 删除App版本（管理员）
func (h *OTAHandler) DeleteAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.BadRequest(c, "无效的ID")
		return
	}
	if err := h.otaService.DeleteAppVersion(c.Request.Context(), int64(id)); err != nil {
		response.InternalError(c, "删除失败")
		return
	}
	response.SuccessWithMessage(c, "删除成功", nil)
}

// UpdateAppVersionRollout 更新App版本灰度比例
func (h *OTAHandler) UpdateAppVersionRollout(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.BadRequest(c, "无效的ID")
		return
	}
	var req struct {
		Percentage int `json:"percentage"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Percentage < 0 || req.Percentage > 100 {
		response.BadRequest(c, "灰度比例需在0-100之间")
		return
	}
	if err := h.otaService.UpdateAppVersionRollout(c.Request.Context(), int64(id), req.Percentage); err != nil {
		response.InternalError(c, "更新失败")
		return
	}
	response.SuccessWithMessage(c, "灰度比例已更新", nil)
}

// RollbackAppVersion 回滚App版本
func (h *OTAHandler) RollbackAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.BadRequest(c, "无效的ID")
		return
	}
	if err := h.otaService.RollbackAppVersion(c.Request.Context(), int64(id)); err != nil {
		response.InternalError(c, "回滚失败")
		return
	}
	response.SuccessWithMessage(c, "版本已回滚", nil)
}

// RestoreAppVersion 恢复已回滚的App版本
func (h *OTAHandler) RestoreAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.BadRequest(c, "无效的ID")
		return
	}
	var req struct {
		Percentage int `json:"percentage"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Percentage = 100
	}
	if err := h.otaService.RestoreAppVersion(c.Request.Context(), int64(id), req.Percentage); err != nil {
		response.InternalError(c, "恢复失败")
		return
	}
	response.SuccessWithMessage(c, "版本已恢复", nil)
}
