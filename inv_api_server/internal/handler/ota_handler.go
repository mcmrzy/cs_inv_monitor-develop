package handler

import (
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
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
			response.HandleError(c, apperr.BadRequest("型号和目标芯片必填"))
			return
		}

		safePattern := regexp.MustCompile(`^[a-zA-Z0-9._-]+$`)
		if !safePattern.MatchString(model) {
			response.HandleError(c, apperr.BadRequest("型号包含非法字符"))
			return
		}
		if version != "" && !safePattern.MatchString(version) {
			response.HandleError(c, apperr.BadRequest("版本号包含非法字符"))
			return
		}

		file, err := c.FormFile("file")
		if err != nil {
			response.HandleError(c, apperr.BadRequest("请选择固件文件"))
			return
		}

		// 保存文件到 /data/firmware/ 目录
		uploadDir := "/data/firmware"
		os.MkdirAll(uploadDir, 0755)

		ext := filepath.Ext(file.Filename)
		if ext != "" && !safePattern.MatchString(ext[1:]) {
			response.HandleError(c, apperr.BadRequest("文件扩展名包含非法字符"))
			return
		}
		filename := fmt.Sprintf("%s_%s%s", model, version, ext)
		savePath := filepath.Join(uploadDir, filename)

		if err := c.SaveUploadedFile(file, savePath); err != nil {
			response.HandleError(c, apperr.Internal("保存文件失败", err))
			return
		}

		// 计算文件MD5和SHA256
		f, err := os.Open(savePath)
		if err != nil {
			response.HandleError(c, apperr.Internal("读取文件失败", err))
			return
		}
		defer f.Close()

		md5Hash := md5.New()
		sha256Hash := sha256.New()
		writer := io.MultiWriter(md5Hash, sha256Hash)
		if _, err := io.Copy(writer, f); err != nil {
			response.HandleError(c, apperr.Internal("计算文件哈希失败", err))
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
			response.HandleError(c, apperr.Internal("创建固件失败", err))
			return
		}
		response.SuccessWithMessage(c, "固件上传成功", nil)
		return
	}

	// 支持 JSON 方式
	var req CreateFirmwareRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
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
		response.HandleError(c, apperr.Internal("创建固件失败", err))
		return
	}
	response.SuccessWithMessage(c, "固件创建成功", nil)
}

func (h *OTAHandler) ListFirmware(c *gin.Context) {
	model := c.Query("model")
	list, err := h.otaService.ListFirmware(c.Request.Context(), model)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询固件列表失败", err))
		return
	}
	response.Success(c, list)
}

func (h *OTAHandler) GetFirmware(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	fw, err := h.otaService.GetFirmware(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.NotFound("固件不存在"))
		return
	}
	response.Success(c, fw)
}

func (h *OTAHandler) DeleteFirmware(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.DeleteFirmware(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("删除固件失败", err))
		return
	}
	response.SuccessWithMessage(c, "固件已删除", nil)
}

