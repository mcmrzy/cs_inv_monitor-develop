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
	"inv-api-server/pkg/apperr"
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
	Title         string `json:"title"`
	Description   string `json:"description"`
	Status        string `json:"status"`
	Priority      string `json:"priority"`
	DeviceSN      string `json:"device_sn"`
	DeviceSNCamel string `json:"deviceSn"`
	TemplateType  string `json:"template_type"`
	TemplateCamel string `json:"templateType"`
	Resolution    string `json:"resolution"`
	AssignedTo    *int64 `json:"assigned_to"`
	AssigneeID    *int64 `json:"assigneeId"`
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
	'escalatedCount',w.escalated_count,'createdAt',w.created_at,'updatedAt',w.updated_at)`

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
	isAdmin := middleware.GetRole(c) == 0
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	filter := `($1 OR w.creator_id=$2 OR w.assigned_to=$2) AND ($3='' OR w.status=$3) AND ($4='' OR w.priority=$4)`
	var total int64
	if err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM work_orders w WHERE `+filter, isAdmin, userID, status, priority).Scan(&total); err != nil {
		response.HandleError(c, apperr.Internal("list work orders failed", err))
		return
	}
	rows, err := h.db.Query(ctx, `SELECT `+workOrderJSON+`
		FROM work_orders w LEFT JOIN users c ON c.id=w.creator_id LEFT JOIN users a ON a.id=w.assigned_to
		WHERE `+filter+` ORDER BY w.created_at DESC LIMIT $5 OFFSET $6`,
		isAdmin, userID, status, priority, pageSize, (page-1)*pageSize)
	if err != nil {
		response.HandleError(c, apperr.Internal("list work orders failed", err))
		return
	}
	defer rows.Close()
	items, err := scanJSONMaps(rows)
	if err != nil {
		response.HandleError(c, apperr.Internal("decode work orders failed", err))
		return
	}
	response.Page(c, items, total, page, pageSize)
}

func (h *WorkOrderHandler) GetByID(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		response.HandleError(c, apperr.BadRequest("invalid order id"))
		return
	}
	var raw []byte
	err := h.db.QueryRow(c.Request.Context(), `SELECT `+workOrderJSON+` || jsonb_build_object(
		'timeline',COALESCE((SELECT jsonb_agg(jsonb_build_object('status',e.status,'operator',COALESCE(u.nickname,u.phone,u.email,''),'timestamp',e.created_at,'remark',e.remark) ORDER BY e.created_at) FROM work_order_events e LEFT JOIN users u ON u.id=e.operator_id WHERE e.work_order_id=w.id),'[]'::jsonb),
		'attachments',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',x.file_name,'url',x.file_url,'type',x.mime_type,'uploadedAt',x.created_at) ORDER BY x.created_at) FROM work_order_attachments x WHERE x.work_order_id=w.id),'[]'::jsonb))
		FROM work_orders w LEFT JOIN users c ON c.id=w.creator_id LEFT JOIN users a ON a.id=w.assigned_to WHERE w.id::text=$1`, id).Scan(&raw)
	if err == pgx.ErrNoRows {
		response.HandleError(c, apperr.NotFound("work order not found"))
		return
	}
	if err != nil {
		response.HandleError(c, apperr.Internal("get work order failed", err))
		return
	}
	var item map[string]interface{}
	if err := json.Unmarshal(raw, &item); err != nil {
		response.HandleError(c, apperr.Internal("decode work order failed", err))
		return
	}
	response.Success(c, item)
}

func (h *WorkOrderHandler) GetStatistics(c *gin.Context) {
	userID := middleware.GetUserID(c)
	isAdmin := middleware.GetRole(c) == 0
	var open, inProgress, resolved, closed int64
	err := h.db.QueryRow(c.Request.Context(), `SELECT
		COUNT(*) FILTER(WHERE status='open'),COUNT(*) FILTER(WHERE status='in_progress'),
		COUNT(*) FILTER(WHERE status='resolved'),COUNT(*) FILTER(WHERE status='closed')
		FROM work_orders WHERE $1 OR creator_id=$2 OR assigned_to=$2`, isAdmin, userID).
		Scan(&open, &inProgress, &resolved, &closed)
	if err != nil {
		response.HandleError(c, apperr.Internal("work order statistics failed", err))
		return
	}
	response.Success(c, gin.H{"total": open + inProgress + resolved + closed, "open": open, "inProgress": inProgress, "resolved": resolved, "closed": closed})
}

