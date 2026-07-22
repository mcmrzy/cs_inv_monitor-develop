package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type ModelHandler struct {
	modelService *service.ModelService
}

func NewModelHandler(modelService *service.ModelService) *ModelHandler {
	return &ModelHandler{modelService: modelService}
}

func (h *ModelHandler) ListModels(c *gin.Context) {
	models, err := h.modelService.ListModels(c.Request.Context())
	if err != nil {
		response.HandleError(c, apperr.Internal("查询型号列表失败", err))
		return
	}
	response.Success(c, models)
}

func (h *ModelHandler) GetModel(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	model, err := h.modelService.GetModel(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询型号失败", err))
		return
	}
	if model == nil {
		response.HandleError(c, apperr.NotFound("型号不存在"))
		return
	}

	response.Success(c, model)
}

func (h *ModelHandler) ListFieldCatalog(c *gin.Context) {
	items, err := h.modelService.ListFieldCatalog(c.Request.Context())
	if err != nil {
		response.HandleError(c, apperr.Internal("查询标准字段目录失败", err))
		return
	}
	response.Success(c, items)
}

func (h *ModelHandler) GetFieldCapabilities(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}
	items, err := h.modelService.ListFieldCapabilities(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询型号字段能力失败", err))
		return
	}
	response.Success(c, items)
}

func (h *ModelHandler) GetModelCommandsV2(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}
	items, err := h.modelService.ListModelCommandsV2(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询型号控制能力失败", err))
		return
	}
	response.Success(c, items)
}

func (h *ModelHandler) GetProtocolSchema(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}
	item, err := h.modelService.GetProtocolSchema(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询协议版本失败", err))
		return
	}
	response.Success(c, item)
}

func (h *ModelHandler) UpdateFieldCapability(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}
	modelID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || c.Param("fieldKey") == "" {
		response.HandleError(c, apperr.BadRequest("invalid model or field"))
		return
	}
	var req repository.FieldCapabilityUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if err := h.modelService.UpdateFieldCapability(c.Request.Context(), modelID, c.Param("fieldKey"), req); err != nil {
		response.HandleError(c, apperr.Internal("update field capability failed", err))
		return
	}
	response.Success(c, nil)
}

func (h *ModelHandler) UpdateCommandCapability(c *gin.Context) {
	if middleware.GetRole(c) > 1 {
		response.HandleError(c, apperr.Forbidden("admin only"))
		return
	}
	modelID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || c.Param("commandCode") == "" {
		response.HandleError(c, apperr.BadRequest("invalid model or command"))
		return
	}
	var req repository.CommandCapabilityUpdate
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if req.TimeoutSeconds != nil && (*req.TimeoutSeconds < 1 || *req.TimeoutSeconds > 3600) {
		response.HandleError(c, apperr.BadRequest("timeout_seconds must be between 1 and 3600"))
		return
	}
	if err := h.modelService.UpdateCommandCapability(c.Request.Context(), modelID, c.Param("commandCode"), req); err != nil {
		response.HandleError(c, apperr.Internal("update command capability failed", err))
		return
	}
	response.Success(c, nil)
}

func (h *ModelHandler) UpsertFieldCatalog(c *gin.Context) {
	var req repository.FieldCatalogInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid field catalog request: "+err.Error()))
		return
	}
	if req.FieldKey == "" {
		req.FieldKey = c.Param("fieldKey")
	}
	if req.FieldKey == "" || req.FieldType == "" || req.Category == "" {
		response.HandleError(c, apperr.BadRequest("field_key, field_type and category are required"))
		return
	}
	if err := h.modelService.UpsertFieldCatalog(c.Request.Context(), req, middleware.GetUserID(c)); err != nil {
		response.HandleError(c, apperr.Internal("save field catalog failed", err))
		return
	}
	response.Success(c, nil)
}

func (h *ModelHandler) BatchUpdateFieldCapabilities(c *gin.Context) {
	modelID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	var req struct {
		Fields []repository.FieldCapabilityPatch `json:"fields" binding:"required"`
	}
	if err = c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request: "+err.Error()))
		return
	}
	if err = h.modelService.BatchUpdateFieldCapabilities(c.Request.Context(), modelID, middleware.GetUserID(c), req.Fields); err != nil {
		response.HandleError(c, apperr.Internal("batch update capabilities failed", err))
		return
	}
	response.Success(c, nil)
}

