# BLE 后端扩展（绑定返回 device_key + 离线日志上报）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 扩展 business-api：`POST /devices/bind` 生成并返回 device_key（仅存 SHA-256 摘要），新增 `POST /devices/offline-logs` 批量幂等上报接口（配套 `device_offline_op_logs` 表）。

**Architecture:** 遵循 Handler → Service → Repository 三层。device_key 由 Service 层用 `crypto/rand` 生成（32B Base64），仅下发一次，库中只存 SHA-256 摘要；离线日志以 `(user_id, log_id)` 唯一约束实现幂等。校验逻辑（action 白名单 / log_id 格式 / 批量上限）为纯函数，便于单元测试。

**Tech Stack:** Go + Gin + pgx（PostgreSQL）+ crypto/rand + sha256

**依赖设计文档:** `docs/superpowers/specs/2026-08-10-ble-local-mode-design.md` §4

**前置约定：** 最新迁移编号为 097，新迁移为 098；`DeviceRepository` 为具体类型（非接口），`internal/testutil/mocks/mock_device_alarm.go` 中的 `MockDeviceRepo` 需同步签名。

---

### Task 1: 数据库迁移 098（devices.device_key_hash + device_offline_op_logs 表）

**Files:**
- Create: `database/migrations/098_ble_device_key_offline_logs.up.sql`
- Create: `database/migrations/098_ble_device_key_offline_logs.down.sql`
- Modify: `database/schema.sql:277-311`（devices 表加列）、`database/schema.sql`（文件末尾新增表定义，与迁移保持一致）

- [ ] **Step 1: 创建 up 迁移**

`database/migrations/098_ble_device_key_offline_logs.up.sql`：

```sql
--
-- 背景：BLE 本地模式（App 通过蓝牙直连设备）：
--   1. devices 增加 device_key_hash —— 绑定设备时云端生成的 device_key 仅返回一次，
--      库中只存 SHA-256 摘要（设计文档 §4.1）。
--   2. device_offline_op_logs —— App 离线期间本地记录的操作日志，联网后批量上报，
--      (user_id, log_id) 唯一约束实现幂等（设计文档 §4.2）。
--
-- 幂等可重放：ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS。

ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_key_hash VARCHAR(64);

CREATE TABLE IF NOT EXISTS device_offline_op_logs (
    id BIGSERIAL PRIMARY KEY,
    log_id VARCHAR(64) NOT NULL,                 -- App 本地 UUID，同步幂等键
    user_id BIGINT NOT NULL,                     -- 同步时归属用户
    device_sn VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,                 -- bind/unbind/power_on/power_off/set_power/set_param/ota
    params JSONB DEFAULT '{}',
    result VARCHAR(50) DEFAULT 'ok',
    channel VARCHAR(10) DEFAULT 'ble',           -- cloud/ble
    op_time TIMESTAMPTZ NOT NULL,                -- App 上报的本地操作时间
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, log_id)
);

CREATE INDEX IF NOT EXISTS idx_offline_logs_user_time ON device_offline_op_logs(user_id, op_time DESC);
CREATE INDEX IF NOT EXISTS idx_offline_logs_sn ON device_offline_op_logs(device_sn);
```

- [ ] **Step 2: 创建 down 迁移**

`database/migrations/098_ble_device_key_offline_logs.down.sql`：

```sql
DROP TABLE IF EXISTS device_offline_op_logs;
ALTER TABLE devices DROP COLUMN IF EXISTS device_key_hash;
```

- [ ] **Step 3: 同步 schema.sql（devices 表加列）**

在 `database/schema.sql` 第 305 行 `alias VARCHAR(100), -- 设备别名（App 可编辑, migration 095）` 之前（即 `sort_order` 行附近）无需改动；直接在 `user_id BIGINT NOT NULL,` 行（第 299 行）之后插入一行，保持列顺序与迁移一致：

