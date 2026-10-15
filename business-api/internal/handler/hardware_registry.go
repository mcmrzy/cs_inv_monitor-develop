package handler

import (
	"github.com/gin-gonic/gin"
	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"
	"strconv"
)

type HardwareRegistryHandler struct {
	service *service.HardwareRegistryService
	scope   otaDeviceScopeChecker
}

func NewHardwareRegistryHandler(s *service.HardwareRegistryService, ota *service.OTAService) *HardwareRegistryHandler {
	return &HardwareRegistryHandler{service: s, scope: ota}
}
func (h *HardwareRegistryHandler) admin(c *gin.Context) bool {
	if !middleware.GetIsSystemAdmin(c) || middleware.GetUserID(c) <= 0 {
		response.Forbidden(c, "system administrator required")
		return false
	}
	return true
}
func (h *HardwareRegistryHandler) view(c *gin.Context, sn string) bool {
	if middleware.GetIsSystemAdmin(c) {
		return true
	}
	if h.scope == nil {
		response.Forbidden(c, "device scope unavailable")
		return false
	}
	allowed, err := h.scope.CheckDevicePermission(c.Request.Context(), middleware.GetActorContext(c), "devices:view", sn)
	if err != nil {
		response.HandleError(c, err)
		return false
	}
	if !allowed {
		response.Forbidden(c, "device access denied")
		return false
	}
	return true
}
func hardwarePathID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		response.HandleError(c, apperr.BadRequest("invalid id"))
		return 0, false
	}
	return id, true
}
func (h *HardwareRegistryHandler) ListBoardTypes(c *gin.Context) {
	v, err := h.service.ListBoardTypes(c.Request.Context(), c.Query("model"), c.Query("target_chip"))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) CreateBoardType(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	var req model.HardwareBoardType
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid board type")
		return
	}
	if err := h.service.CreateBoardType(c.Request.Context(), req); err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, req)
}
func (h *HardwareRegistryHandler) Get(c *gin.Context) {
	sn := c.Param("sn")
	if !h.view(c, sn) {
		return
	}
	v, err := h.service.Get(c.Request.Context(), sn)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) mutate(c *gin.Context, action string) {
	if !h.admin(c) {
		return
	}
	var req struct {
		model.HardwareMutation
		ExpectedRevision *int64 `json:"expected_revision"`
		Frozen           *bool  `json:"frozen"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.ExpectedRevision == nil {
		response.BadRequest(c, "expected_revision and hardware fields required")
		return
	}
	req.HardwareMutation.ExpectedRevision = *req.ExpectedRevision
	if action == "freeze" {
		if req.Frozen == nil {
			response.BadRequest(c, "frozen must be explicit")
			return
		}
		req.HardwareMutation.Frozen = *req.Frozen
	}
	v, err := h.service.Mutate(c.Request.Context(), c.Param("sn"), action, req.HardwareMutation, middleware.GetUserID(c))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) Verify(c *gin.Context)        { h.mutate(c, "verify") }
func (h *HardwareRegistryHandler) Correct(c *gin.Context)       { h.mutate(c, "correction") }
func (h *HardwareRegistryHandler) ServiceChange(c *gin.Context) { h.mutate(c, "service_change") }
func (h *HardwareRegistryHandler) Freeze(c *gin.Context)        { h.mutate(c, "freeze") }
func (h *HardwareRegistryHandler) History(c *gin.Context) {
	sn := c.Param("sn")
	if !h.view(c, sn) {
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	size, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if size < 1 || size > 100 {
		size = 20
	}
	v, total, err := h.service.History(c.Request.Context(), sn, page, size)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Page(c, v, total, page, size)
}
func (h *HardwareRegistryHandler) StageImport(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	var req struct {
		Rows []model.HardwareImportInput `json:"rows"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid import rows")
		return
	}
	v, err := h.service.StageImport(c.Request.Context(), req.Rows, middleware.GetUserID(c))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) GetImport(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	id, ok := hardwarePathID(c)
	if !ok {
		return
	}
	v, err := h.service.ImportBatch(c.Request.Context(), id, middleware.GetUserID(c))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) CommitImport(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	id, ok := hardwarePathID(c)
	if !ok {
		return
	}
	var req model.HardwareImportCommit
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid import selection")
		return
	}
	v, err := h.service.CommitImport(c.Request.Context(), id, middleware.GetUserID(c), req)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) SetFirmwareBoards(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	id, ok := hardwarePathID(c)
	if !ok {
		return
	}
	var req struct {
		BoardCodes  []string `json:"board_codes"`
		Reason      string   `json:"reason"`
		EvidenceRef string   `json:"evidence_ref"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid firmware scope")
		return
	}
	if err := h.service.SetFirmwareBoards(c.Request.Context(), id, middleware.GetUserID(c), req.BoardCodes, req.Reason, req.EvidenceRef); err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, gin.H{"firmware_id": id, "board_codes": req.BoardCodes})
}
func (h *HardwareRegistryHandler) CreateCompatibilityWindow(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	var req model.OTACompatibilityWindow
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid compatibility window")
		return
	}
	v, err := h.service.CreateCompatibilityWindow(c.Request.Context(), req, middleware.GetUserID(c))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) ListCompatibilityWindows(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	v, err := h.service.ListCompatibilityWindows(c.Request.Context(), c.Query("sn"))
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, v)
}
func (h *HardwareRegistryHandler) GetFirmwareBoards(c *gin.Context) {
	if !h.admin(c) {
		return
	}
	id, ok := hardwarePathID(c)
	if !ok {
		return
	}
	v, err := h.service.FirmwareBoards(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, err)
		return
	}
	response.Success(c, gin.H{"board_codes": v})
}