// PushUpgrade 管理员推送升级
func (h *OTAHandler) PushUpgrade(c *gin.Context) {
	var req struct {
		FirmwareID int64    `json:"firmware_id" binding:"required"`
		DeviceSNs  []string `json:"device_sns" binding:"required"`
		Immediate  bool     `json:"immediate"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if len(req.DeviceSNs) == 0 {
		response.HandleError(c, apperr.BadRequest("请选择至少一台设备"))
		return
	}

	if err := h.otaService.PushUpgrade(c.Request.Context(), &service.PushUpgradeReq{
		FirmwareID: req.FirmwareID,
		DeviceSNs:  req.DeviceSNs,
		Immediate:  req.Immediate,
	}); err != nil {
		log.Printf("[PushUpgrade] error: firmware_id=%d, err=%v", req.FirmwareID, err)
		response.HandleError(c, apperr.Internal("推送升级失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "升级已推送", nil)
}

// GetUpgradeDashboard 升级管理面板（按固件分组聚合）
func (h *OTAHandler) GetUpgradeDashboard(c *gin.Context) {
	page := parseInt(c.DefaultQuery("page", "1"))
	pageSize := parseInt(c.DefaultQuery("page_size", "20"))
	if pageSize > 100 {
		pageSize = 100
	}
	items, total, err := h.otaService.GetUpgradeDashboard(c.Request.Context(), page, pageSize)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级面板失败", err))
		return
	}
	response.Success(c, gin.H{"items": items, "total": total})
}

// GetFirmwareUpgradeDetails 获取指定固件的所有设备升级详情
func (h *OTAHandler) GetFirmwareUpgradeDetails(c *gin.Context) {
	firmwareID := parseInt(c.Param("firmwareId"))
	if firmwareID == 0 {
		response.HandleError(c, apperr.BadRequest("invalid firmware_id"))
		return
	}
	details, err := h.otaService.GetFirmwareUpgradeDetails(c.Request.Context(), int64(firmwareID))
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级详情失败", err))
		return
	}
	response.Success(c, details)
}

// RetryUpgrade 重试失败的设备升级
func (h *OTAHandler) RetryUpgrade(c *gin.Context) {
	var req struct {
		FirmwareID int64    `json:"firmware_id" binding:"required"`
		DeviceSNs  []string `json:"device_sns" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if err := h.otaService.RetryUpgrade(c.Request.Context(), req.FirmwareID, req.DeviceSNs); err != nil {
		response.HandleError(c, apperr.Internal("重试失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "已重试", nil)
}

// CancelUpgrade 取消待执行的升级
func (h *OTAHandler) CancelUpgrade(c *gin.Context) {
	var req struct {
		DeviceSN   string `json:"device_sn" binding:"required"`
		FirmwareID int64  `json:"firmware_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	if err := h.otaService.CancelUpgrade(c.Request.Context(), req.DeviceSN, req.FirmwareID); err != nil {
		response.HandleError(c, apperr.Internal("取消失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "已取消", nil)
}

// DeleteUpgradesByFirmware 删除指定固件的所有升级记录
func (h *OTAHandler) DeleteUpgradesByFirmware(c *gin.Context) {
	firmwareID := parseInt(c.Param("firmwareId"))
	if firmwareID == 0 {
		response.HandleError(c, apperr.BadRequest("invalid firmware_id"))
		return
	}
	if err := h.otaService.DeleteUpgradesByFirmwareID(c.Request.Context(), int64(firmwareID)); err != nil {
		response.HandleError(c, apperr.Internal("删除失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "已删除", nil)
}

// CheckUpdate 检查设备是否有可用更新
func (h *OTAHandler) CheckUpdate(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}

	// 获取设备信息
	device, err := h.otaService.GetDeviceBySN(c.Request.Context(), sn)
	if err != nil || device == nil {
		response.HandleError(c, apperr.NotFound("设备不存在"))
		return
	}

	// 优先检查升级包模式的待执行升级
	pkgUpgrades, pkg, _ := h.otaService.CheckPendingPackageUpgrade(c.Request.Context(), sn)
	if pkgUpgrades != nil && pkg != nil && len(pkgUpgrades) > 0 {
		// 构造 chips_to_upgrade 列表
		chipsToUpgrade := []map[string]interface{}{}
		for _, du := range pkgUpgrades {
			fw, _ := h.otaService.GetFirmware(c.Request.Context(), du.FirmwareID)
			if fw == nil {
				continue
			}
			chipsToUpgrade = append(chipsToUpgrade, map[string]interface{}{
				"chip":         du.TargetChip,
				"current":      du.OldVersion,
				"target":       du.FirmwareVersion,
				"firmware_id":  fw.ID,
				"download_url": h.otaService.BuildDownloadURL(fw.FileURL),
				"file_size":    fw.FileSize,
				"file_md5":     fw.FileMD5,
				"upgrade_id":   du.ID,
			})
		}

		// 使用第一个待升级芯片的信息作为主信息
		firstFW := pkgUpgrades[0]
		response.Success(c, gin.H{
			"has_update":             true,
			"upgrade_mode":           "package",
			"device_model":           device.Model,
			"current_main_version":   device.MainVersion,
			"main_version":           pkg.MainVersion,
			"firmware_id":            firstFW.FirmwareID,
			"version":                firstFW.FirmwareVersion,
			"target_chip":            firstFW.TargetChip,
			"current_version":        firstFW.OldVersion,
			"chips_to_upgrade":       chipsToUpgrade,
			"changelog":              pkg.Changelog,
			"is_force":               pkg.IsForce,
			"upgrade_id":             firstFW.ID,
			"is_admin_push":          true,
		})
		return
	}

	// 回退到旧的单固件检查逻辑
	du, fw, err := h.otaService.CheckPendingUpgrade(c.Request.Context(), sn)
	if err == nil && du != nil && fw != nil {
		// 获取该芯片的当前版本（而非合并版本）
		currentChipVersion := ""
		switch fw.TargetChip {
		case "arm":
			currentChipVersion = device.FirmwareArm
		case "esp":
			currentChipVersion = device.FirmwareEsp
		case "dsp":
			currentChipVersion = device.FirmwareDSP
		case "bms":
			currentChipVersion = device.FirmwareBMS
		}
		if currentChipVersion == "" {
			currentChipVersion = du.OldVersion
		}
		response.Success(c, gin.H{
			"has_update":             true,
			"upgrade_mode":           "single",
			"device_model":           device.Model,
			"current_main_version":   device.MainVersion,
			"firmware_id":            fw.ID,
			"main_version":           fw.MainVersion,
			"version":                fw.Version,
			"target_chip":            fw.TargetChip,
			"current_version":        currentChipVersion,
			"download_url":           h.otaService.BuildDownloadURL(fw.FileURL),
			"file_name":              fw.Model + "_" + fw.Version + ".bin",
			"file_size":              fw.FileSize,
			"file_md5":               fw.FileMD5,
			"changelog":              fw.Changelog,
			"is_force":               fw.IsForce,
			"upgrade_id":             du.ID,
			"is_admin_push":          true,
		})
		return
	}

	// 没有待执行的升级任务，检查是否有已发布的升级包
	packages, _ := h.otaService.GetAvailablePackagesForDevice(c.Request.Context(), sn, 0)
	if len(packages) > 0 {
		// 有已发布的升级包，返回给 App 端显示
		// 使用第一个升级包的信息作为主信息
		firstPkg := packages[0]
		chipsToUpgrade := []map[string]interface{}{}
		chipVersions := map[string]string{
			"arm": device.FirmwareArm,
			"esp": device.FirmwareEsp,
			"dsp": device.FirmwareDSP,
			"bms": device.FirmwareBMS,
		}
		for _, item := range firstPkg.Items {
			chipsToUpgrade = append(chipsToUpgrade, map[string]interface{}{
				"chip":         item.TargetChip,
				"current":      chipVersions[item.TargetChip],
				"target":       item.FirmwareVersion,
				"firmware_id":  item.FirmwareID,
				"firmware_version": item.FirmwareVersion,
			})
		}

		response.Success(c, gin.H{
			"has_update":             true,
			"upgrade_mode":           "package",
			"device_model":           device.Model,
			"current_main_version":   device.MainVersion,
			"main_version":           firstPkg.UserVersion, // 使用用户可见版本号
			"changelog":              firstPkg.UserChangelog,
			"is_force":               firstPkg.IsForce,
			"firmware_arm":           device.FirmwareArm,
			"firmware_esp":           device.FirmwareEsp,
			"firmware_dsp":           device.FirmwareDSP,
			"firmware_bms":           device.FirmwareBMS,
			"chips_to_upgrade":       chipsToUpgrade,
			"available_packages":     packages, // 同时返回所有可用升级包
			"message":                "有可用的升级包",
		})
		return
	}

	response.Success(c, gin.H{
		"has_update":             false,
		"device_model":           device.Model,
		"current_main_version":   device.MainVersion,
		"firmware_arm":           device.FirmwareArm,
		"firmware_esp":           device.FirmwareEsp,
		"firmware_dsp":           device.FirmwareDSP,
		"firmware_bms":           device.FirmwareBMS,
		"message":                "暂无可用更新",
	})
}

// TriggerOTA 触发设备OTA升级（App端调用，创建 source='app' 的升级任务）
func (h *OTAHandler) TriggerOTA(c *gin.Context) {
	var req struct {
		SN        string `json:"sn" binding:"required"`
		PackageID int64  `json:"package_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}

	userID := c.GetInt64("user_id")
	taskID, err := h.otaService.TriggerUpgradeFromApp(c.Request.Context(), userID, req.SN, req.PackageID)
	if err != nil {
		log.Printf("[TriggerOTA] error: sn=%s, package_id=%d, err=%v", req.SN, req.PackageID, err)
		response.HandleError(c, apperr.Internal("触发升级失败: "+err.Error(), err))
		return
	}
	response.Success(c, gin.H{"task_id": taskID, "message": "升级已触发"})
}

// ResendUpgradeCommand 重新发送待执行升级的MQTT命令
func (h *OTAHandler) ResendUpgradeCommand(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}

	userID := c.GetInt64("user_id")
	owned, err := h.otaService.CheckDeviceOwnership(c.Request.Context(), sn, userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备信息失败", err))
		return
	}
	if !owned {
		response.HandleError(c, apperr.Forbidden("设备不属于当前用户"))
		return
	}

	err = h.otaService.ResendPendingUpgradeCommand(c.Request.Context(), sn)
	if err != nil {
		// 没有待执行的升级任务，尝试获取可用升级包并创建新任务
		packages, _ := h.otaService.GetAvailablePackagesForDevice(c.Request.Context(), sn, userID)
		if len(packages) > 0 {
			// 使用第一个可用升级包创建升级任务
			taskID, triggerErr := h.otaService.TriggerUpgradeFromApp(c.Request.Context(), userID, sn, packages[0].ID)
			if triggerErr != nil {
				log.Printf("[ResendUpgradeCommand] trigger error: sn=%s, err=%v", sn, triggerErr)
				response.HandleError(c, apperr.Internal("创建升级任务失败: "+triggerErr.Error(), triggerErr))
				return
			}
			response.Success(c, gin.H{"message": "升级任务已创建", "task_id": taskID})
			return
		}
		log.Printf("[ResendUpgradeCommand] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("重新发送升级命令失败: "+err.Error(), err))
		return
	}
	response.Success(c, gin.H{"message": "升级命令已重新发送"})
}

// GetDeviceOTAStatus 获取设备当前升级状态
func (h *OTAHandler) GetDeviceOTAStatus(c *gin.Context) {
	sn := c.Param("sn")
	upgrade, err := h.otaService.GetLatestTaskDevice(c.Request.Context(), sn)
	if err != nil || upgrade == nil {
		response.Success(c, gin.H{"status": "idle", "message": "无升级任务"})
		return
	}
	response.Success(c, upgrade)
}

// GetDeviceOTAHistory 获取设备OTA历史
func (h *OTAHandler) GetDeviceOTAHistory(c *gin.Context) {
	sn := c.Param("sn")
	page := parseInt(c.DefaultQuery("page", "1"))
	pageSize := parseInt(c.DefaultQuery("page_size", "20"))

	history, total, err := h.otaService.GetDeviceOTAHistory(c.Request.Context(), sn, page, pageSize)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询历史失败", err))
		return
	}
	response.Success(c, gin.H{"items": history, "total": total})
}

// GetAllFirmware 获取所有固件（不分页，供APP选择）
func (h *OTAHandler) GetAllFirmware(c *gin.Context) {
	list, err := h.otaService.ListFirmware(c.Request.Context(), "")
	if err != nil {
		response.HandleError(c, apperr.Internal("查询固件列表失败", err))
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
		response.HandleError(c, apperr.BadRequest("platform 必须是 android 或 ios"))
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
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	if req.Platform != "android" && req.Platform != "ios" {
		response.HandleError(c, apperr.BadRequest("platform 必须是 android 或 ios"))
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
		response.HandleError(c, apperr.Internal("创建版本失败", err))
		return
	}
	response.Success(c, v)
}

// ListAppVersions 列出App版本（管理员）
func (h *OTAHandler) ListAppVersions(c *gin.Context) {
	platform := c.Query("platform")
	list, err := h.otaService.ListAppVersions(c.Request.Context(), platform)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询版本列表失败", err))
		return
	}
	response.Success(c, list)
}

// DeleteAppVersion 删除App版本（管理员）
func (h *OTAHandler) DeleteAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.HandleError(c, apperr.BadRequest("无效的ID"))
		return
	}
	if err := h.otaService.DeleteAppVersion(c.Request.Context(), int64(id)); err != nil {
		response.HandleError(c, apperr.Internal("删除失败", err))
		return
	}
	response.SuccessWithMessage(c, "删除成功", nil)
}

// UpdateAppVersionRollout 更新App版本灰度比例
func (h *OTAHandler) UpdateAppVersionRollout(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.HandleError(c, apperr.BadRequest("无效的ID"))
		return
	}
	var req struct {
		Percentage int `json:"percentage"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Percentage < 0 || req.Percentage > 100 {
		response.HandleError(c, apperr.BadRequest("灰度比例需在0-100之间"))
		return
	}
	if err := h.otaService.UpdateAppVersionRollout(c.Request.Context(), int64(id), req.Percentage); err != nil {
		response.HandleError(c, apperr.Internal("更新失败", err))
		return
	}
	response.SuccessWithMessage(c, "灰度比例已更新", nil)
}

// RollbackAppVersion 回滚App版本
func (h *OTAHandler) RollbackAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.HandleError(c, apperr.BadRequest("无效的ID"))
		return
	}
	if err := h.otaService.RollbackAppVersion(c.Request.Context(), int64(id)); err != nil {
		response.HandleError(c, apperr.Internal("回滚失败", err))
		return
	}
	response.SuccessWithMessage(c, "版本已回滚", nil)
}

// RestoreAppVersion 恢复已回滚的App版本
func (h *OTAHandler) RestoreAppVersion(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.HandleError(c, apperr.BadRequest("无效的ID"))
		return
	}
	var req struct {
		Percentage int `json:"percentage"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		req.Percentage = 100
	}
	if err := h.otaService.RestoreAppVersion(c.Request.Context(), int64(id), req.Percentage); err != nil {
		response.HandleError(c, apperr.Internal("恢复失败", err))
		return
	}
	response.SuccessWithMessage(c, "版本已恢复", nil)
}

// ========== 升级包管理 ==========

// CreateUpgradePackage 创建升级包
func (h *OTAHandler) CreateUpgradePackage(c *gin.Context) {
	var req struct {
		Model          string   `json:"model" binding:"required"`
		FirmwareIDs    []int64  `json:"firmware_ids" binding:"required"`
		Changelog      string   `json:"changelog"`
		IsForce        bool     `json:"is_force"`
		UserVersion    string   `json:"user_version"`
		UserChangelog  string   `json:"user_changelog"`
		RolloutType    string   `json:"rollout_type"`
		RolloutTargets string   `json:"rollout_targets"`
		IsPublished    bool     `json:"is_published"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if req.RolloutType == "" {
		req.RolloutType = "all"
	}

	userID := c.GetInt64("user_id")
	if err := h.otaService.CreateUpgradePackage(c.Request.Context(), &service.CreatePackageReq{
		Model:          req.Model,
		FirmwareIDs:    req.FirmwareIDs,
		Changelog:      req.Changelog,
		IsForce:        req.IsForce,
		UserVersion:    req.UserVersion,
		UserChangelog:  req.UserChangelog,
		RolloutType:    req.RolloutType,
		RolloutTargets: req.RolloutTargets,
		IsPublished:    req.IsPublished,
		CreatedBy:      userID,
	}); err != nil {
		log.Printf("[CreateUpgradePackage] error: %v", err)
		response.HandleError(c, apperr.Internal("创建升级包失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "升级包创建成功", nil)
}

// ListUpgradePackages 升级包列表
func (h *OTAHandler) ListUpgradePackages(c *gin.Context) {
	modelFilter := c.Query("model")
	list, err := h.otaService.ListUpgradePackages(c.Request.Context(), modelFilter)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级包列表失败", err))
		return
	}
	response.Success(c, list)
}

// GetUpgradePackage 升级包详情
func (h *OTAHandler) GetUpgradePackage(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	pkg, err := h.otaService.GetUpgradePackage(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.NotFound("升级包不存在"))
		return
	}
	response.Success(c, pkg)
}

// DeleteUpgradePackage 删除升级包
func (h *OTAHandler) DeleteUpgradePackage(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.DeleteUpgradePackage(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("删除升级包失败", err))
		return
	}
	response.SuccessWithMessage(c, "升级包已删除", nil)
}

// UpdateUpgradePackage 更新升级包（用户可见信息）
func (h *OTAHandler) UpdateUpgradePackage(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	var req struct {
		UserVersion   *string `json:"user_version"`
		UserChangelog *string `json:"user_changelog"`
		Changelog     *string `json:"changelog"`
		IsForce       *bool   `json:"is_force"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误"))
		return
	}
	if err := h.otaService.UpdateUpgradePackage(c.Request.Context(), id, req.UserVersion, req.UserChangelog, req.Changelog, req.IsForce); err != nil {
		response.HandleError(c, apperr.Internal("更新失败", err))
		return
	}
	response.SuccessWithMessage(c, "更新成功", nil)
}

// PublishPackage 发布升级包
func (h *OTAHandler) PublishPackage(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	var req service.PublishPackageReq
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误"))
		return
	}
	if err := h.otaService.PublishPackage(c.Request.Context(), id, req); err != nil {
		log.Printf("[PublishPackage] error: package_id=%d, err=%v", id, err)
		response.HandleError(c, apperr.Internal("发布失败: "+err.Error(), err))
		return
	}
	response.Success(c, gin.H{"message": "发布成功"})
}