在 `database/schema.sql` 中 `user_id BIGINT NOT NULL,`（devices 表定义内，约 299 行）之后新增：

```sql
    device_key_hash VARCHAR(64),                  -- BLE 绑定密钥 SHA-256 摘要 (migration 098)
```

> 定位提示：该文件中存在两处 `CREATE TABLE IF NOT EXISTS devices`，只改 277-311 行的那处（含 `firmware_arm`/`main_version` 等列的新版表）。

- [ ] **Step 4: 同步 schema.sql（新增 device_offline_op_logs 表）**

在 `database/schema.sql` 中 `CREATE TABLE IF NOT EXISTS devices`（277 行那版）的索引定义 `CREATE INDEX idx_devices_timezone ON devices(timezone);` 之后，追加与迁移完全一致的建表语句（含 2 个索引，见 Step 1）。

- [ ] **Step 5: 验证 SQL 语法并提交**

Run: `psql --version`（若本机无 psql，跳过本步，在部署环境验证）
Expected: 无错误输出。

```bash
git add database/migrations/098_ble_device_key_offline_logs.up.sql database/migrations/098_ble_device_key_offline_logs.down.sql database/schema.sql
git commit -m "feat(db): add device_key_hash and device_offline_op_logs for BLE local mode"
```

---

### Task 2: 数据模型 + Repository 层（Bind 扩展 / Unbind 清理 / SaveOfflineLogs）

**Files:**
- Modify: `business-api/internal/model/models.go`（新增 OfflineOpLog）
- Modify: `business-api/internal/repository/repositories.go:1617-1633`（Bind 签名）、`repositories.go:1635-1660`（Unbind 清理）、`repositories.go`（新增 SaveOfflineLogs）
- Modify: `business-api/internal/testutil/mocks/mock_device_alarm.go:88-94`（MockDeviceRepo.Bind 签名）

- [ ] **Step 1: model 新增 OfflineOpLog**

在 `business-api/internal/model/models.go` 的 `Device` struct 定义之后追加：

```go
// OfflineOpLog represents one local operation log uploaded by the App
// (BLE local mode, design doc §4.2).
type OfflineOpLog struct {
	LogID    string                 `json:"log_id"`
	DeviceSN string                 `json:"device_sn"`
	Action   string                 `json:"action"`
	Params   map[string]interface{} `json:"params"`
	Result   string                 `json:"result"`
	Channel  string                 `json:"channel"`
	OpTime   time.Time              `json:"op_time"`
}
```

确认文件已 import `"time"`（若没有则添加）。

- [ ] **Step 2: 修改 Repository.Bind（加 deviceKeyHash 参数并写库）**

将 `business-api/internal/repository/repositories.go` 第 1617-1633 行的 Bind 方法整体替换为：

```go
// Bind binds a device to the current user, storing the SHA-256 hash of its
// device_key (the raw key is returned to the client only once).
func (r *DeviceRepository) Bind(ctx context.Context, sn string, userID, stationID int64, deviceKeyHash string) error {
	query := `UPDATE devices
		SET user_id = $1,
			station_id = NULLIF($2::bigint, 0),
			timezone = COALESCE((SELECT timezone FROM stations WHERE id = NULLIF($2::bigint, 0)), 'Asia/Shanghai'),
			device_key_hash = $3,
			updated_at = NOW()
		WHERE sn = $4 AND user_id = 0`
	tag, err := r.db.Exec(ctx, query, userID, stationID, deviceKeyHash, sn)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("device already bound")
	}
	r.invalidateDeviceCache(ctx, sn)
	return nil
}
```

- [ ] **Step 3: 修改 Repository.Unbind（清 device_key_hash）**

将 `repositories.go` 第 1640 行的 Unbind UPDATE 语句改为：

```go
	query := `UPDATE devices SET user_id = 0, station_id = NULL, timezone = 'Asia/Shanghai', device_key_hash = NULL, updated_at = NOW() WHERE sn = $1`
```

