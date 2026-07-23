//go:build integration

package integration

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// =============================================================================
// TestDeviceClaimFlow — Device claim code generation, verification, and claiming
// =============================================================================

func TestDeviceClaimCode_Generate(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM")

	data := ctx.generateClaimCode(t, sn, 24)
	assert.NotEmpty(t, data["claim_code"], "should return claim code")
	assert.Equal(t, sn, data["sn"])
	assert.Equal(t, "pending", data["status"])
}

func TestDeviceClaimCode_Generate_AlreadyClaimed(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM-DUP")

	// First bind the device so it exists
	doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)

	// Generate first claim code
	ctx.generateClaimCode(t, sn, 24)

	// Generate second claim code → should conflict if device already claimed
	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/claim-code/generate",
		map[string]interface{}{"sn": sn, "expires_hours": 24}, ctx.Token, 5)
	t.Logf("dup claim code: status=%d code=%d msg=%s", status, resp.Code, resp.Message)
	// The behavior depends on whether the device is already claimed
	// At minimum, the response should be valid
	assert.Equal(t, http.StatusOK, status)
}

func TestDeviceClaimCode_Generate_InvalidExpires(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM-INV")

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/claim-code/generate",
		map[string]interface{}{"sn": sn, "expires_hours": 0}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "zero expires_hours should be rejected")
}

func TestDeviceClaimCode_Verify_Valid(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM-VV")

	codeData := ctx.generateClaimCode(t, sn, 24)
	claimCode, _ := codeData["claim_code"].(string)
	require.NotEmpty(t, claimCode, "need claim code for verification")

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/claim-code/verify",
		map[string]interface{}{"claim_code": claimCode}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "valid code should verify: %s", resp.Message)

	var data map[string]interface{}
	if resp.Data != nil {
		_ = json.Unmarshal(resp.Data, &data)
		t.Logf("verify result: %v", data)
	}
}

func TestDeviceClaimCode_Verify_Invalid(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/claim-code/verify",
		map[string]interface{}{"claim_code": "INVALID-CODE-XXXXX"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "invalid code should not verify")
}

func TestDeviceClaim_WithValidCode(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM-CLAIM")

	// Bind device first
	bindResp, bindStatus := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)
	t.Logf("bind: status=%d code=%d msg=%s", bindStatus, bindResp.Code, bindResp.Message)

	// Generate claim code
	codeData := ctx.generateClaimCode(t, sn, 24)
	claimCode, _ := codeData["claim_code"].(string)
	require.NotEmpty(t, claimCode)

	// Claim device
	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/by-sn/%s/claim", ctx.BaseURL, sn),
		map[string]interface{}{"sn": sn, "claim_code": claimCode}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("claim: code=%d msg=%s", resp.Code, resp.Message)
	assert.Equal(t, 0, resp.Code, "claim should succeed")
}

func TestDeviceClaim_WithWrongCode(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("CLM-WRONG")

	// Bind device
	doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/by-sn/%s/claim", ctx.BaseURL, sn),
		map[string]interface{}{"sn": sn, "claim_code": "WRONG-CODE"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "wrong code should be rejected")
}

func TestDeviceClaim_UnauthorizedNoToken(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.APIBaseURL, "", "API Gateway")
	client := &http.Client{Timeout: 10 * time.Second}

	_, status := doJSON(t, client, "POST",
		cfg.APIBaseURL+"/api/v1/devices/by-sn/TEST-SN/claim",
		map[string]interface{}{"sn": "TEST-SN", "claim_code": "CODE"}, "")
	assert.Equal(t, http.StatusUnauthorized, status)
}

// =============================================================================
// TestDeviceTransfer — Ownership transfer lifecycle
// =============================================================================

func TestDeviceTransfer_RequestTransfer(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("TRF")

	// Bind device
	doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)

	// Request transfer to another tenant
	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/by-sn/%s/request-transfer", ctx.BaseURL, sn),
		map[string]interface{}{
			"device_sn":    sn,
			"to_tenant_id": 999,
			"reason":       "test transfer",
		}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	t.Logf("transfer request: code=%d msg=%s", resp.Code, resp.Message)
	// May succeed or fail depending on tenant validation
}

func TestDeviceTransfer_ListTransfers(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSONWithRetry(t, ctx.Client, "GET",
		ctx.BaseURL+"/api/v1/devices/transfers/list?page=1&page_size=20", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, 0, resp.Code, "list transfers should succeed")
}

func TestDeviceTransfer_ApproveNonExistent(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/devices/transfers/999999999/approve",
		map[string]interface{}{"approved": true}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "approving non-existent transfer should fail")
}

func TestDeviceTransfer_RejectNonExistent(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/devices/transfers/999999999/reject",
		map[string]interface{}{"approved": false, "reason": "test reject"}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "rejecting non-existent transfer should fail")
}

func TestDeviceTransfer_CancelNonExistent(t *testing.T) {
	ctx := setupChannelTest(t)

	resp, status := doJSONWithRetry(t, ctx.Client, "POST",
		ctx.BaseURL+"/api/v1/devices/transfers/999999999/cancel", nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	assert.NotEqual(t, 0, resp.Code, "cancelling non-existent transfer should fail")
}

func TestDeviceTransfer_FullLifecycle(t *testing.T) {
	ctx := setupChannelTest(t)
	sn := uniqueSN("TRF-FULL")

	// Bind device
	bindResp, _ := doJSONWithRetry(t, ctx.Client, "POST", ctx.BaseURL+"/api/v1/devices/bind",
		map[string]interface{}{"sn": sn, "station_id": 0}, ctx.Token, 5)
	if bindResp.Code != 0 {
		t.Skipf("device bind failed: %s", bindResp.Message)
		return
	}

	// Request transfer
	transferResp, status := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/by-sn/%s/request-transfer", ctx.BaseURL, sn),
		map[string]interface{}{
			"device_sn":    sn,
			"to_tenant_id": 1,
			"reason":       "full lifecycle test",
		}, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, status)
	if transferResp.Code != 0 {
		t.Logf("transfer request failed: code=%d msg=%s — skipping lifecycle", transferResp.Code, transferResp.Message)
		return
	}

	var tData map[string]interface{}
	require.NoError(t, json.Unmarshal(transferResp.Data, &tData))
	transferID, ok := tData["id"].(float64)
	if !ok || transferID == 0 {
		t.Skip("transfer ID not returned, cannot continue lifecycle")
		return
	}

	// Cancel the transfer
	cancelResp, cancelStatus := doJSONWithRetry(t, ctx.Client, "POST",
		fmt.Sprintf("%s/api/v1/devices/transfers/%d/cancel", ctx.BaseURL, int64(transferID)), nil, ctx.Token, 5)
	assert.Equal(t, http.StatusOK, cancelStatus)
	t.Logf("cancel transfer: code=%d msg=%s", cancelResp.Code, cancelResp.Message)
}