// PushPackageUpgrade 推送升级包
func (h *OTAHandler) PushPackageUpgrade(c *gin.Context) {
	var req struct {
		PackageID      int64    `json:"package_id" binding:"required"`
		DeviceSNs      []string `json:"device_sns" binding:"required"`
		Immediate      bool     `json:"immediate"`
		RolloutPercent int      `json:"rollout_percent"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if len(req.DeviceSNs) == 0 {
		response.HandleError(c, apperr.BadRequest("请选择至少一台设备"))
		return
	}

	userID := c.GetInt64("user_id")
	if err := h.otaService.PushPackageUpgrade(c.Request.Context(), &service.PushPackageUpgradeReq{
		PackageID:      req.PackageID,
		DeviceSNs:      req.DeviceSNs,
		PushedBy:       userID,
		Immediate:      req.Immediate,
		RolloutPercent: req.RolloutPercent,
	}); err != nil {
		log.Printf("[PushPackageUpgrade] error: package_id=%d, err=%v", req.PackageID, err)
		response.HandleError(c, apperr.Internal("推送升级包失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "升级包已推送", nil)
}

// RollbackPackageUpgrade 回滚升级包
func (h *OTAHandler) RollbackPackageUpgrade(c *gin.Context) {
	id := parseInt(c.Param("id"))
	if id == 0 {
		response.HandleError(c, apperr.BadRequest("invalid package_id"))
		return
	}
	var req struct {
		Immediate bool `json:"immediate"`
	}
	_ = c.ShouldBindJSON(&req)

	userID := c.GetInt64("user_id")
	if err := h.otaService.RollbackPackageUpgrade(c.Request.Context(), int64(id), req.Immediate, userID); err != nil {
		response.HandleError(c, apperr.Internal("回滚失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "回滚指令已发送", nil)
}

// GetPackageUpgradeDetails 获取升级包的设备升级详情
func (h *OTAHandler) GetPackageUpgradeDetails(c *gin.Context) {
	packageID := parseInt(c.Param("id"))
	if packageID == 0 {
		response.HandleError(c, apperr.BadRequest("invalid package_id"))
		return
	}
	details, err := h.otaService.GetPackageUpgradesByPackageID(c.Request.Context(), int64(packageID))
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级详情失败", err))
		return
	}
	response.Success(c, details)
}

// ========== 升级任务管理 ==========

// CreateUpgradeTask 创建升级任务
func (h *OTAHandler) CreateUpgradeTask(c *gin.Context) {
	var req struct {
		Name           string   `json:"name"`
		TaskType       string   `json:"task_type" binding:"required"`
		FirmwareID     *int64   `json:"firmware_id"`
		PackageID      *int64   `json:"package_id"`
		Model          string   `json:"model"`
		DeviceSNs      []string `json:"device_sns" binding:"required"`
		ExecuteMode    string   `json:"execute_mode"`
		ScheduledAt    string   `json:"scheduled_at"`
		RolloutPercent int      `json:"rollout_percent"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if len(req.DeviceSNs) == 0 {
		response.HandleError(c, apperr.BadRequest("请至少选择一台设备"))
		return
	}
	if req.ExecuteMode == "" {
		req.ExecuteMode = "manual"
	}
	if req.RolloutPercent <= 0 || req.RolloutPercent > 100 {
		req.RolloutPercent = 100
	}

	var scheduledAt *time.Time
	if req.ExecuteMode == "scheduled" && req.ScheduledAt != "" {
		t, err := time.Parse("2006-01-02T15:04:05Z07:00", req.ScheduledAt)
		if err != nil {
			t, err = time.Parse("2006-01-02 15:04:05", req.ScheduledAt)
		}
		if err == nil {
			scheduledAt = &t
		}
	}

	userID := c.GetInt64("user_id")
	task, err := h.otaService.CreateUpgradeTask(c.Request.Context(), &service.CreateUpgradeTaskReq{
		Name:           req.Name,
		TaskType:       req.TaskType,
		FirmwareID:     req.FirmwareID,
		PackageID:      req.PackageID,
		Model:          req.Model,
		DeviceSNs:      req.DeviceSNs,
		ExecuteMode:    req.ExecuteMode,
		ScheduledAt:    scheduledAt,
		RolloutPercent: req.RolloutPercent,
		CreatedBy:      userID,
	})
	if err != nil {
		log.Printf("[CreateUpgradeTask] error: %v", err)
		response.HandleError(c, apperr.Internal("创建升级任务失败: "+err.Error(), err))
		return
	}
	response.Success(c, task)
}

// ListUpgradeTasks 升级任务列表
func (h *OTAHandler) ListUpgradeTasks(c *gin.Context) {
	page := parseInt(c.DefaultQuery("page", "1"))
	pageSize := parseInt(c.DefaultQuery("page_size", "20"))
	if pageSize > 100 {
		pageSize = 100
	}
	statusFilter := c.Query("status")
	tasks, total, err := h.otaService.ListUpgradeTasks(c.Request.Context(), page, pageSize, statusFilter)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级任务列表失败", err))
		return
	}
	response.Success(c, gin.H{"items": tasks, "total": total})
}

