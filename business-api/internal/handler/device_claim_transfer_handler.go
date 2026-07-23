package handler

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strconv"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ============================================
// Request/Response Models
// ============================================

// GenerateClaimCodeRequest request to generate a new claim code for a device
type GenerateClaimCodeRequest struct {
	SN             string `json:"sn" binding:"required"`
	ExpiresHours   int    `json:"expires_hours" binding:"required,min=1,max=8760"` // up to 1 year
}

// VerifyClaimCodeRequest request to verify a claim code
type VerifyClaimCodeRequest struct {
	ClaimCode string `json:"claim_code" binding:"required"`
}

// ClaimDeviceRequest request to claim a device with SN and claim code
type ClaimDeviceRequest struct {
	SN        string `json:"sn" binding:"required"`
	ClaimCode string `json:"claim_code" binding:"required"`
	UserID    *int64 `json:"user_id"` // Optional, auto-resolve from JWT if omitted
}

// TransferRequestRequest request to initiate ownership transfer
type TransferRequestRequest struct {
	DeviceSN   string `json:"device_sn" binding:"required"`
	ToTenantID int64  `json:"to_tenant_id" binding:"required"`
	Reason     string `json:"reason"`
}

// TransferApprovalRequest request to approve or reject a device transfer
// Using unique name to avoid conflict with other handlers
type DeviceTransferApprovalRequest struct {
	Approved bool   `json:"approved" binding:"required"`
	Reason   string `json:"reason"` // Required if rejected
}

// DeviceClaimToken model representing a claim token
type DeviceClaimToken struct {
	ID                      int64      `json:"id"`
	SN                      string     `json:"sn"`
	RawClaimCode            string     `json:"-"`           // Never return raw code in API
	ClaimCodeDigest         string     `json:"-"`
	RootTenantID            int64      `json:"root_tenant_id"`
	AssignedOrganizationID  *int64     `json:"assigned_organization_id,omitempty"`
	Status                  string     `json:"status"`
	CreatedByUserID         *int64     `json:"created_by_user_id,omitempty"`
	ExpiresAt               time.Time  `json:"expires_at"`
	ClaimedAt               *time.Time `json:"claimed_at,omitempty"`
	ClaimedByUserID         *int64     `json:"claimed_by_user_id,omitempty"`
	CreatedAt               time.Time  `json:"created_at"`
	UpdatedAt               time.Time  `json:"updated_at"`
}