- [ ] **Step 4: Repository 新增 SaveOfflineLogs**

在 `repositories.go` 的 Unbind 方法之后追加：

```go
// SaveOfflineLogs batch-inserts offline operation logs uploaded by the App.
// Idempotency: (user_id, log_id) unique constraint; duplicates are skipped.
// Returns (accepted, duplicates, err).
func (r *DeviceRepository) SaveOfflineLogs(ctx context.Context, userID int64, logs []model.OfflineOpLog) (int, int, error) {
	accepted := 0
	for _, log := range logs {
		params, err := json.Marshal(log.Params)
		if err != nil {
			return accepted, 0, fmt.Errorf("marshal params: %w", err)
		}
		tag, err := r.db.Exec(ctx, `
			INSERT INTO device_offline_op_logs (log_id, user_id, device_sn, action, params, result, channel, op_time)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			ON CONFLICT (user_id, log_id) DO NOTHING`,
			log.LogID, userID, log.DeviceSN, log.Action, params, log.Result, log.Channel, log.OpTime)
		if err != nil {
			return accepted, 0, err
		}
		accepted += int(tag.RowsAffected())
	}
	return accepted, len(logs) - accepted, nil
}
```

确认文件已 import `"encoding/json"` 与 model 包（检查 `model "inv-api-server/internal/model"` 是否已有，没有则添加）。

- [ ] **Step 5: 更新 MockDeviceRepo.Bind 签名**

将 `business-api/internal/testutil/mocks/mock_device_alarm.go` 第 88-94 行替换为：

```go
func (m *MockDeviceRepo) Bind(ctx context.Context, sn string, userID, stationID int64, deviceKeyHash string) error {
	m.record("Bind", sn, userID, stationID)
	if m.BindFunc != nil {
		return m.BindFunc(ctx, sn, userID, stationID, deviceKeyHash)
	}
	return nil
}
```

- [ ] **Step 6: 编译验证并提交**

Run: `make build-api`（在仓库根目录执行）
Expected: BUILD SUCCESS（无编译错误）

```bash
git add business-api/internal/model/models.go business-api/internal/repository/repositories.go business-api/internal/testutil/mocks/mock_device_alarm.go
git commit -m "feat(api): extend Bind with device_key_hash, add SaveOfflineLogs"
```

---

### Task 3: Service 层（device_key 生成 + Bind/SaveOfflineLogs）

**Files:**
- Modify: `business-api/internal/service/services.go:570-572`（Bind 签名改为返回 key）
- Modify: `business-api/internal/service/services.go`（Bind 方法后追加 generateDeviceKey 与 SaveOfflineLogs）
- Test: Create `business-api/internal/service/device_key_test.go`

- [ ] **Step 1: 先写 generateDeviceKey 单元测试（TDD）**

Create `business-api/internal/service/device_key_test.go`：

```go
package service

import (
	"encoding/base64"
	"encoding/hex"
	"strings"
	"testing"
)

func TestGenerateDeviceKey(t *testing.T) {
	key, hash, err := generateDeviceKey()
	if err != nil {
		t.Fatalf("generateDeviceKey returned error: %v", err)
	}
	// key: 32 字节随机数 Base64
	raw, err := base64.StdEncoding.DecodeString(key)
	if err != nil {
		t.Fatalf("device_key is not valid base64: %v", err)
	}
	if len(raw) != 32 {
		t.Fatalf("device_key decoded length = %d, want 32", len(raw))
	}
	// hash: 对应原始密钥的 SHA-256 hex（64 字符）
	if len(hash) != 64 {
		t.Fatalf("device_key_hash length = %d, want 64", len(hash))
	}
	if !strings.EqualFold(hash, hex.EncodeToString(sha256Sum(raw))) {
		t.Fatalf("device_key_hash does not match the raw key")
	}
	// 随机性：两次生成不同
	key2, _, err := generateDeviceKey()
	if err != nil {
		t.Fatalf("generateDeviceKey second call returned error: %v", err)
	}
	if key == key2 {
		t.Fatalf("generateDeviceKey produced identical keys")
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd business-api && go test ./internal/service/ -run TestGenerateDeviceKey -v`
Expected: FAIL（`undefined: generateDeviceKey`）