// GetUpgradeTask 获取升级任务详情
func (h *OTAHandler) GetUpgradeTask(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	task, err := h.otaService.GetUpgradeTask(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.NotFound("任务不存在"))
		return
	}
	response.Success(c, task)
}

// GetUpgradeTaskDevices 获取任务下设备升级详情
func (h *OTAHandler) GetUpgradeTaskDevices(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	devices, err := h.otaService.GetUpgradeTaskDevices(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备升级详情失败", err))
		return
	}
	response.Success(c, gin.H{"items": devices})
}

// ExecuteUpgradeTask 手动执行任务
func (h *OTAHandler) ExecuteUpgradeTask(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.ExecuteTask(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("执行任务失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "任务已执行", nil)
}

// CancelUpgradeTask 取消任务
func (h *OTAHandler) CancelUpgradeTask(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.CancelTask(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("取消任务失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "任务已取消", nil)
}

// RetryUpgradeTask 重试失败设备
func (h *OTAHandler) RetryUpgradeTask(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.RetryTaskFailed(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("重试失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "已重试", nil)
}

// DeleteUpgradeTask 删除任务
func (h *OTAHandler) DeleteUpgradeTask(c *gin.Context) {
	id := parseID(c.Param("id"))
	if id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return
	}
	if err := h.otaService.DeleteUpgradeTask(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("删除失败: "+err.Error(), err))
		return
	}
	response.SuccessWithMessage(c, "任务已删除", nil)
}

// GetTaskStats 获取任务统计
func (h *OTAHandler) GetTaskStats(c *gin.Context) {
	pending, running, todayCompleted, failed, err := h.otaService.GetTaskStats(c.Request.Context())
	if err != nil {
		response.HandleError(c, apperr.Internal("查询统计失败", err))
		return
	}
	response.Success(c, gin.H{
		"pending":         pending,
		"running":         running,
		"today_completed": todayCompleted,
		"failed":          failed,
	})
}

// ReportLocalOTAResult 本地OTA完成后，App上报新版本号
func (h *OTAHandler) ReportLocalOTAResult(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}

	var req struct {
		Status      string `json:"status" binding:"required"`      // "success" or "failed"
		TargetChip  string `json:"target_chip" binding:"required"` // "esp", "arm", "dsp", "bms"
		NewVersion  string `json:"new_version"`
		MainVersion string `json:"main_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}

	validChips := map[string]bool{"arm": true, "esp": true, "dsp": true, "bms": true}
	if !validChips[req.TargetChip] {
		response.HandleError(c, apperr.BadRequest("invalid target_chip"))
		return
	}

	ctx := c.Request.Context()

	if req.Status == "success" && req.NewVersion != "" {
		userID := c.GetInt64("user_id")
		taskID, err := h.otaService.ReportLocalOTAResult(ctx, userID, sn, req.TargetChip, req.NewVersion, req.MainVersion)
		if err != nil {
			log.Printf("[ReportLocalOTAResult] error: sn=%s, chip=%s, err=%v", sn, req.TargetChip, err)
			// 不返回错误给客户端，避免阻断 App 流程
			response.Success(c, gin.H{"status": "ok"})
			return
		}
		response.Success(c, gin.H{"status": "ok", "task_id": taskID})
		return
	}

	response.Success(c, gin.H{"status": "ok"})
}

// AppListUpgradePackages APP端查询升级包列表（过滤敏感字段）
func (h *OTAHandler) AppListUpgradePackages(c *gin.Context) {
	modelFilter := c.Query("model")
	if modelFilter == "" {
		response.HandleError(c, apperr.BadRequest("model is required"))
		return
	}

	list, err := h.otaService.ListUpgradePackages(c.Request.Context(), modelFilter)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级包列表失败", err))
		return
	}

	// 过滤敏感字段，只返回 App 端需要的信息
	type safeItem struct {
		TargetChip      string `json:"target_chip"`
		FirmwareVersion string `json:"firmware_version"`
	}
	type safePackage struct {
		ID          int64      `json:"id"`
		MainVersion string     `json:"main_version"`
		Model       string     `json:"model"`
		Changelog   string     `json:"changelog"`
		CreatedAt   string     `json:"created_at"`
		Items       []safeItem `json:"items"`
	}

	packages := make([]safePackage, 0, len(list))
	for _, pkg := range list {
		items := make([]safeItem, 0, len(pkg.Items))
		for _, item := range pkg.Items {
			items = append(items, safeItem{
				TargetChip:      item.TargetChip,
				FirmwareVersion: item.FirmwareVersion,
			})
		}
		packages = append(packages, safePackage{
			ID:          pkg.ID,
			MainVersion: pkg.MainVersion,
			Model:       pkg.Model,
			Changelog:   pkg.Changelog,
			CreatedAt:   pkg.CreatedAt.Format(time.RFC3339),
			Items:       items,
		})
	}

	response.Success(c, gin.H{"packages": packages})
}

// AppInstallPackage APP端安装指定升级包
func (h *OTAHandler) AppInstallPackage(c *gin.Context) {
	var req struct {
		SN        string `json:"sn" binding:"required"`
		PackageID int64  `json:"package_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}

	userID := c.GetInt64("user_id")

	// 安全校验：确认设备属于当前用户
	owned, err := h.otaService.CheckDeviceOwnership(c.Request.Context(), req.SN, userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备信息失败", err))
		return
	}
	if !owned {
		response.HandleError(c, apperr.Forbidden("设备不属于当前用户"))
		return
	}

	if err := h.otaService.PushPackageUpgrade(c.Request.Context(), &service.PushPackageUpgradeReq{
		PackageID: req.PackageID,
		DeviceSNs: []string{req.SN},
		PushedBy:  userID,
		Immediate: true,
	}); err != nil {
		log.Printf("[AppInstallPackage] error: sn=%s, package_id=%d, err=%v", req.SN, req.PackageID, err)
		response.HandleError(c, apperr.Internal("安装升级包失败: "+err.Error(), err))
		return
	}

	response.SuccessWithMessage(c, "升级包已推送", nil)
}

// GetDevicePackageUpgradeInfo 获取设备在指定升级包下的各芯片升级进度
func (h *OTAHandler) GetDevicePackageUpgradeInfo(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}
	packageID := parseID(c.Param("packageId"))
	if packageID <= 0 {
		response.HandleError(c, apperr.BadRequest("无效的升级包ID"))
		return
	}

	userID := c.GetInt64("user_id")
	owned, err := h.otaService.CheckDeviceOwnership(c.Request.Context(), sn, userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备信息失败", err))
		return
	}
	if !owned {
		response.HandleError(c, apperr.Forbidden("设备不属于当前用户"))
		return
	}

	info, err := h.otaService.GetDevicePackageUpgradeInfo(c.Request.Context(), sn, int64(packageID))
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级进度失败: "+err.Error(), err))
		return
	}
	response.Success(c, info)
}

// ListDeviceUpgradePackages 通过设备SN查询可用的升级包列表
func (h *OTAHandler) ListDeviceUpgradePackages(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}

	userID := c.GetInt64("user_id")
	owned, err := h.otaService.CheckDeviceOwnership(c.Request.Context(), sn, userID)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备信息失败", err))
		return
	}
	if !owned {
		response.HandleError(c, apperr.Forbidden("设备不属于当前用户"))
		return
	}

	// 获取设备信息以确定型号和当前芯片版本
	device, err := h.otaService.GetDeviceBySN(c.Request.Context(), sn)
	if err != nil || device == nil {
		response.HandleError(c, apperr.NotFound("设备不存在"))
		return
	}

	list, err := h.otaService.ListUpgradePackages(c.Request.Context(), device.Model)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询升级包列表失败", err))
		return
	}

	// 获取设备当前各芯片版本用于对比
	chipVersions := device.ChipVersions()

	type chipItem struct {
		TargetChip      string `json:"target_chip"`
		FirmwareVersion string `json:"firmware_version"`
		CurrentVersion  string `json:"current_version"`
	}
	type packageInfo struct {
		ID          int64      `json:"id"`
		MainVersion string     `json:"main_version"`
		Model       string     `json:"model"`
		Changelog   string     `json:"changelog"`
		CreatedAt   string     `json:"created_at"`
		Items       []chipItem `json:"items"`
	}

	packages := make([]packageInfo, 0, len(list))
	for _, pkg := range list {
		items := make([]chipItem, 0, len(pkg.Items))
		for _, item := range pkg.Items {
			items = append(items, chipItem{
				TargetChip:      item.TargetChip,
				FirmwareVersion: item.FirmwareVersion,
				CurrentVersion:  chipVersions[item.TargetChip],
			})
		}
		packages = append(packages, packageInfo{
			ID:          pkg.ID,
			MainVersion: pkg.MainVersion,
			Model:       pkg.Model,
			Changelog:   pkg.Changelog,
			CreatedAt:   pkg.CreatedAt.Format(time.RFC3339),
			Items:       items,
		})
	}

	response.Success(c, gin.H{
		"device_sn":             sn,
		"device_model":          device.Model,
		"current_main_version":  device.MainVersion,
		"packages":              packages,
	})
}