func (h *WorkOrderHandler) Create(c *gin.Context) {
	var req workOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Title) == "" || strings.TrimSpace(req.Description) == "" {
		response.HandleError(c, apperr.BadRequest("title and description are required"))
		return
	}
	normalizeWorkOrderRequest(&req)
	if !validPriority(req.Priority) {
		response.HandleError(c, apperr.BadRequest("invalid priority"))
		return
	}
	var id string
	err := h.db.QueryRow(c.Request.Context(), `INSERT INTO work_orders
		(title,description,status,priority,device_sn,creator_id,assigned_to,template_type,sla_deadline,created_at,updated_at)
		VALUES($1,$2,'open',$3,NULLIF($4,''),$5,$6,NULLIF($7,''),NOW()+($8*INTERVAL '1 hour'),NOW(),NOW()) RETURNING id::text`,
		req.Title, req.Description, req.Priority, req.DeviceSN, middleware.GetUserID(c), req.AssignedTo,
		req.TemplateType, slaHours(req.Priority)).Scan(&id)
	if err != nil {
		response.HandleError(c, apperr.Internal("create work order failed", err))
		return
	}
	_, _ = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_events(work_order_id,status,operator_id,remark) VALUES($1,'open',$2,'created')`, id, middleware.GetUserID(c))
	response.SuccessWithMessage(c, "work order created", gin.H{"id": id})
}

func (h *WorkOrderHandler) Update(c *gin.Context) {
	var req workOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.HandleError(c, apperr.BadRequest("invalid request"))
		return
	}
	normalizeWorkOrderRequest(&req)
	if req.Status != "" && !validWorkOrderStatus(req.Status) {
		response.HandleError(c, apperr.BadRequest("invalid work order status"))
		return
	}
	if req.Priority != "" && !validPriority(req.Priority) {
		response.HandleError(c, apperr.BadRequest("invalid priority"))
		return
	}
	result, err := h.db.Exec(c.Request.Context(), `UPDATE work_orders SET
		title=COALESCE(NULLIF($2,''),title),description=COALESCE(NULLIF($3,''),description),
		status=COALESCE(NULLIF($4,''),status),priority=COALESCE(NULLIF($5,''),priority),
		device_sn=COALESCE(NULLIF($6,''),device_sn),assigned_to=COALESCE($7,assigned_to),
		resolution=COALESCE(NULLIF($8,''),resolution),updated_at=NOW(),
		resolved_at=CASE WHEN $4='resolved' THEN NOW() ELSE resolved_at END,
		closed_at=CASE WHEN $4='closed' THEN NOW() ELSE closed_at END WHERE id::text=$1`,
		c.Param("id"), req.Title, req.Description, req.Status, req.Priority, req.DeviceSN, req.AssignedTo, req.Resolution)
	if err != nil {
		response.HandleError(c, apperr.Internal("update work order failed", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.NotFound("work order not found"))
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
		WHERE id::text=$1 AND status NOT IN('resolved','closed') RETURNING status`, c.Param("id")).Scan(&status)
	if err == pgx.ErrNoRows {
		response.HandleError(c, apperr.BadRequest("work order cannot be escalated"))
		return
	}
	if err != nil {
		response.HandleError(c, apperr.Internal("escalate work order failed", err))
		return
	}
	_, _ = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_events(work_order_id,status,operator_id,remark) VALUES($1,$2,$3,'escalated')`, c.Param("id"), status, middleware.GetUserID(c))
	response.SuccessWithMessage(c, "work order escalated", gin.H{"id": c.Param("id")})
}

func (h *WorkOrderHandler) UploadAttachments(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid multipart request"))
		return
	}
	files := form.File["files"]
	if len(files) == 0 || len(files) > 5 {
		response.HandleError(c, apperr.BadRequest("1 to 5 image files are required"))
		return
	}
	if err := os.MkdirAll(h.uploadRoot, 0750); err != nil {
		response.HandleError(c, apperr.Internal("create attachment directory failed", err))
		return
	}
	urls := make([]string, 0, len(files))
	for index, header := range files {
		file, err := header.Open()
		if err != nil {
			response.HandleError(c, apperr.BadRequest("open attachment failed"))
			return
		}
		content, readErr := io.ReadAll(io.LimitReader(file, 10<<20+1))
		file.Close()
		if readErr != nil || len(content) > 10<<20 {
			response.HandleError(c, apperr.BadRequest("attachment exceeds 10MB"))
			return
		}
		mimeType := http.DetectContentType(content)
		if !strings.HasPrefix(mimeType, "image/") {
			response.HandleError(c, apperr.BadRequest("only image attachments are allowed"))
			return
		}
		ext := strings.ToLower(filepath.Ext(header.Filename))
		if ext == "" || len(ext) > 6 {
			ext = ".img"
		}
		name := fmt.Sprintf("%s-%d-%d%s", c.Param("id"), time.Now().UnixNano(), index, ext)
		if err := os.WriteFile(filepath.Join(h.uploadRoot, name), content, 0640); err != nil {
			response.HandleError(c, apperr.Internal("save attachment failed", err))
			return
		}
		url := "/firmware/work-orders/" + name
		_, err = h.db.Exec(c.Request.Context(), `INSERT INTO work_order_attachments(work_order_id,file_name,file_url,mime_type,file_size,uploaded_by) VALUES($1,$2,$3,$4,$5,$6)`,
			c.Param("id"), filepath.Base(header.Filename), url, mimeType, len(content), middleware.GetUserID(c))
		if err != nil {
			_ = os.Remove(filepath.Join(h.uploadRoot, name))
			response.HandleError(c, apperr.Internal("save attachment metadata failed", err))
			return
		}
		urls = append(urls, url)
	}
	response.Success(c, gin.H{"urls": urls})
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
	result, err := h.db.Exec(c.Request.Context(), `DELETE FROM work_orders WHERE id::text=$1`, c.Param("id"))
	if err != nil {
		response.HandleError(c, apperr.Internal("delete work order failed", err))
		return
	}
	if result.RowsAffected() == 0 {
		response.HandleError(c, apperr.NotFound("work order not found"))
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