func (h *ModelHandler) UpsertModelCommand(c *gin.Context) {
	modelID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	var req repository.ModelCommandInput
	if err = c.ShouldBindJSON(&req); err != nil || req.CommandCode == "" {
		response.HandleError(c, apperr.BadRequest("command_code is required"))
		return
	}
	if err = h.modelService.UpsertModelCommand(c.Request.Context(), modelID, middleware.GetUserID(c), req); err != nil {
		response.HandleError(c, apperr.Internal("save command capability failed", err))
		return
	}
	response.Success(c, nil)
}

func (h *ModelHandler) ListProtocolVersions(c *gin.Context) {
	items, err := h.modelService.ListProtocolVersions(c.Request.Context())
	if err != nil {
		response.HandleError(c, apperr.Internal("list protocol versions failed", err))
		return
	}
	response.Success(c, items)
}
func (h *ModelHandler) CreateProtocolVersion(c *gin.Context) {
	var req repository.ProtocolVersionInput
	if err := c.ShouldBindJSON(&req); err != nil || req.ProtocolCode == "" || req.Version < 1 || req.SchemaHash == "" || len(req.Fields) == 0 {
		response.HandleError(c, apperr.BadRequest("protocol_code, version, schema_hash and fields are required"))
		return
	}
	id, err := h.modelService.CreateProtocolVersion(c.Request.Context(), middleware.GetUserID(c), req)
	if err != nil {
		response.HandleError(c, apperr.Internal("create protocol version failed", err))
		return
	}
	response.Success(c, gin.H{"id": id})
}
func (h *ModelHandler) ReleaseProtocolVersion(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("protocolId"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid protocol id"))
		return
	}
	if err = h.modelService.ReleaseProtocolVersion(c.Request.Context(), id, middleware.GetUserID(c)); err != nil {
		response.HandleError(c, apperr.Internal("release protocol failed", err))
		return
	}
	response.Success(c, nil)
}
func (h *ModelHandler) BindProtocolVersion(c *gin.Context) {
	modelID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	var req struct {
		ProtocolID int64 `json:"protocol_id" binding:"required"`
	}
	if err != nil || c.ShouldBindJSON(&req) != nil {
		response.HandleError(c, apperr.BadRequest("model id and protocol_id are required"))
		return
	}
	if err = h.modelService.BindProtocolVersion(c.Request.Context(), modelID, req.ProtocolID, middleware.GetUserID(c)); err != nil {
		response.HandleError(c, apperr.Internal("bind protocol failed", err))
		return
	}
	response.Success(c, nil)
}
func (h *ModelHandler) GetMigrationReport(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	item, err := h.modelService.GetMigrationReport(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("get migration report failed", err))
		return
	}
	response.Success(c, item)
}
func (h *ModelHandler) ValidateRegistry(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	issues, err := h.modelService.ValidateModelRegistry(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("validate model failed", err))
		return
	}
	response.Success(c, gin.H{"valid": len(issues) == 0, "issues": issues})
}
func (h *ModelHandler) ActivateRegistry(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	if err = h.modelService.ActivateModel(c.Request.Context(), id, middleware.GetUserID(c)); err != nil {
		response.HandleError(c, apperr.BadRequest(err.Error()))
		return
	}
	response.Success(c, nil)
}
func (h *ModelHandler) GetDataPreview(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid model id"))
		return
	}
	item, err := h.modelService.GetModelDataPreview(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("get model preview failed", err))
		return
	}
	response.Success(c, item)
}

func (h *ModelHandler) CreateModel(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	var req service.CreateModelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	model, err := h.modelService.CreateModel(c.Request.Context(), &req)
	if err != nil {
		response.HandleError(c, apperr.Internal("创建型号失败: "+err.Error(), err))
		return
	}

	response.Success(c, model)
}