// GetDevicesByFirmware 按固件版本查询正在使用该版本的设备（管理端）
func (h *OTAHandler) GetDevicesByFirmware(c *gin.Context) {
	deviceModel := c.Query("model")
	targetChip := c.Query("target_chip")
	version := c.Query("version")
	if deviceModel == "" || targetChip == "" || version == "" {
		response.HandleError(c, apperr.BadRequest("model, target_chip, version 均为必填参数"))
		return
	}

	validChips := map[string]bool{"arm": true, "esp": true, "dsp": true, "bms": true}
	if !validChips[targetChip] {
		response.HandleError(c, apperr.BadRequest("invalid target_chip"))
		return
	}

	devices, err := h.otaService.GetDevicesByFirmwareVersion(c.Request.Context(), deviceModel, targetChip, version)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备列表失败", err))
		return
	}
	response.Success(c, gin.H{"devices": devices, "total": len(devices)})
}

// GetUpgradePackageDevices 按升级包查询已安装/正在安装该升级包的设备（管理端）
func (h *OTAHandler) GetUpgradePackageDevices(c *gin.Context) {
	packageIDStr := c.Query("package_id")
	if packageIDStr == "" {
		response.HandleError(c, apperr.BadRequest("package_id 必填"))
		return
	}
	packageID := parseID(packageIDStr)
	if packageID <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid package_id"))
		return
	}

	status := c.Query("status")

	devices, err := h.otaService.GetDevicesByUpgradePackage(c.Request.Context(), packageID, status)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询设备列表失败", err))
		return
	}
	response.Success(c, gin.H{"devices": devices, "total": len(devices)})
}