- [ ] **Step 3: 实现 generateDeviceKey 与 Bind/SaveOfflineLogs**

将 `business-api/internal/service/services.go` 第 570-572 行的 Bind 方法替换为：

```go
// Bind binds a device and returns a fresh device_key (Base64, 32 random bytes).
// The raw key is returned to the client exactly once; only its SHA-256 hash
// is stored (design doc §4.1).
func (s *DeviceService) Bind(ctx context.Context, sn string, userID, stationID int64) (string, error) {
	deviceKey, hash, err := generateDeviceKey()
	if err != nil {
		return "", err
	}
	if err := s.repo.Bind(ctx, sn, userID, stationID, hash); err != nil {
		return "", err
	}
	return deviceKey, nil
}

// SaveOfflineLogs persists offline operation logs uploaded by the App.
func (s *DeviceService) SaveOfflineLogs(ctx context.Context, userID int64, logs []model.OfflineOpLog) (int, int, error) {
	return s.repo.SaveOfflineLogs(ctx, userID, logs)
}
```

在同一文件（`DeviceService` 定义之后）追加辅助函数：

```go
// generateDeviceKey returns (base64 raw key, sha256 hex hash) for a 32-byte
// random key. The raw key is only ever returned to the binding client.
func generateDeviceKey() (string, string, error) {
	keyBytes := make([]byte, 32)
	if _, err := rand.Read(keyBytes); err != nil {
		return "", "", fmt.Errorf("generate device key: %w", err)
	}
	sum := sha256.Sum256(keyBytes)
	return base64.StdEncoding.EncodeToString(keyBytes), hex.EncodeToString(sum[:]), nil
}
```

确认 `services.go` 已 import：`"crypto/rand"`、`"crypto/sha256"`、`"encoding/base64"`、`"encoding/hex"`（若缺失则补充）。

- [ ] **Step 4: 补充测试辅助函数 sha256Sum**

在 `business-api/internal/service/device_key_test.go` 末尾追加：

```go
func sha256Sum(b []byte) []byte {
	s := sha256.Sum256(b)
	return s[:]
}
```

并将 Step 1 测试中调用处保持为 `sha256Sum(raw)`（与上一致），同时补 import `"crypto/sha256"`。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd business-api && go test ./internal/service/ -run TestGenerateDeviceKey -v`
Expected: PASS

- [ ] **Step 6: 编译验证并提交**

Run: `make build-api`
Expected: BUILD SUCCESS

```bash
git add business-api/internal/service/services.go business-api/internal/service/device_key_test.go
git commit -m "feat(api): generate device_key on bind, add SaveOfflineLogs service"
```

---

### Task 4: Handler 层（Bind 返回 device_key + UploadOfflineLogs）

**Files:**
- Modify: `business-api/internal/handler/device_binding_handler.go:65-75`（Bind 响应）、`device_binding_handler.go:329-333`（ImportExcel 调用点）
- Create: `business-api/internal/handler/offline_log_handler.go`
- Test: Create `business-api/internal/handler/offline_log_handler_test.go`

- [ ] **Step 1: 先写校验纯函数测试（TDD）**

Create `business-api/internal/handler/offline_log_handler_test.go`：

```go
package handler

import (
	"testing"
	"time"

	"inv-api-server/internal/model"
)