func (h *ModelHandler) UpdateModel(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	var req service.UpdateModelRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	if err := h.modelService.UpdateModel(c.Request.Context(), id, &req); err != nil {
		response.HandleError(c, apperr.Internal("更新型号失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) DeleteModel(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	if err := h.modelService.DeleteModel(c.Request.Context(), id); err != nil {
		response.HandleError(c, apperr.Internal("删除型号失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) GetModelFields(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	fields, err := h.modelService.GetModelFields(c.Request.Context(), id)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询字段失败", err))
		return
	}

	response.Success(c, fields)
}

func (h *ModelHandler) CreateField(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	modelIDStr := c.Param("id")
	modelID, err := strconv.ParseInt(modelIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	var req service.CreateFieldRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	field, err := h.modelService.CreateField(c.Request.Context(), modelID, &req)
	if err != nil {
		response.HandleError(c, apperr.Internal("创建字段失败: "+err.Error(), err))
		return
	}

	response.Success(c, field)
}

func (h *ModelHandler) UpdateField(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	fieldIDStr := c.Param("fieldId")
	fieldID, err := strconv.ParseInt(fieldIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的字段ID"))
		return
	}

	var req service.UpdateFieldRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	if err := h.modelService.UpdateField(c.Request.Context(), fieldID, &req); err != nil {
		response.HandleError(c, apperr.Internal("更新字段失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) DeleteField(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	fieldIDStr := c.Param("fieldId")
	fieldID, err := strconv.ParseInt(fieldIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的字段ID"))
		return
	}

	if err := h.modelService.DeleteField(c.Request.Context(), fieldID); err != nil {
		response.HandleError(c, apperr.Internal("删除字段失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) BatchUpdateFields(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	modelIDStr := c.Param("id")
	modelID, err := strconv.ParseInt(modelIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	var req service.BatchUpdateFieldsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	if err := h.modelService.BatchUpdateFields(c.Request.Context(), modelID, &req); err != nil {
		response.HandleError(c, apperr.Internal("批量更新字段失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) GetFieldsByModelCode(c *gin.Context) {
	code := c.Param("code")
	if code == "" {
		response.HandleError(c, apperr.BadRequest("型号编码不能为空"))
		return
	}

	fields, err := h.modelService.GetFieldsByModelCode(c.Request.Context(), code)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询字段失败: "+err.Error(), err))
		return
	}

	response.Success(c, fields)
}

// ==================== Protocol CRUD ====================

func (h *ModelHandler) GetProtocols(c *gin.Context) {
	modelIDStr := c.Param("id")
	modelID, err := strconv.ParseInt(modelIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	protocols, err := h.modelService.GetProtocols(c.Request.Context(), modelID)
	if err != nil {
		response.HandleError(c, apperr.Internal("查询协议配置失败", err))
		return
	}

	response.Success(c, protocols)
}

func (h *ModelHandler) CreateProtocol(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	modelIDStr := c.Param("id")
	modelID, err := strconv.ParseInt(modelIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的型号ID"))
		return
	}

	var req service.CreateProtocolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	protocol, err := h.modelService.CreateProtocol(c.Request.Context(), modelID, &req)
	if err != nil {
		response.HandleError(c, apperr.Internal("创建协议配置失败: "+err.Error(), err))
		return
	}

	response.Success(c, protocol)
}

func (h *ModelHandler) UpdateProtocol(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	protocolIDStr := c.Param("protocolId")
	protocolID, err := strconv.ParseInt(protocolIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的协议ID"))
		return
	}

	var req service.UpdateProtocolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("参数错误: "+err.Error()))
		return
	}

	if err := h.modelService.UpdateProtocol(c.Request.Context(), protocolID, &req); err != nil {
		response.HandleError(c, apperr.Internal("更新协议配置失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}

func (h *ModelHandler) DeleteProtocol(c *gin.Context) {
	role := middleware.GetRole(c)
	if role > 1 {
		response.HandleError(c, apperr.Forbidden("仅管理员可操作"))
		return
	}

	protocolIDStr := c.Param("protocolId")
	protocolID, err := strconv.ParseInt(protocolIDStr, 10, 64)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("无效的协议ID"))
		return
	}

	if err := h.modelService.DeleteProtocol(c.Request.Context(), protocolID); err != nil {
		response.HandleError(c, apperr.Internal("删除协议配置失败: "+err.Error(), err))
		return
	}

	response.Success(c, nil)
}