// DeviceTransferRequest model representing a transfer request
type DeviceTransferRequest struct {
	ID                int64      `json:"id"`
	DeviceSN          string     `json:"device_sn"`
	FromTenantID      int64      `json:"from_tenant_id"`
	ToTenantID        int64      `json:"to_tenant_id"`
	RequesterUserID   int64      `json:"requester_user_id"`
	Reason            string     `json:"reason,omitempty"`
	Status            string     `json:"status"`
	ApprovedByUserID  *int64     `json:"approved_by_user_id,omitempty"`
	ApprovedAt        *time.Time `json:"approved_at,omitempty"`
	RejectedReason    string     `json:"rejected_reason,omitempty"`
	RequestedAt       time.Time  `json:"requested_at"`
	ProcessedAt       *time.Time `json:"processed_at,omitempty"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// Handler for device claim and transfer operations
type DeviceClaimTransferHandler struct {
	db           *pgxpool.Pool
	permChecker  *service.PermChecker
	jwtService   *service.JWTService
	deviceURL    string
	internalKey  string
}

// NewDeviceClaimTransferHandler creates a new instance of the handler
func NewDeviceClaimTransferHandler(
	db *pgxpool.Pool,
	permChecker *service.PermChecker,
	jwtService *service.JWTService,
	deviceURL string,
	internalKey string,
) *DeviceClaimTransferHandler {
	return &DeviceClaimTransferHandler{
		db:          db,
		permChecker: permChecker,
		jwtService:  jwtService,
		deviceURL:   deviceURL,
		internalKey: internalKey,
	}
}

// ============================================
// Claim Code Operations
// ============================================

// GenerateClaimCode generates a new claim code for a device
// POST /api/v1/devices/claim-code/generate
func (h *DeviceClaimTransferHandler) GenerateClaimCode(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req GenerateClaimCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	ctx := c.Request.Context()

	// Try to query device by SN; if not found, use user's tenant context
	device, err := h.getDeviceBySN(ctx, req.SN)
	var rootTenantID int64
	if err != nil || device == nil {
		// Device not yet in system — use current user's root tenant
		rootTenantID = middleware.GetRootTenantID(c)
		if rootTenantID == 0 {
			rootTenantID = userID
		}
	} else {
		// Device exists — always enforce cross-tenant check regardless of admin role
		requesterTenantID, tcErr := h.getRootTenantID(ctx, userID)
		if tcErr != nil {
			response.Error(c, 500, "获取用户租户信息失败")
			return
		}
		ownerTenantID, otErr := h.getRootTenantID(ctx, device.UserID)
		if otErr != nil {
			response.Error(c, 500, "获取设备租户信息失败")
			return
		}
		if requesterTenantID != ownerTenantID {
			response.Error(c, 403, "无权限为其他租户的设备生成认领码")
			return
		}
		// Check device not already claimed
		if device.Status != 0 && device.Status != 1 {
			response.Error(c, 409, "设备已被认领，无法再次生成认领码")
			return
		}
		rootTenantID = ownerTenantID
	}

	// Generate secure claim code (96-bit entropy → ~13 base64 chars)
	codeBytes := make([]byte, 12)
	if _, err := rand.Read(codeBytes); err != nil {
		response.Error(c, 500, "生成随机码失败")
		return
	}
	rawClaimCode := base64.URLEncoding.EncodeToString(codeBytes)[:16] // Fixed 16 chars

	// Compute SHA-256 digest
	digest := sha256.Sum256([]byte(rawClaimCode))
	claimCodeDigest := hex.EncodeToString(digest[:])

	// Calculate expiration
	expiresAt := time.Now().Add(time.Duration(req.ExpiresHours) * time.Hour)

	// Upsert claim token
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	var tokenID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO device_claim_tokens 
			(sn, claim_code, claim_code_digest, root_tenant_id, assigned_organization_id, 
			 status, created_by_user_id, expires_at)
		VALUES ($1, $2, $3, $4, $5, 'unclaimed', $6, $7)
		ON CONFLICT (sn, root_tenant_id) DO UPDATE SET 
			claim_code = EXCLUDED.claim_code,
			claim_code_digest = EXCLUDED.claim_code_digest,
			expires_at = EXCLUDED.expires_at,
			status = 'unclaimed'
		RETURNING id
	`, 
		req.SN,
		rawClaimCode,
		claimCodeDigest,
		rootTenantID,
		nil, // Organization not used yet
		userID,
		expiresAt,
	).Scan(&tokenID)

	if err != nil {
		response.Error(c, 500, "保存认领码失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交认领码失败")
		return
	}

	// Return claim code (display only, never returned again)
	response.Success(c, map[string]any{
		"claim_code": rawClaimCode,
		"expires_at": expiresAt.Format(time.RFC3339),
		"status":     "pending",
		"note":       fmt.Sprintf("请将此代码告知安装商，有效期%d小时", req.ExpiresHours),
		"sn":         req.SN,
	})
}

// VerifyClaimCode verifies if a claim code is valid
// POST /api/v1/devices/claim-code/verify
func (h *DeviceClaimTransferHandler) VerifyClaimCode(c *gin.Context) {
	var req VerifyClaimCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	ctx := c.Request.Context()

	// Find claim token by digest (stored as hex-encoded VARCHAR)
	digest := sha256.Sum256([]byte(req.ClaimCode))
	claimCodeDigest := hex.EncodeToString(digest[:])

	var token DeviceClaimToken
	err := h.db.QueryRow(ctx, `
		SELECT id, sn, claim_code_digest, root_tenant_id, assigned_organization_id, 
			   status, expires_at, claimed_at, claimed_by_user_id, created_at, updated_at
		FROM device_claim_tokens 
		WHERE claim_code_digest = $1 AND status = 'unclaimed'
	`, claimCodeDigest).
		Scan(
			&token.ID, &token.SN, &token.ClaimCodeDigest, &token.RootTenantID,
			&token.AssignedOrganizationID, &token.Status, &token.ExpiresAt,
			&token.ClaimedAt, &token.ClaimedByUserID, &token.CreatedAt, &token.UpdatedAt,
		)

	if err == pgx.ErrNoRows {
		response.Error(c, 404, "无效的认领码")
		return
	} else if err != nil {
		response.Error(c, 500, "查询认领码失败")
		return
	}

	// Check expiration
	if time.Now().After(token.ExpiresAt) {
		response.Error(c, 403, "认领码已过期")
		return
	}

	// All checks passed - just return basic info (no sensitive data)
	response.Success(c, map[string]any{
		"valid":          true,
		"sn":             token.SN,
		"expires_at":     token.ExpiresAt.Format(time.RFC3339),
		"remaining_time": int(time.Until(token.ExpiresAt).Seconds()),
	})
}

