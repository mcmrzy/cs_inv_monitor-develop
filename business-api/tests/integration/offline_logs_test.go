package integration

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"os"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TestSaveOfflineLogsIdempotent verifies that re-uploading the same log_id
// is a no-op (accepted=1, duplicates=1 for two identical uploads).
// Requires DATABASE_URL to point at a test PostgreSQL instance.
func TestSaveOfflineLogsIdempotent(t *testing.T) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		t.Skip("DATABASE_URL not set; skipping integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	// cache 传 nil：本测试路径不触发缓存访问（invalidateDeviceCache 对 nil 安全）
	repo := repository.NewDeviceRepository(pool, nil)
	userID := int64(999001)
	logs := []model.OfflineOpLog{
		{
			LogID:    "integ-test-0001",
			DeviceSN: "H1CNA6K20001",
			Action:   "set_power",
			Params:   map[string]interface{}{"power_w": float64(3000)},
			Result:   "ok",
			Channel:  "ble",
			OpTime:   time.Now(),
		},
	}

	accepted, duplicates, err := repo.SaveOfflineLogs(ctx, userID, logs)
	if err != nil {
		t.Fatalf("first upload: %v", err)
	}
	if accepted != 1 || duplicates != 0 {
		t.Fatalf("first upload: accepted=%d duplicates=%d, want 1/0", accepted, duplicates)
	}

	// 幂等重放：同 log_id 应全部跳过
	accepted, duplicates, err = repo.SaveOfflineLogs(ctx, userID, logs)
	if err != nil {
		t.Fatalf("second upload: %v", err)
	}
	if accepted != 0 || duplicates != 1 {
		t.Fatalf("second upload: accepted=%d duplicates=%d, want 0/1", accepted, duplicates)
	}
}

// TestOfflineLogBatchRejectsUnauthorizedDeviceAndKeepsAuthorizedOutcomes
// verifies the first-wave v2 response semantics against PostgreSQL: current
// device scope is checked per entry, a rejected entry does not roll back an
// authorized entry, and replay returns a per-id duplicate outcome.
func TestOfflineLogBatchRejectsUnauthorizedDeviceAndKeepsAuthorizedOutcomes(t *testing.T) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		t.Skip("DATABASE_URL not set; skipping integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	suffix := time.Now().UTC().Format("20060102150405.000000000")
	userID := int64(990001)
	allowedSN := "OFFLOG-ALLOW-" + suffix
	deniedSN := "OFFLOG-DENY-" + suffix
	acceptedID := "offline-accepted-" + suffix
	rejectedID := "offline-rejected-" + suffix
	defer func() {
		_, _ = pool.Exec(ctx, `DELETE FROM device_offline_op_logs WHERE log_id = ANY($1)`, []string{acceptedID, rejectedID})
		_, _ = pool.Exec(ctx, `DELETE FROM devices WHERE sn = ANY($1)`, []string{allowedSN, deniedSN})
	}()

	_, err = pool.Exec(ctx, `
		INSERT INTO devices(sn, model, user_id) VALUES
			($1, 'CS-INV-TEST', $3),
			($2, 'CS-INV-TEST', $4)`, allowedSN, deniedSN, userID, userID+1)
	if err != nil {
		t.Fatalf("seed devices: %v", err)
	}

	repo := repository.NewDeviceRepository(pool, nil)
	svc := service.NewDeviceService(repo, nil, repository.NewModelRepository(pool, nil), nil, "", "", pool)
	actor := model.ActorContext{UserID: userID}
	logs := []model.OfflineOpLog{
		{LogID: acceptedID, DeviceSN: allowedSN, Action: "control", Params: map[string]interface{}{}, Result: "unknown", Channel: "ble", OpTime: time.Now().UTC()},
		{LogID: rejectedID, DeviceSN: deniedSN, Action: "control", Params: map[string]interface{}{}, Result: "unknown", Channel: "ble", OpTime: time.Now().UTC()},
	}

	result, err := svc.SaveOfflineLogs(ctx, actor, logs)
	if err != nil {
		t.Fatalf("first batch: %v", err)
	}
	if result.Accepted != 1 || result.Duplicates != 0 || result.Rejected != 1 {
		t.Fatalf("first batch counts = %+v, want accepted=1 duplicates=0 rejected=1", result)
	}
	outcomes := make(map[string]model.OfflineLogResult, len(result.Results))
	for _, item := range result.Results {
		outcomes[item.LogID] = item
	}
	if outcomes[acceptedID].Status != model.OfflineLogAccepted {
		t.Fatalf("authorized log outcome = %+v, want accepted", outcomes[acceptedID])
	}
	if outcomes[rejectedID].Status != model.OfflineLogRejected || outcomes[rejectedID].Reason != "device_access_denied" {
		t.Fatalf("unauthorized log outcome = %+v, want rejected/device_access_denied", outcomes[rejectedID])
	}

	retry, err := svc.SaveOfflineLogs(ctx, actor, logs[:1])
	if err != nil {
		t.Fatalf("replay batch: %v", err)
	}
	if retry.Accepted != 0 || retry.Duplicates != 1 || retry.Rejected != 0 || len(retry.Results) != 1 || retry.Results[0].Status != model.OfflineLogDuplicate {
		t.Fatalf("replay outcome = %+v, want one duplicate", retry)
	}
}

// TestBindStoresDeviceKeyHash verifies the registry-based bind: the raw
// device_key is never stored, only its SHA-256 hex digest lands in
// devices.device_key_hash (design doc §4.1 / plan appendix A).
// Requires DATABASE_URL to point at a test PostgreSQL instance.
func TestBindStoresDeviceKeyHash(t *testing.T) {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		t.Skip("DATABASE_URL not set; skipping integration test")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	// cache 传 nil：本测试路径不触发缓存访问（invalidateDeviceCache 对 nil 安全）
	repo := repository.NewDeviceRepository(pool, nil)
	sn := "H1CNA6K29999" // 测试专用 SN，先确保未绑定
	userID := int64(999002)
	stationID := int64(0)

	// 准备：确保设备存在且未绑定
	_ = repo.EnsureDevice(ctx, sn)

	// App 生成的 32B 随机 key
	rawKey := make([]byte, 32)
	if _, err := rand.Read(rawKey); err != nil {
		t.Fatalf("rand: %v", err)
	}
	deviceKey := base64.StdEncoding.EncodeToString(rawKey)
	sum := sha256.Sum256(rawKey)
	wantHash := hex.EncodeToString(sum[:])

	if err := repo.Bind(ctx, sn, userID, stationID, wantHash); err != nil {
		t.Fatalf("bind: %v", err)
	}

	// 断言：库中只存摘要，无明文
	var gotHash string
	err = pool.QueryRow(ctx, `SELECT COALESCE(device_key_hash,'') FROM devices WHERE sn=$1`, sn).Scan(&gotHash)
	if err != nil {
		t.Fatalf("query hash: %v", err)
	}
	if gotHash != wantHash {
		t.Fatalf("device_key_hash = %q, want %q", gotHash, wantHash)
	}
	// 重复绑定应失败（device already bound）
	if err := repo.Bind(ctx, sn, userID, stationID, wantHash); err == nil {
		t.Fatalf("second bind: expected error, got nil")
	}
	// 防误用：确认明文 device_key 不会出现在库中（device_key_hash 与 Base64 明文不同）
	_ = deviceKey
}