func TestValidOfflineLog(t *testing.T) {
	base := model.OfflineOpLog{
		LogID:    "9f8e7d6c-5b4a-4321-9876-fedcba098765",
		DeviceSN: "H1CNA6K20001",
		Action:   "set_power",
		Params:   map[string]interface{}{"power_w": float64(3000)},
		Result:   "ok",
		Channel:  "ble",
		OpTime:   time.Now(),
	}

	if !validOfflineLog(base) {
		t.Fatal("valid log rejected")
	}

	cases := []struct {
		name   string
		mutate func(*model.OfflineOpLog)
	}{
		{"empty log_id", func(l *model.OfflineOpLog) { l.LogID = "" }},
		{"bad log_id", func(l *model.OfflineOpLog) { l.LogID = "not a uuid!" }},
		{"empty sn", func(l *model.OfflineOpLog) { l.DeviceSN = "" }},
		{"unknown action", func(l *model.OfflineOpLog) { l.Action = "rm_rf" }},
		{"bad channel", func(l *model.OfflineOpLog) { l.Channel = "wifi" }},
		{"zero op_time", func(l *model.OfflineOpLog) { l.OpTime = time.Time{} }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			log := base
			tc.mutate(&log)
			if validOfflineLog(log) {
				t.Fatalf("%s: expected invalid", tc.name)
			}
		})
	}
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd business-api && go test ./internal/handler/ -run TestValidOfflineLog -v`
Expected: FAIL（`undefined: validOfflineLog`）

- [ ] **Step 3: 实现校验纯函数与 UploadOfflineLogs handler**

Create `business-api/internal/handler/offline_log_handler.go`：

```go
package handler

import (
	"regexp"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/pkg/response"

	"github.com/gin-gonic/gin"
)

// maxOfflineLogsPerBatch caps a single upload request (design doc §4.3).
const maxOfflineLogsPerBatch = 50

var offlineLogIDRegex = regexp.MustCompile(`^[0-9a-fA-F-]{8,64}$`)

// offlineActionWhitelist mirrors the App's local op log actions
// (design doc §3.5): bind/unbind, control commands, set_param, ota.
var offlineActionWhitelist = map[string]bool{
	"bind": true, "unbind": true, "power_on": true, "power_off": true,
	"set_power": true, "set_param": true, "ota": true,
}

// validOfflineLog validates a single offline log entry.
func validOfflineLog(log model.OfflineOpLog) bool {
	if !offlineLogIDRegex.MatchString(log.LogID) {
		return false
	}
	if log.DeviceSN == "" || len(log.DeviceSN) > 50 {
		return false
	}
	if !offlineActionWhitelist[log.Action] {
		return false
	}
	switch log.Channel {
	case "", "cloud", "ble":
	default:
		return false
	}
	if log.OpTime.IsZero() {
		return false
	}
	return true
}

