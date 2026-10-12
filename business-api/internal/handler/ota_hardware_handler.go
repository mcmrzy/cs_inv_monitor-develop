package handler

import (
	"encoding/json"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgconn"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/response"
	"strconv"
)

// Hardware catalog and legacy range backfill are administrative data, never a device identity override.
func (h *OTAHandler) ListHardwareVersions(c *gin.Context) {
	list, err := h.otaService.ListHardwareVersions(c.Request.Context(), c.Query("model"))
	if err != nil {
		response.Error(c, 500, "查询硬件版本失败")
		return
	}
	response.Success(c, list)
}
func (h *OTAHandler) CreateHardwareVersion(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "仅系统管理员可管理硬件版本")
		return
	}
	var v model.DeviceHardwareVersion
	if err := c.ShouldBindJSON(&v); err != nil {
		response.Error(c, 400, "硬件版本参数无效")
		return
	}
	if err := h.otaService.CreateHardwareVersion(c.Request.Context(), &v); err != nil {
		respondHardwareError(c, err)
		return
	}
	detail, _ := json.Marshal(v)
	h.logOTAAuditTyped(c, "hardware_version_create", "hardware_version", v.Model+"/"+v.Version, string(detail))
	response.Success(c, v)
}
func (h *OTAHandler) UpdateFirmwareHardwareVersions(c *gin.Context) {
	if !middleware.GetIsSystemAdmin(c) {
		response.Error(c, 403, "仅系统管理员可补录硬件范围")
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(c, 400, "固件 ID 无效")
		return
	}
	var req struct {
		HardwareVersions []string `json:"hardware_versions"`
	}
	if err = c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "硬件范围参数无效")
		return
	}
	if err = h.otaService.UpdateFirmwareHardwareVersions(c.Request.Context(), id, req.HardwareVersions); err != nil {
		respondHardwareError(c, err)
		return
	}
	versions, _ := model.NormalizeHardwareVersions(req.HardwareVersions)
	detail, _ := json.Marshal(gin.H{"hardware_versions": versions})
	h.logOTAAudit(c, "firmware_hardware_update", strconv.FormatInt(id, 10), string(detail))
	response.Success(c, gin.H{"id": id, "hardware_versions": versions})
}

func respondHardwareError(c *gin.Context, err error) {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		switch pgErr.Code {
		case "23505":
			response.Error(c, 409, "该硬件已存在相同模块及软件版本，或硬件版本已登记")
			return
		case "23503":
			response.Error(c, 400, "请先在对应型号下登记硬件版本")
			return
		}
	}
	if errors.Is(err, model.ErrFirmwareHardwareImmutable) {
		response.Error(c, 409, err.Error())
		return
	}
	response.Error(c, 400, err.Error())
}

func parseHardwareVersionsForm(raw string) ([]string, error) {
	var versions []string
	if err := json.Unmarshal([]byte(raw), &versions); err != nil {
		return nil, model.ErrFirmwareHardwareUnspecified
	}
	return model.NormalizeHardwareVersions(versions)
}

func firmwareUploadAuditDetail(f *model.Firmware) string {
	data, _ := json.Marshal(gin.H{"model": f.Model, "version": f.Version, "target_chip": f.TargetChip, "file_size": f.FileSize, "file_sha256": f.FileSHA256, "hardware_versions": f.HardwareVersions})
	return string(data)
}
