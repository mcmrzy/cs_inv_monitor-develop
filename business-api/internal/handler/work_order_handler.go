package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type WorkOrderHandler struct {
	db         *pgxpool.Pool
	uploadRoot string
}

type workOrderRequest struct {
	Title           string `json:"title"`
	Description     string `json:"description"`
	Status          string `json:"status"`
	Priority        string `json:"priority"`
	DeviceSN        string `json:"device_sn"`
	DeviceSNCamel   string `json:"deviceSn"`
	TemplateType    string `json:"template_type"`
	TemplateCamel   string `json:"templateType"`
	Resolution      string `json:"resolution"`
	AssignedTo      *int64 `json:"assigned_to"`
	AssigneeID      *int64 `json:"assigneeId"`
	ExpectedVersion *int64 `json:"expectedVersion"`
}

func NewWorkOrderHandler(db *pgxpool.Pool) *WorkOrderHandler {
	return &WorkOrderHandler{db: db, uploadRoot: "/data/firmware/work-orders"}
}

const workOrderJSON = `jsonb_build_object(
	'id',w.id::text,'title',w.title,'description',w.description,'status',w.status,'priority',w.priority,
	'deviceSn',COALESCE(w.device_sn,''),'device_sn',COALESCE(w.device_sn,''),
	'creatorId',w.creator_id,'creatorName',COALESCE(c.nickname,c.phone,c.email,''),
	'assigneeId',COALESCE(w.assigned_to,0),'assigneeName',COALESCE(a.nickname,a.phone,a.email,''),
	'templateType',COALESCE(w.template_type,''),'template_type',COALESCE(w.template_type,''),
	'resolution',COALESCE(w.resolution,''),'slaDeadline',w.sla_deadline,'sla_deadline',w.sla_deadline,
	'slaOverdueCount',w.sla_overdue_count,'sla_overdue_count',w.sla_overdue_count,
	'escalatedCount',w.escalated_count,'lockVersion',w.lock_version,'createdAt',w.created_at,'updatedAt',w.updated_at)`

func workOrderDataScope(alias string, role, userArg int) string {
	userParam := "$" + strconv.Itoa(userArg)
	switch role {
	case service.RoleSuperAdmin:
		return userParam + " = " + userParam
	case service.RoleGeneralAgent, service.RoleAgent, service.RoleDealer:
		return "(" + alias + ".creator_id IN (SELECT descendant_id FROM v_user_hierarchy WHERE ancestor_id=" + userParam + ")" +
			" OR " + alias + ".assigned_to IN (SELECT descendant_id FROM v_user_hierarchy WHERE ancestor_id=" + userParam + "))"
	case service.RoleInstaller:
		return "(" + alias + ".creator_id=" + userParam + " OR " + alias + ".assigned_to=" + userParam + ")"
	case service.RoleEndUser:
		return alias + ".creator_id=" + userParam
	default:
		return "FALSE"
	}
}