// UploadOfflineLogs receives operation logs collected by the App while
// offline (BLE local mode). Deduplication is enforced by the
// (user_id, log_id) unique constraint.
func (h *DeviceHandler) UploadOfflineLogs(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req struct {
		Logs []model.OfflineOpLog `json:"logs"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, 400, "invalid request")
		return
	}
	if len(req.Logs) == 0 || len(req.Logs) > maxOfflineLogsPerBatch {
		response.Error(c, 400, "logs count must be between 1 and 50")
		return
	}
	for i := range req.Logs {
		// 归一化：缺省 channel 视为 ble、缺省 result 视为 ok
		if req.Logs[i].Channel == "" {
			req.Logs[i].Channel = "ble"
		}
		if req.Logs[i].Result == "" {
			req.Logs[i].Result = "ok"
		}
		if req.Logs[i].Params == nil {
			req.Logs[i].Params = map[string]interface{}{}
		}
		if !validOfflineLog(req.Logs[i]) {
			response.Error(c, 400, "invalid log entry")
			return
		}
	}

	accepted, duplicates, err := h.deviceService.SaveOfflineLogs(c.Request.Context(), userID, req.Logs)
	if err != nil {
		response.Error(c, 500, "save offline logs failed")
		return
	}
	response.Success(c, gin.H{
		"accepted":    accepted,
		"duplicates":  duplicates,
	})
}
```

- [ ] **Step 4: 修改 Bind handler 返回 device_key**

将 `business-api/internal/handler/device_binding_handler.go` 第 65-74 行替换为：

```go
	deviceKey, err := h.deviceService.Bind(c.Request.Context(), req.SN, userID, req.StationID)
	if err != nil {
		if err.Error() == "device already bound" {
			response.Error(c, 5002, "device already bound")
			return
		}
		response.Error(c, 500, "bind device failed")
		return
	}

	response.SuccessWithMessage(c, "device bound success", gin.H{
		"device_key": deviceKey,
	})
```

- [ ] **Step 5: 适配 ImportExcel 调用点**

将 `device_binding_handler.go` 第 329-333 行替换为：

```go
		if _, err := h.deviceService.Bind(c.Request.Context(), sn, userID, stationID); err != nil {
			failedCount++
			importErrors = append(importErrors, fmt.Sprintf("第%d行: 绑定失败: %s - %s", i+1, sn, err.Error()))
			continue
		}
```

- [ ] **Step 6: 运行测试确认通过**

Run: `cd business-api && go test ./internal/handler/ -run TestValidOfflineLog -v`
Expected: PASS

- [ ] **Step 7: 编译验证并提交**

Run: `make build-api`
Expected: BUILD SUCCESS

```bash
git add business-api/internal/handler/offline_log_handler.go business-api/internal/handler/offline_log_handler_test.go business-api/internal/handler/device_binding_handler.go
git commit -m "feat(api): return device_key from bind, add offline-logs upload handler"
```

---

### Task 5: 路由注册

**Files:**
- Modify: `business-api/cmd/main.go:880-881`（在 /devices/bind 与 /devices/batch/control 之间注册）

- [ ] **Step 1: 注册 POST /devices/offline-logs**

将 `business-api/cmd/main.go` 第 880-881 行之间（`auth.POST("/devices/bind", ...)` 之后）插入：

```go
			auth.POST("/devices/offline-logs", deps.DeviceHandler.UploadOfflineLogs)
```

- [ ] **Step 2: 编译验证并提交**

Run: `make build-api`
Expected: BUILD SUCCESS

```bash
git add business-api/cmd/main.go
git commit -m "feat(api): register POST /devices/offline-logs route"
```

---

### Task 6: 集成测试（幂等与批量上限，需 Docker PostgreSQL）

**Files:**
- Create: `business-api/tests/integration/offline_logs_test.go`

- [ ] **Step 1: 编写集成测试**

Create `business-api/tests/integration/offline_logs_test.go`：

```go
package integration

import (
	"context"
	"os"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"

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

	repo := repository.NewDeviceRepository(pool)
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
```

> 若 `repository.NewDeviceRepository` 构造函数名不同，先 `grep -n "func NewDeviceRepository" business-api/internal/repository/repositories.go` 确认。

- [ ] **Step 2: 运行集成测试（需先启动 PostgreSQL 并执行迁移 098）**

Run: `cd business-api && $env:DATABASE_URL="postgres://postgres:postgres@localhost:5432/inv_test"; go test ./tests/integration/ -run TestSaveOfflineLogsIdempotent -v`
Expected: PASS（无 DATABASE_URL 时 SKIP）

- [ ] **Step 3: 提交**

```bash
git add business-api/tests/integration/offline_logs_test.go
git commit -m "test(api): integration test for offline logs idempotency"
```

---

### Task 7: 全量验证

- [ ] **Step 1: 编译 + 单元测试 + 静态检查**

Run: `make build-api && make test-go && make vet-go`
Expected: 全部通过（0 failures）

- [ ] **Step 2: 确认无遗漏调用点**

Run: `grep -rn "\.Bind(ctx" business-api/internal business-api/tests | grep -v "_test.go"`
Expected: 仅剩 `services.go` 与 `mock_device_alarm.go` 两处已更新的签名（任何报错的调用点需修正为 5 参数新签名）。

- [ ] **Step 3: 提交收尾（如 Step 2 有修正）**

```bash
git add -A business-api
git commit -m "fix(api): align remaining Bind call sites"
```

---

## 附录 A：PIN 方案修订（2026-08-10 定稿）

> 设计文档已更新（§1.2 决策表 +11/12 行、§4.1 登记制、§5.4 PIN 机制、§6 修订③、§7.1/§8/§9）。本附录列出对本计划的**差异修订**，执行时按附录优先。

### 核心变化

1. **device_key 由 App 生成**（32B 随机 Base64），后端 bind 接口改为**登记制**：接收 App 上传的原始 key → 校验格式 → 算 SHA-256 → 存 `devices.device_key_hash`。
2. 老客户端（不带 device_key）兼容：后端仍保留 `generateDeviceKey()` 生成逻辑（作为兼容分支，不返回给客户端——老客户端逻辑不变）。
3. 绑定**无需联网/登录**（离线绑定后补登记），后端不再下发 device_key/expires。
4. PIN 校验完全在设备端（§5.4），**后端无 PIN 相关改动**（不存 PIN、不校验 PIN）。

### 受影响 Task 及修订

#### Task 3（Service 层）修订

- `generateDeviceKey()` 保留但降级为**兼容分支**：仅当请求未携带 `device_key` 时调用（老客户端）。
- `DeviceService.Bind` 签名修订：

```go
// deviceKeyRaw 可选：App 生成的 32B Base64 key（新客户端）；空串 = 老客户端走兼容生成
func (s *DeviceService) Bind(ctx context.Context, sn, userID, stationID, deviceKeyRaw string) error {
    var hash string
    if deviceKeyRaw != "" {
        raw, err := base64.StdEncoding.DecodeString(deviceKeyRaw)
        if err != nil || len(raw) != 32 {
            return apperr.New(apperr.CodeInvalidParam, "invalid device_key")
        }
        sum := sha256.Sum256(raw)
        hash = hex.EncodeToString(sum[:])
    } else {
        _, h, err := generateDeviceKey() // 兼容：生成并取哈希
        if err != nil { return err }
        hash = h
    }
    return s.repo.Bind(ctx, sn, userID, stationID, hash)
}
```

- device_key 格式校验抽为纯函数 `validDeviceKey(raw string) bool`（base64 解码后长度 32）——单测直接覆盖。

#### Task 4（Handler 层）修订

- `BindDeviceRequest` 增加可选字段：

```go
type BindDeviceRequest struct {
    SN        string `json:"SN" binding:"required"`
    StationID int64  `json:"station_id"`
    DeviceKey string `json:"device_key"` // 可选：App 生成（新客户端）
}
```

- Handler 透传 `req.DeviceKey` 给 Service；**响应不再返回 device_key**（`gin.H{"message": "bound"}`）。
- `validDeviceKey` 校验失败 → 400（`CodeInvalidParam`）。

#### Task 6（集成测试）修订

- 新增用例：
  - 携带合法 device_key（32B Base64）→ 201/200，库中 `device_key_hash` = SHA-256(key)（查询断言）
  - 携带非法 device_key（长度 ≠ 32B）→ 400
  - 不带 device_key（老客户端）→ 200（兼容生成分支）
  - 重复绑定 → 5002（不变）

#### 其余 Task

Task 1（迁移 098）/ Task 2（repo）/ Task 5（路由）/ Task 7（验证）**不受影响**，按原计划执行。

### 自审补充

- 后端不再存储 PIN 相关数据（设备端本地校验，云端无 PIN 面）✅
- 存储面仍只有 SHA-256 摘要（明文 key 不落库）✅
- 兼容性：老客户端无感（后端兜底生成）✅
