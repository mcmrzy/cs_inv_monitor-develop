package handler

import (
	"context"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/logger"
	"inv-api-server/pkg/response"

	"go.uber.org/zap"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

// UserOpLogHandler 用户操作历史聚合查询（App"操作历史"页数据源）。
//
// GET /api/v1/op-logs 按当前用户维度聚合三类操作记录：
//  1. user_operation_logs（登录/设备控制/参数修改等用户操作）
//  2. device_cmd_logs（用户名下设备收到的命令）
//  3. device_upgrades（用户名下设备的 OTA 升级记录）
//
// 三源 UNION ALL 后按时间倒序统一分页返回。
type UserOpLogHandler struct {
	db *pgxpool.Pool
}

func NewUserOpLogHandler(db *pgxpool.Pool) *UserOpLogHandler {
	return &UserOpLogHandler{db: db}
}

// userDeviceScope 用户可见设备子查询（devices.user_id + user_device_rel 关联表），
// 与 repository 层权限过滤模板保持一致。
func userDeviceScope(argIdx int) string {
	return `(SELECT sn FROM devices WHERE user_id = $` + strconv.Itoa(argIdx) + ` AND deleted_at IS NULL
		UNION SELECT device_sn FROM user_device_rel WHERE user_id = $` + strconv.Itoa(argIdx) + `)`
}

func (h *UserOpLogHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isSystemAdmin := middleware.GetIsSystemAdmin(c)
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	// 三源聚合公共片段：统一 source/title/device_sn/result/op_time 五字段。
	// UNION ALL 各分支共享同一参数编号空间：$1=userID、$2=limit、$3=offset。
	operationSrc := `SELECT 'operation' AS source, o.operation_type AS title,
		COALESCE(o.device_sn,'') AS device_sn, o.result,
		o.created_at AS op_time
		FROM user_operation_logs o WHERE o.user_id = $1`
	cmdSrc := `SELECT 'command' AS source, c.cmd AS title,
		c.device_sn, COALESCE(NULLIF(c.status,''),'pending'),
		c.sent_at AS op_time
		FROM device_cmd_logs c`
	otaSrc := `SELECT 'ota' AS source, u.firmware_version AS title,
		u.device_sn, COALESCE(NULLIF(u.status,''),'pending'),
		u.created_at AS op_time
		FROM device_upgrades u`

	// 系统管理员可见全部设备的命令/OTA 记录；普通用户仅限名下设备。
	// 用户操作日志始终为当前用户维度。
	if !isSystemAdmin {
		scope := userDeviceScope(1)
		cmdSrc += ` WHERE c.device_sn IN ` + scope
		otaSrc += ` WHERE u.device_sn IN ` + scope
	}

	unionSQL := `SELECT * FROM (` + operationSrc + `
		UNION ALL ` + cmdSrc + `
		UNION ALL ` + otaSrc + `) t`

	var total int64
	if err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM (`+unionSQL+`) u`, userID).Scan(&total); err != nil {
		logger.Error("count user op logs failed",
			zap.Int64("user_id", userID),
			zap.Error(err))
		response.Error(c, 500, "query operation logs failed")
		return
	}

	rows, err := h.db.Query(ctx, unionSQL+` ORDER BY t.op_time DESC LIMIT $2 OFFSET $3`,
		userID, pageSize, (page-1)*pageSize)
	if err != nil {
		logger.Error("list user op logs failed",
			zap.Int64("user_id", userID),
			zap.Error(err))
		response.Error(c, 500, "query operation logs failed")
		return
	}
	defer rows.Close()

	items, err := scanJSONMaps(rows)
	if err != nil {
		logger.Error("decode user op logs failed",
			zap.Int64("user_id", userID),
			zap.Error(err))
		response.Error(c, 500, "decode operation logs failed")
		return
	}
	response.Page(c, items, total, page, pageSize)
}