// GetAvailablePackages APP端获取设备可用的已发布升级包列表
func (h *OTAHandler) GetAvailablePackages(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		response.HandleError(c, apperr.BadRequest("设备SN不能为空"))
		return
	}

	userID := c.GetInt64("user_id")
	packages, err := h.otaService.GetAvailablePackagesForDevice(c.Request.Context(), sn, userID)
	if err != nil {
		log.Printf("[GetAvailablePackages] error: sn=%s, err=%v", sn, err)
		response.HandleError(c, apperr.Internal("查询可用升级包失败: "+err.Error(), err))
		return
	}

	// 过滤敏感字段，只返回 App 端需要的信息
	type chipInfo struct {
		TargetChip      string `json:"target_chip"`
		FirmwareVersion string `json:"firmware_version"`
	}
	type availablePackage struct {
		ID            int64      `json:"id"`
		UserVersion   string     `json:"user_version"`
		UserChangelog string     `json:"user_changelog"`
		MainVersion   string     `json:"main_version"` // 新增：供 App 端回退
		IsForce       bool       `json:"is_force"`
		Model         string     `json:"model"`
		Chips        []chipInfo `json:"chips"`
	}

	result := make([]availablePackage, 0, len(packages))
	for _, pkg := range packages {
		chips := make([]chipInfo, 0, len(pkg.Items))
		for _, item := range pkg.Items {
			chips = append(chips, chipInfo{
				TargetChip:      item.TargetChip,
				FirmwareVersion: item.FirmwareVersion,
			})
		}
		result = append(result, availablePackage{
			ID:            pkg.ID,
			UserVersion:   pkg.UserVersion,
			UserChangelog: pkg.UserChangelog,
			MainVersion:   pkg.MainVersion, // 新增
			IsForce:       pkg.IsForce,
			Model:         pkg.Model,
			Chips:        chips,
		})
	}

	response.Success(c, gin.H{"packages": result})
}

// RollbackUpgrade 回退设备到指定升级包版本
func (h *OTAHandler) RollbackUpgrade(c *gin.Context) {
	var req struct {
		SN        string `json:"sn" binding:"required"`
		PackageID int64  `json:"package_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}

	taskID, err := h.otaService.RollbackUpgrade(c.Request.Context(), req.SN, req.PackageID)
	if err != nil {
		log.Printf("[RollbackUpgrade] error: sn=%s, package_id=%d, err=%v", req.SN, req.PackageID, err)
		response.HandleError(c, apperr.Internal("回退升级失败: "+err.Error(), err))
		return
	}
	response.Success(c, gin.H{"task_id": taskID, "message": "回退指令已发送"})
}