func (h *WorkOrderHandler) List(c *gin.Context) {
	page := positiveInt(c.DefaultQuery("page", "1"), 1)
	pageSize := getPageSize(c, 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	status, priority := c.Query("status"), c.Query("priority")
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	filter := workOrderDataScope("w", role, 1) + ` AND ($2='' OR w.status=$2) AND ($3='' OR w.priority=$3)`
	var total int64
	if err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM work_orders w WHERE `+filter, userID, status, priority).Scan(&total); err != nil {
		response.Error(c, 500, "list work orders failed")
		return
	}
	rows, err := h.db.Query(ctx, `SELECT `+workOrderJSON+`
		FROM work_orders w LEFT JOIN users c ON c.id=w.creator_id LEFT JOIN users a ON a.id=w.assigned_to
		WHERE `+filter+` ORDER BY w.created_at DESC LIMIT $4 OFFSET $5`,
		userID, status, priority, pageSize, (page-1)*pageSize)
	if err != nil {
		response.Error(c, 500, "list work orders failed")
		return
	}
	defer rows.Close()
	items, err := scanJSONMaps(rows)
	if err != nil {
		response.Error(c, 500, "decode work orders failed")
		return
	}
	response.Page(c, items, total, page, pageSize)
}

func (h *WorkOrderHandler) GetByID(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		response.Error(c, 400, "invalid order id")
		return
	}
	var raw []byte
	err := h.db.QueryRow(c.Request.Context(), `SELECT `+workOrderJSON+` || jsonb_build_object(
		'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('status',e.status,'operator',COALESCE(u.nickname,u.phone,u.email,''),'timestamp',e.created_at,'remark',e.remark) ORDER BY e.created_at) FROM work_order_events e LEFT JOIN users u ON u.id=e.operator_id WHERE e.work_order_id=w.id),'[]'::jsonb),
		'attachments',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',x.file_name,'url',x.file_url,'type',x.mime_type,'uploadedAt',x.created_at) ORDER BY x.created_at) FROM work_order_attachments x WHERE x.work_order_id=w.id),'[]'::jsonb))
		FROM work_orders w LEFT JOIN users c ON c.id=w.creator_id LEFT JOIN users a ON a.id=w.assigned_to
		WHERE w.id::text=$1 AND `+workOrderDataScope("w", middleware.GetRole(c), 2), id, middleware.GetUserID(c)).Scan(&raw)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "work order not found")
		return
	}
	if err != nil {
		response.Error(c, 500, "get work order failed")
		return
	}
	var item map[string]interface{}
	if err := json.Unmarshal(raw, &item); err != nil {
		response.Error(c, 500, "decode work order failed")
		return
	}
	response.Success(c, item)
}

func (h *WorkOrderHandler) GetStatistics(c *gin.Context) {
	userID := middleware.GetUserID(c)
	role := middleware.GetRole(c)
	var open, inProgress, resolved, closed int64
	err := h.db.QueryRow(c.Request.Context(), `SELECT
		COUNT(*) FILTER(WHERE status='open'),COUNT(*) FILTER(WHERE status='in_progress'),
		COUNT(*) FILTER(WHERE status='resolved'),COUNT(*) FILTER(WHERE status='closed')
		FROM work_orders w WHERE `+workOrderDataScope("w", role, 1), userID).
		Scan(&open, &inProgress, &resolved, &closed)
	if err != nil {
		response.Error(c, 500, "work order statistics failed")
		return
	}
	response.Success(c, gin.H{"total": open + inProgress + resolved + closed, "open": open, "inProgress": inProgress, "resolved": resolved, "closed": closed})
}

func (h *WorkOrderHandler) Create(c *gin.Context) {
	var req workOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Title) == "" || strings.TrimSpace(req.Description) == "" {
		response.Error(c, 400, "title and description are required")
		return
	}
	normalizeWorkOrderRequest(&req)
	if !validPriority(req.Priority) {
		response.Error(c, 400, "invalid priority")
		return
	}
	var id string
	err := h.db.QueryRow(c.Request.Context(), `INSERT INTO work_orders
		(title,description,status,priority,device_sn,creator_id,assigned_to,template_type,sla_deadline,created_at,updated_at)
		VALUES($1,$2,'open',$3,NULLIF($4,''),$5,$6,NULLIF($7,''),NOW()+($8*INTERVAL '1 hour'),NOW(),NOW()) RETURNING id::text`,
		req.Title, req.Description, req.Priority, req.DeviceSN, middleware.GetUserID(c), req.AssignedTo,
		req.TemplateType, slaHours(req.Priority)).Scan(&id)
	if err != nil {
		response.Error(c, 500, "create work order failed")
		return
	}
	_, _ = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_events(work_order_id,status,operator_id,remark) VALUES($1,'open',$2,'created')`, id, middleware.GetUserID(c))
	response.SuccessWithMessage(c, "work order created", gin.H{"id": id})
}

func (h *WorkOrderHandler) Update(c *gin.Context) {
	var req workOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}
	normalizeWorkOrderRequest(&req)
	if req.Status != "" && !validWorkOrderStatus(req.Status) {
		response.Error(c, 400, "invalid work order status")
		return
	}
	if req.Priority != "" && !validPriority(req.Priority) {
		response.Error(c, 400, "invalid priority")
		return
	}
	result, err := h.db.Exec(c.Request.Context(), `UPDATE work_orders SET
		title=COALESCE(NULLIF($2,''),title),description=COALESCE(NULLIF($3,''),description),
		status=COALESCE(NULLIF($4,''),status),priority=COALESCE(NULLIF($5,''),priority),
		device_sn=COALESCE(NULLIF($6,''),device_sn),assigned_to=COALESCE($7,assigned_to),
		resolution=COALESCE(NULLIF($8,''),resolution),updated_at=NOW(),
		resolved_at=CASE WHEN $4='resolved' THEN NOW() ELSE resolved_at END,
		closed_at=CASE WHEN $4='closed' THEN NOW() ELSE closed_at END,
		lock_version=lock_version+1 WHERE id::text=$1 AND `+workOrderDataScope("work_orders", middleware.GetRole(c), 9)+`
		AND ($10::bigint IS NULL OR lock_version=$10)`,
		c.Param("id"), req.Title, req.Description, req.Status, req.Priority, req.DeviceSN, req.AssignedTo, req.Resolution, middleware.GetUserID(c), req.ExpectedVersion)
	if err != nil {
		response.Error(c, 500, "update work order failed")
		return
	}
	if result.RowsAffected() == 0 {
		response.Error(c, 404, "work order not found")
		return
	}
	if req.Status != "" {
		_, _ = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_events(work_order_id,status,operator_id,remark) VALUES($1,$2,$3,'status updated')`, c.Param("id"), req.Status, middleware.GetUserID(c))
	}
	response.SuccessWithMessage(c, "work order updated", gin.H{"id": c.Param("id")})
}

func (h *WorkOrderHandler) Escalate(c *gin.Context) {
	var status string
	err := h.db.QueryRow(c.Request.Context(), `UPDATE work_orders SET
		priority=CASE priority WHEN 'low' THEN 'medium' WHEN 'medium' THEN 'high' ELSE 'urgent' END,
		escalated_count=escalated_count+1,sla_overdue_count=sla_overdue_count+1,updated_at=NOW()
		escalated_at=NOW(),lock_version=lock_version+1
		WHERE id::text=$1 AND status NOT IN('resolved','closed') AND `+workOrderDataScope("work_orders", middleware.GetRole(c), 2)+`
		RETURNING status`, c.Param("id"), middleware.GetUserID(c)).Scan(&status)
	if err == pgx.ErrNoRows {
		response.Error(c, 400, "work order cannot be escalated")
		return
	}
	if err != nil {
		response.Error(c, 500, "escalate work order failed")
		return
	}
	_, _ = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_events(work_order_id,status,operator_id,remark) VALUES($1,$2,$3,'escalated')`, c.Param("id"), status, middleware.GetUserID(c))
	response.SuccessWithMessage(c, "work order escalated", gin.H{"id": c.Param("id")})
}

