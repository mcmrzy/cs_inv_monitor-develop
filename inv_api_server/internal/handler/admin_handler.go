package handler

import (
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

type AdminHandler struct {
	userRepo    *repository.UserRepository
	permChecker *service.PermChecker
}

func NewAdminHandler(userRepo *repository.UserRepository, permChecker *service.PermChecker) *AdminHandler {
	return &AdminHandler{
		userRepo:    userRepo,
		permChecker: permChecker,
	}
}

func (h *AdminHandler) ListUsers(c *gin.Context) {
	users, err := h.userRepo.ListAll(c.Request.Context())
	if err != nil {
		response.InternalError(c, "查询用户列表失败")
		return
	}
	response.Success(c, users)
}

func (h *AdminHandler) GetUser(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.NotFound(c, "用户不存在")
		return
	}
	user.PasswordHash = ""
	response.Success(c, user)
}

type UpdateUserRoleRequest struct {
	Role int `json:"role" binding:"required"`
}

func (h *AdminHandler) UpdateUserRole(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	var req UpdateUserRoleRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.userRepo.UpdateRole(c.Request.Context(), userID, req.Role); err != nil {
		response.InternalError(c, "更新角色失败")
		return
	}

	go h.permChecker.InvalidateUser(userID)
	response.SuccessWithMessage(c, "角色更新成功", nil)
}

type UpdatePermissionRequest struct {
	Role        int    `json:"role" binding:"required"`
	Resource    string `json:"resource" binding:"required"`
	Action      string `json:"action" binding:"required"`
	IsAllowed   bool   `json:"is_allowed"`
}

func (h *AdminHandler) UpdatePermission(c *gin.Context) {
	var req UpdatePermissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.userRepo.UpsertPermission(c.Request.Context(), req.Role, req.Resource, req.Action, req.IsAllowed); err != nil {
		response.InternalError(c, "更新权限失败")
		return
	}

	go h.permChecker.InvalidateRole(int64(req.Role))
	response.SuccessWithMessage(c, "权限更新成功", nil)
}

func (h *AdminHandler) ListRolePermissions(c *gin.Context) {
	roleParam := c.Query("role")
	if roleParam == "" {
		response.BadRequest(c, "缺少 role 参数")
		return
	}
	role := parseID(roleParam)
	if role <= 0 {
		response.BadRequest(c, "invalid role")
		return
	}

	perms, err := h.userRepo.GetRolePermissions(c.Request.Context(), int64(role))
	if err != nil {
		response.InternalError(c, "查询权限失败")
		return
	}
	response.Success(c, perms)
}

func (h *AdminHandler) ToggleUserStatus(c *gin.Context) {
	userID := parseID(c.Param("id"))
	if userID <= 0 {
		response.BadRequest(c, "invalid user id")
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil || user == nil {
		response.NotFound(c, "用户不存在")
		return
	}

	newStatus := 0
	if user.Status != 1 {
		newStatus = 1
	}

	if err := h.userRepo.UpdateStatus(c.Request.Context(), userID, newStatus); err != nil {
		response.InternalError(c, "更新用户状态失败")
		return
	}
	response.SuccessWithMessage(c, "用户状态已更新", nil)
}

func (h *AdminHandler) ListAllModels(c *gin.Context) {
	db := GetDB()
	if db == nil {
		response.InternalError(c, "database not available")
		return
	}

	rows, err := db.Query(c.Request.Context(), `
		SELECT dm.id, dm.model_code, dm.model_name, dm.manufacturer, dm.category,
		       dm.rated_power_kw, dm.description, dm.is_active, dm.created_at, dm.updated_at,
		       COALESCE((SELECT COUNT(*) FROM devices WHERE model = dm.model_code AND deleted_at IS NULL), 0) AS device_count
		FROM device_models dm ORDER BY dm.id DESC
	`)
	if err != nil {
		response.InternalError(c, "查询型号列表失败")
		return
	}
	defer rows.Close()

	type ModelWithCount struct {
		ID          int64  `json:"id"`
		ModelCode   string `json:"model_code"`
		ModelName   string `json:"model_name"`
		Manufacturer string `json:"manufacturer"`
		Category    string `json:"category"`
		RatedPowerKW float64 `json:"rated_power_kw"`
		Description string `json:"description"`
		IsActive    bool   `json:"is_active"`
		CreatedAt   string `json:"created_at"`
		UpdatedAt   string `json:"updated_at"`
		DeviceCount int    `json:"device_count"`
	}

	var models []ModelWithCount
	for rows.Next() {
		var m ModelWithCount
		if err := rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer,
			&m.Category, &m.RatedPowerKW, &m.Description, &m.IsActive,
			&m.CreatedAt, &m.UpdatedAt, &m.DeviceCount); err != nil {
			continue
		}
		models = append(models, m)
	}
	response.Success(c, models)
}
