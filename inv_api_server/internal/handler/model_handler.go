package handler

import (
	"strconv"

	"inv-api-server/internal/middleware"
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