func (h *WorkOrderHandler) UploadAttachments(c *gin.Context) {
	var allowed bool
	if err := h.db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM work_orders w WHERE w.id::text=$1 AND `+workOrderDataScope("w", middleware.GetRole(c), 2)+`)`, c.Param("id"), middleware.GetUserID(c)).Scan(&allowed); err != nil {
		response.Error(c, 500, "validate work order scope failed")
		return
	}
	if !allowed {
		response.Error(c, 404, "work order not found")
		return
	}
	form, err := c.MultipartForm()
	if err != nil {
		response.Error(c, 400, "invalid multipart request")
		return
	}
	files := form.File["files"]
	if len(files) == 0 || len(files) > 5 {
		response.Error(c, 400, "1 to 5 image files are required")
		return
	}
	if err := os.MkdirAll(h.uploadRoot, 0750); err != nil {
		response.Error(c, 500, "create attachment directory failed")
		return
	}
	urls := make([]string, 0, len(files))
	for index, header := range files {
		file, err := header.Open()
		if err != nil {
			response.Error(c, 400, "open attachment failed")
			return
		}
		content, readErr := io.ReadAll(io.LimitReader(file, 10<<20+1))
		file.Close()
		if readErr != nil || len(content) > 10<<20 {
			response.Error(c, 400, "attachment exceeds 10MB")
			return
		}
		mimeType := http.DetectContentType(content)
		if !strings.HasPrefix(mimeType, "image/") {
			response.Error(c, 400, "only image attachments are allowed")
			return
		}
		ext := strings.ToLower(filepath.Ext(header.Filename))
		if ext == "" || len(ext) > 6 {
			ext = ".img"
		}
		name := fmt.Sprintf("%s-%d-%d%s", c.Param("id"), time.Now().UnixNano(), index, ext)
		if err := os.WriteFile(filepath.Join(h.uploadRoot, name), content, 0640); err != nil {
			response.Error(c, 500, "save attachment failed")
			return
		}
		url := "/firmware/work-orders/" + name
		_, err = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_attachments(work_order_id,file_name,file_url,mime_type,file_size,uploaded_by) VALUES($1,$2,$3,$4,$5,$6)`,
			c.Param("id"), filepath.Base(header.Filename), url, mimeType, len(content), middleware.GetUserID(c))
		if err != nil {
			_ = os.Remove(filepath.Join(h.uploadRoot, name))
			response.Error(c, 500, "save attachment metadata failed")
			return
		}
		urls = append(urls, url)
	}
	response.Success(c, gin.H{"urls": urls})
}