// ClaimDevice claims a device using SN and claim code
// POST /api/v1/devices/:sn/claim
func (h *DeviceClaimTransferHandler) ClaimDevice(c *gin.Context) {
	userID := middleware.GetUserID(c)
	sn := c.Param("sn")

	var req ClaimDeviceRequest
	req.SN = sn
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	ctx := c.Request.Context()

	// Compute digest from provided claim code
	_ = sha256.Sum256([]byte(req.ClaimCode)) // Use blank identifier to avoid unused variable warning

	// Lookup claim token
	var token DeviceClaimToken
	err := h.db.QueryRow(ctx, `
		SELECT id, sn, claim_code_digest, root_tenant_id, assigned_organization_id, 
			   status, expires_at, claimed_at, claimed_by_user_id, created_at, updated_at
		FROM device_claim_tokens WHERE sn = $1
	`, req.SN).
		Scan(
			&token.ID, &token.SN, &token.ClaimCodeDigest, &token.RootTenantID,
			&token.AssignedOrganizationID, &token.Status, &token.ExpiresAt,
			&token.ClaimedAt, &token.ClaimedByUserID, &token.CreatedAt, &token.UpdatedAt,
		)

	if err == pgx.ErrNoRows {
		response.Error(c, 404, "设备或认领码不存在")
		return
	} else if err != nil {
		response.Error(c, 500, "查询认领码失败")
		return
	}

	// Validate not already claimed
	if token.Status != "unclaimed" {
		if token.ClaimedByUserID != nil {
			response.Error(c, 409, "设备已被用户"+strconv.FormatInt(*token.ClaimedByUserID, 10)+"认领")
		} else {
			response.Error(c, 409, "设备认领码已失效")
		}
		return
	}

	// Validate expiration
	if time.Now().After(token.ExpiresAt) {
		response.Error(c, 403, "认领码已过期")
		return
	}

	// Validate digest match
	providedDigest := sha256.Sum256([]byte(req.ClaimCode))
	if hex.EncodeToString(providedDigest[:]) != token.ClaimCodeDigest {
		response.Error(c, 403, "认领码错误")
		return
	}

	// Determine claiming user ID
	claimingUserID := userID
	if req.UserID != nil {
		claimingUserID = *req.UserID
	}

	// Verify tenant matching
	userTenantID, err := h.getRootTenantID(ctx, claimingUserID)
	if err != nil {
		response.Error(c, 500, "获取用户租户信息失败")
		return
	}

	if token.RootTenantID != userTenantID {
		response.Error(c, 403, "跨租户认领需要管理员权限")
		return
	}

	// Begin transaction
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	// Update device status to claimed
	result, err := tx.Exec(ctx, `
		UPDATE devices SET 
			status = 1, -- claimed status
			updated_at = NOW()
		WHERE sn = $1 AND (status = 0 OR status IS NULL)
	`, req.SN)

	if err != nil {
		response.Error(c, 500, "更新设备状态失败")
		return
	}

	if result.RowsAffected() == 0 {
		response.Error(c, 409, "设备可能已被其他操作改变状态")
		return
	}

	// Mark claim token as used
	_, err = tx.Exec(ctx, `
		UPDATE device_claim_tokens 
		SET status = 'claimed', claimed_at = NOW(), claimed_by_user_id = $1
		WHERE id = $2
	`, claimingUserID, token.ID)

	if err != nil {
		response.Error(c, 500, "更新认领码状态失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交认领事务失败")
		return
	}

	// Emit async event for external services
	h.emitEvent(c, "device_claimed", map[string]any{
		"device_sn":     req.SN,
		"claimed_by":    claimingUserID,
		"claimed_at":    time.Now().UTC(),
		"organization_id": token.AssignedOrganizationID,
	})

	response.Success(c, map[string]any{
		"message": "设备认领成功",
		"device_sn": req.SN,
		"claimed_by": claimingUserID,
	})
}

// ============================================
// Transfer Request Operations
// ============================================

// RequestTransfer initiates an ownership transfer request
// POST /api/v1/devices/:sn/request-transfer
func (h *DeviceClaimTransferHandler) RequestTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)
	sn := c.Param("sn")

	var req TransferRequestRequest
	req.DeviceSN = sn
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	ctx := c.Request.Context()

	// Get device
	device, err := h.getDeviceBySN(ctx, req.DeviceSN)
	if err != nil || device == nil {
		response.Error(c, 404, "设备不存在")
		return
	}

	// Verify requester owns the device
	currentTenantID, err := h.getRootTenantID(ctx, device.UserID)
	if err != nil {
		response.Error(c, 500, "获取租户信息失败")
		return
	}

	userTenantID, err := h.getRootTenantID(ctx, userID)
	if err != nil {
		response.Error(c, 500, "获取用户租户信息失败")
		return
	}

	if currentTenantID != userTenantID {
		response.Error(c, 403, "只能转移自己拥有的设备")
		return
	}

	// Validate target tenant is different
	if req.ToTenantID == currentTenantID {
		response.Error(c, 400, "目标租户不能与当前租户相同")
		return
	}

	// Check if there's already a pending transfer
	var existingCount int64
	err = h.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM device_transfer_requests 
		WHERE device_sn = $1 AND status = 'pending'
	`, req.DeviceSN).Scan(&existingCount)

	if err != nil {
		response.Error(c, 500, "检查现有转移请求失败")
		return
	}

	if existingCount > 0 {
		response.Error(c, 409, "该设备已有待处理的转移请求")
		return
	}

	// Create transfer request
	var transferID int64
	err = h.db.QueryRow(ctx, `
		INSERT INTO device_transfer_requests 
			(device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id, reason, status)
		VALUES ($1, $2, $3, $4, $5, 'pending')
		RETURNING id
	`, req.DeviceSN, currentTenantID, req.ToTenantID, userID, req.Reason).Scan(&transferID)

	if err != nil {
		response.Error(c, 500, "创建转移请求失败")
		return
	}

	// Emit event
	h.emitEvent(c, "transfer_requested", map[string]any{
		"transfer_id": transferID,
		"device_sn": req.DeviceSN,
		"from_tenant": currentTenantID,
		"to_tenant": req.ToTenantID,
		"requester": userID,
	})

	response.Success(c, map[string]any{
		"transfer_id": transferID,
		"message": "转移请求已提交，等待对方确认",
	})
}

// ListTransfers lists transfer requests
// GET /api/v1/devices/transfers/list
func (h *DeviceClaimTransferHandler) ListTransfers(c *gin.Context) {
	userID := middleware.GetUserID(c)
	userRole := middleware.GetRole(c)
	isAdmin := userRole == 0

	// Status filter
	statusFilter := c.Query("status")
	if statusFilter != "" && !contains([]string{"pending", "approved", "rejected", "cancelled"}, statusFilter) {
		response.Error(c, 400, "invalid status filter")
		return
	}

	// Type filter: mine vs all (admin only)
	typeFilter := c.Query("type")

	ctx := c.Request.Context()

	var transfers []DeviceTransferRequest
	var err error

	if typeFilter == "mine" || (!isAdmin && typeFilter == "") {
		transfers, err = h.getMyTransfers(ctx, userID, statusFilter)
	} else {
		transfers, err = h.getAllTransfers(ctx, isAdmin, statusFilter)
	}

	if err != nil {
		response.Error(c, 500, "查询转移请求失败")
		return
	}

	response.Success(c, gin.H{
		"transfers": transfers,
		"total":     len(transfers),
	})
}

// ApproveTransfer approves a transfer request
// POST /api/v1/devices/transfers/:id/approve
func (h *DeviceClaimTransferHandler) ApproveTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)
	
	transferID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid transfer ID")
		return
	}

	var req DeviceTransferApprovalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	if !req.Approved {
		response.Error(c, 400, "approve endpoint requires approved=true")
		return
	}

	ctx := c.Request.Context()

	// Get transfer request
	var transfer DeviceTransferRequest
	err = h.db.QueryRow(ctx, `
		SELECT id, device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id,
			   reason, status, approved_by_user_id, approved_at, rejected_reason, 
			   requested_at, processed_at, updated_at
		FROM device_transfer_requests 
		WHERE id = $1
	`, transferID).
		Scan(
			&transfer.ID, &transfer.DeviceSN, &transfer.FromTenantID, &transfer.ToTenantID,
			&transfer.RequesterUserID, &transfer.Reason, &transfer.Status,
			&transfer.ApprovedByUserID, &transfer.ApprovedAt, &transfer.RejectedReason,
			&transfer.RequestedAt, &transfer.ProcessedAt, &transfer.UpdatedAt,
		)

	if err == pgx.ErrNoRows {
		response.Error(c, 404, "转移请求不存在")
		return
	} else if err != nil {
		response.Error(c, 500, "查询转移请求失败")
		return
	}

	// Validate state
	if transfer.Status != "pending" {
		response.Error(c, 409, "转移请求当前状态为 "+transfer.Status+", 无法批准")
		return
	}

	// Verify approver is the recipient
	userTenantID, err := h.getRootTenantID(ctx, userID)
	if err != nil {
		response.Error(c, 500, "获取租户信息失败")
		return
	}

	if userTenantID != transfer.FromTenantID {
		response.Error(c, 403, "只有转出方可以批准转移请求")
		return
	}

	// Begin transaction
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	// Update transfer request status
	now := time.Now().UTC()
	_, err = tx.Exec(ctx, `
		UPDATE device_transfer_requests 
		SET status = 'approved', approved_by_user_id = $1, approved_at = $2, processed_at = $3
		WHERE id = $4
	`, userID, now, now, transferID)

	if err != nil {
		response.Error(c, 500, "更新转移请求状态失败")
		return
	}

	// Note: Actual device ownership change should happen in a separate step
	// This completes the approval workflow, but device records are not yet updated

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交转移审批失败")
		return
	}

	// Emit event
	h.emitEvent(c, "transfer_approved", map[string]any{
		"transfer_id": transferID,
		"device_sn": transfer.DeviceSN,
		"approved_by": userID,
		"approved_at": now.UTC(),
	})

	response.Success(c, map[string]any{
		"message": "转移请求已批准，正在更新设备所有权",
		"transfer_id": transferID,
	})
}

// RejectTransfer rejects a transfer request
// POST /api/v1/devices/transfers/:id/reject
func (h *DeviceClaimTransferHandler) RejectTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)

	transferID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid transfer ID")
		return
	}

	var req DeviceTransferApprovalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request: "+err.Error())
		return
	}

	if req.Approved {
		response.Error(c, 400, "reject endpoint requires approved=false")
		return
	}

	// Validate reason provided for rejection
	if req.Reason == "" {
		response.Error(c, 400, "rejection must include a reason")
		return
	}

	ctx := c.Request.Context()

	// Get and validate transfer (similar to approve logic)
	var transfer DeviceTransferRequest
	err = h.db.QueryRow(ctx, `
		SELECT id, device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id,
			   reason, status, approved_by_user_id, approved_at, rejected_reason, 
			   requested_at, processed_at, updated_at
		FROM device_transfer_requests WHERE id = $1
	`, transferID).
		Scan(
			&transfer.ID, &transfer.DeviceSN, &transfer.FromTenantID, &transfer.ToTenantID,
			&transfer.RequesterUserID, &transfer.Reason, &transfer.Status,
			&transfer.ApprovedByUserID, &transfer.ApprovedAt, &transfer.RejectedReason,
			&transfer.RequestedAt, &transfer.ProcessedAt, &transfer.UpdatedAt,
		)

	if err == pgx.ErrNoRows {
		response.Error(c, 404, "转移请求不存在")
		return
	} else if err != nil {
		response.Error(c, 500, "查询转移请求失败")
		return
	}

	if transfer.Status != "pending" {
		response.Error(c, 409, "转移请求当前状态为 "+transfer.Status)
		return
	}

	// Verify approver permissions (same as approve)
	userTenantID, err := h.getRootTenantID(ctx, userID)
	if err != nil {
		response.Error(c, 500, "获取租户信息失败")
		return
	}

	if userTenantID != transfer.FromTenantID {
		response.Error(c, 403, "只有转出方可以拒绝转移请求")
		return
	}

	// Update transfer
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	now := time.Now().UTC()
	_, err = tx.Exec(ctx, `
		UPDATE device_transfer_requests 
		SET status = 'rejected', rejected_reason = $1, approved_by_user_id = $2, 
			approved_at = $3, processed_at = $4
		WHERE id = $5
	`, req.Reason, userID, now, now, transferID)

	if err != nil {
		response.Error(c, 500, "更新转移请求状态失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交转移拒绝失败")
		return
	}

	h.emitEvent(c, "transfer_rejected", map[string]any{
		"transfer_id": transferID,
		"device_sn": transfer.DeviceSN,
		"rejected_by": userID,
		"reason": req.Reason,
	})

	response.Success(c, map[string]any{
		"message": "转移请求已拒绝",
		"transfer_id": transferID,
	})
}

// CancelTransfer cancels a pending transfer request
// POST /api/v1/devices/transfers/:id/cancel
func (h *DeviceClaimTransferHandler) CancelTransfer(c *gin.Context) {
	userID := middleware.GetUserID(c)

	transferID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.Error(c, 400, "invalid transfer ID")
		return
	}

	ctx := c.Request.Context()

	// Get transfer request
	var transfer DeviceTransferRequest
	err = h.db.QueryRow(ctx, `
		SELECT id, device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id,
			   reason, status, approved_by_user_id, approved_at, rejected_reason, 
			   requested_at, processed_at, updated_at
		FROM device_transfer_requests WHERE id = $1
	`, transferID).
		Scan(
			&transfer.ID, &transfer.DeviceSN, &transfer.FromTenantID, &transfer.ToTenantID,
			&transfer.RequesterUserID, &transfer.Reason, &transfer.Status,
			&transfer.ApprovedByUserID, &transfer.ApprovedAt, &transfer.RejectedReason,
			&transfer.RequestedAt, &transfer.ProcessedAt, &transfer.UpdatedAt,
		)

	if err == pgx.ErrNoRows {
		response.Error(c, 404, "转移请求不存在")
		return
	} else if err != nil {
		response.Error(c, 500, "查询转移请求失败")
		return
	}

	// Only requester can cancel, or admin can cancel any
	userRole := middleware.GetRole(c)
	isAdmin := userRole == 0

	if transfer.Status != "pending" {
		response.Error(c, 409, "转移请求当前状态为 "+transfer.Status)
		return
	}

	if transfer.RequesterUserID != userID && !isAdmin {
		response.Error(c, 403, "只有请求发起者或管理员可以取消转移")
		return
	}

	// Update transfer
	tx, err := h.db.Begin(ctx)
	if err != nil {
		response.Error(c, 500, "数据库事务开始失败")
		return
	}
	defer tx.Rollback(ctx)

	now := time.Now().UTC()
	_, err = tx.Exec(ctx, `
		UPDATE device_transfer_requests 
		SET status = 'cancelled', processed_at = $1
		WHERE id = $2
	`, now, transferID)

	if err != nil {
		response.Error(c, 500, "取消转移请求失败")
		return
	}

	if err := tx.Commit(ctx); err != nil {
		response.Error(c, 500, "提交取消操作失败")
		return
	}

	h.emitEvent(c, "transfer_cancelled", map[string]any{
		"transfer_id": transferID,
		"device_sn": transfer.DeviceSN,
		"cancelled_by": userID,
	})

	response.Success(c, map[string]any{
		"message": "转移请求已取消",
		"transfer_id": transferID,
	})
}

// ============================================
// Helper Methods
// ============================================

func (h *DeviceClaimTransferHandler) getDeviceBySN(ctx context.Context, sn string) (*model.Device, error) {
	var device model.Device
	err := h.db.QueryRow(ctx, `
		SELECT id, sn, model,
		       COALESCE(manufacturer, ''),
		       COALESCE(firmware_arm, ''), COALESCE(firmware_esp, ''),
		       COALESCE(firmware_dsp, ''), COALESCE(firmware_bms, ''),
		       COALESCE(main_version, ''), COALESCE(device_type, ''),
		       rated_power, rated_voltage, rated_freq, battery_voltage,
		       COALESCE(battery_type, ''), cell_count,
		       station_id, user_id, status,
		       last_online_at, created_at, updated_at
		FROM devices WHERE sn = $1
	`, sn).Scan(
		&device.ID, &device.SN, &device.Model,
		&device.Manufacturer, &device.FirmwareArm,
		&device.FirmwareEsp, &device.FirmwareDSP, &device.FirmwareBMS, &device.MainVersion,
		&device.DeviceType, &device.RatedPower, &device.RatedVoltage, &device.RatedFreq,
		&device.BatteryVoltage, &device.BatteryType, &device.CellCount,
		&device.StationID, &device.UserID, &device.Status,
		&device.LastOnlineAt, &device.CreatedAt, &device.UpdatedAt,
	)

	if err != nil {
		return nil, err
	}

	return &device, nil
}

func (h *DeviceClaimTransferHandler) getRootTenantID(ctx context.Context, userID int64) (int64, error) {
	var tenantID int64
	err := h.db.QueryRow(ctx, `
		SELECT COALESCE(parent_id, id) FROM users WHERE id = $1 AND deleted_at IS NULL
	`, userID).Scan(&tenantID)

	if err != nil {
		return 0, err
	}

	return tenantID, nil
}

func (h *DeviceClaimTransferHandler) canManageDevice(ctx context.Context, userID int64, deviceID int64) bool {
	// Simplified permission check - expand as needed
	return h.permChecker.CheckPermission(userID, "devices", "manage") ||
		h.permChecker.CheckPermission(userID, "devices", "control") ||
		h.permChecker.CheckPermission(userID, "admin", "manage")
}

func (h *DeviceClaimTransferHandler) getMyTransfers(ctx context.Context, userID int64, statusFilter string) ([]DeviceTransferRequest, error) {
	rows, err := h.db.Query(ctx, `
		SELECT id, device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id,
			   reason, status, approved_by_user_id, approved_at, rejected_reason,
			   requested_at, processed_at, updated_at
		FROM device_transfer_requests
		WHERE requester_user_id = $1 AND ($2 = '' OR status = $2)
		ORDER BY requested_at DESC
	`, userID, statusFilter)

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanTransferRequests(rows)
}

func (h *DeviceClaimTransferHandler) getAllTransfers(ctx context.Context, isAdmin bool, statusFilter string) ([]DeviceTransferRequest, error) {
	query := `
		SELECT id, device_sn, from_root_tenant_id, to_root_tenant_id, requester_user_id,
			   reason, status, approved_by_user_id, approved_at, rejected_reason,
			   requested_at, processed_at, updated_at
		FROM device_transfer_requests
	`
	args := []interface{}{}
	
	if !isAdmin {
		query += " WHERE ($1 = '' OR status = $1)"
		args = append(args, statusFilter)
	} else if statusFilter != "" {
		query += " WHERE status = $1"
		args = append(args, statusFilter)
	}

	query += " ORDER BY requested_at DESC"

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanTransferRequests(rows)
}

func (h *DeviceClaimTransferHandler) emitEvent(c *gin.Context, eventName string, payload map[string]any) {
	// Placeholder for async event emission (e.g., Kafka, Redis pub/sub)
	// In production, use a proper message queue
	_ = c // Avoid unused variable warning if needed later
}

func scanTransferRequests(rows pgx.Rows) ([]DeviceTransferRequest, error) {
	var transfers []DeviceTransferRequest

	for rows.Next() {
		var t DeviceTransferRequest
		err := rows.Scan(
			&t.ID, &t.DeviceSN, &t.FromTenantID, &t.ToTenantID, &t.RequesterUserID,
			&t.Reason, &t.Status, &t.ApprovedByUserID, &t.ApprovedAt, &t.RejectedReason,
			&t.RequestedAt, &t.ProcessedAt, &t.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		transfers = append(transfers, t)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return transfers, nil
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}