func (h *WorkOrderHandler) DownloadAttachment(c *gin.Context) {
	var fileURL, mimeType, fileName string
	err := h.db.QueryRow(c.Request.Context(), `
		SELECT attachment.file_url, attachment.mime_type, attachment.file_name
		FROM work_order_attachments attachment
		JOIN work_orders w ON w.id=attachment.work_order_id
		WHERE w.id::text=$1 AND attachment.id::text=$2 AND `+workOrderDataScope("w", middleware.GetRole(c), 3),
		c.Param("id"), c.Param("attachmentId"), middleware.GetUserID(c)).Scan(&fileURL, &mimeType, &fileName)
	if err == pgx.ErrNoRows {
		response.Error(c, 404, "attachment not found")
		return
	}
	if err != nil {
		response.Error(c, 500, "load attachment failed")
		return
	}
	storedName := filepath.Base(fileURL)
	if storedName == "." || storedName == "" {
		response.Error(c, 404, "attachment not found")
		return
	}
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filepath.Base(fileName)))
	c.Header("Content-Type", mimeType)
	c.File(filepath.Join(h.uploadRoot, storedName))
}

func (h *WorkOrderHandler) Delete(c *gin.Context) {
	rows, queryErr := h.db.Query(c.Request.Context(), `SELECT file_url FROM work_order_attachments WHERE work_order_id::text=$1`, c.Param("id"))
	attachmentFiles := make([]string, 0)
	if queryErr == nil {
		for rows.Next() {
			var fileURL string
			if rows.Scan(&fileURL) == nil {
				attachmentFiles = append(attachmentFiles, filepath.Base(fileURL))
			}
		}
		rows.Close()
	}
	result, err := h.db.Exec(c.Request.Context(), `DELETE FROM work_orders WHERE id::text=$1 AND `+workOrderDataScope("work_orders", middleware.GetRole(c), 2), c.Param("id"), middleware.GetUserID(c))
	if err != nil {
		response.Error(c, 500, "delete work order failed")
		return
	}
	if result.RowsAffected() == 0 {
		response.Error(c, 404, "work order not found")
		return
	}
	for _, name := range attachmentFiles {
		if name != "." && name != "" {
			_ = os.Remove(filepath.Join(h.uploadRoot, name))
		}
	}
	response.SuccessWithMessage(c, "work order deleted", gin.H{"id": c.Param("id")})
}

func (h *WorkOrderHandler) ListTemplates(c *gin.Context) {
	response.Success(c, []gin.H{
		{"templateId": "repair", "title": "设备故障", "description": "设备运行异常，需要检修", "priority": "high", "defaultFields": []string{"deviceSn", "description"}, "estimatedHours": 4},
		{"templateId": "maintenance", "title": "定期维护", "description": "设备定期保养维护", "priority": "medium", "defaultFields": []string{"deviceSn", "description"}, "estimatedHours": 2},
		{"templateId": "inspection", "title": "设备巡检", "description": "设备运行状态巡检", "priority": "low", "defaultFields": []string{"deviceSn", "description"}, "estimatedHours": 1},
		{"templateId": "installation", "title": "安装调试", "description": "设备安装与参数调试", "priority": "medium", "defaultFields": []string{"deviceSn", "description"}, "estimatedHours": 4},
	})
}

func scanJSONMaps(rows pgx.Rows) ([]map[string]interface{}, error) {
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, err
		}
		var item map[string]interface{}
		if err := json.Unmarshal(raw, &item); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func positiveInt(value string, fallback int) int {
	n, err := strconv.Atoi(value)
	if err != nil || n < 1 {
		return fallback
	}
	return n
}

func normalizeWorkOrderRequest(req *workOrderRequest) {
	if req.DeviceSN == "" {
		req.DeviceSN = req.DeviceSNCamel
	}
	if req.TemplateType == "" {
		req.TemplateType = req.TemplateCamel
	}
	if req.AssignedTo == nil {
		req.AssignedTo = req.AssigneeID
	}
	if req.Priority == "" && req.Status == "" {
		req.Priority = "medium"
	}
}

func validPriority(value string) bool {
	return value == "low" || value == "medium" || value == "high" || value == "urgent"
}

func validWorkOrderStatus(value string) bool {
	return value == "open" || value == "in_progress" || value == "resolved" || value == "closed"
}

func slaHours(priority string) int {
	return map[string]int{"urgent": 4, "high": 8, "medium": 24, "low": 72}[priority]
}
