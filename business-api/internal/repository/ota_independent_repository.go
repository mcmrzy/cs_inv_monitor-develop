package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"inv-api-server/internal/model"
)

// ErrIdempotencyConflict 同幂等键但 payload/operation 不一致
var ErrIdempotencyConflict = errors.New("idempotency_key conflict")

// ErrDeviceNotFound 设备不存在
var ErrDeviceNotFound = errors.New("device not found")

// ErrFirmwareNotPublished 固件未发布
var ErrFirmwareNotPublished = errors.New("firmware not published")

// ErrDuplicateTarget 同一模块指定了多个固件
var ErrDuplicateTarget = errors.New("duplicate firmware target")

// UpdateDeviceFirmwareVersion 更新设备单模块固件版本（不写 main_version）
func (r *OTARepository) UpdateDeviceFirmwareVersion(ctx context.Context, sn, target, version string) error {
	t := strings.ToLower(strings.TrimSpace(target))
	col := ""
	switch t {
	case "arm":
		col = "firmware_arm"
	case "esp":
		col = "firmware_esp"
	case "dsp":
		col = "firmware_dsp"
	case "bms":
		col = "firmware_bms"
	default:
		return fmt.Errorf("unknown target: %s", target)
	}
	// col 已在 switch 白名单内，不存在注入
	_, err := r.db.Exec(ctx, fmt.Sprintf(
		`UPDATE devices SET %s = $2, updated_at = NOW() WHERE sn = $1`, col), sn, version)
	return err
}

// GetDeviceInfoForOTA 读取设备模块版本信息
func (r *OTARepository) GetDeviceInfoForOTA(ctx context.Context, sn string) (*DeviceInfo, error) {
	var d DeviceInfo
	var online bool
	err := r.db.QueryRow(ctx, `
		SELECT sn, COALESCE(model,''), COALESCE(firmware_arm,''), COALESCE(firmware_esp,''),
		       COALESCE(firmware_dsp,''), COALESCE(firmware_bms,''), COALESCE(main_version,''), COALESCE(status,0)=1
		FROM devices WHERE sn = $1 AND deleted_at IS NULL
	`, sn).Scan(&d.SN, &d.Model, &d.FirmwareArm, &d.FirmwareEsp, &d.FirmwareDSP, &d.FirmwareBMS, &d.MainVersion, &online)
	if err != nil {
		return nil, err
	}
	d.IsOnline = online
	return &d, nil
}

// PayloadHashForFirmwareTrigger 计算触发请求指纹
func PayloadHashForFirmwareTrigger(deviceSN string, firmwareIDs []int64, forceReason string) string {
	h := sha256.New()
	fmt.Fprintf(h, "trigger|%s|", deviceSN)
	for _, id := range firmwareIDs {
		fmt.Fprintf(h, "%d,", id)
	}
	fmt.Fprintf(h, "|%s", forceReason)
	return hex.EncodeToString(h.Sum(nil))
}

// CreateIndependentFirmwareTasks 事务式创建独立模块任务（每固件一条 task + device_upgrade）
func (r *OTARepository) CreateIndependentFirmwareTasks(ctx context.Context, userID int64, deviceSN string, firmwareIDs []int64, idempotencyKey, operation, forceReason string) ([]model.FirmwareTaskRef, error) {
	if len(firmwareIDs) == 0 {
		return nil, fmt.Errorf("firmware_ids required")
	}
	payloadHash := PayloadHashForFirmwareTrigger(deviceSN, firmwareIDs, forceReason)

	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// 幂等：尝试读取已有请求
	var existingPayload string
	var existingOp string
	var existingTaskIDs json.RawMessage
	err = tx.QueryRow(ctx, `
		SELECT payload_hash, operation, task_ids
		FROM ota_idempotency_requests
		WHERE user_id = $1 AND device_sn = $2 AND operation = $3 AND idempotency_key = $4
		FOR UPDATE
	`, userID, deviceSN, operation, idempotencyKey).Scan(&existingPayload, &existingOp, &existingTaskIDs)
	if err == nil {
		if existingPayload != payloadHash || existingOp != operation {
			return nil, ErrIdempotencyConflict
		}
		var ids []int64
		if err := json.Unmarshal(existingTaskIDs, &ids); err != nil {
			return nil, err
		}
		return r.loadTaskRefsByIDs(ctx, ids)
	}

	// 设备
	var device DeviceInfo
	err = tx.QueryRow(ctx, `
		SELECT sn, COALESCE(model,''), COALESCE(firmware_arm,''), COALESCE(firmware_esp,''),
		       COALESCE(firmware_dsp,''), COALESCE(firmware_bms,'')
		FROM devices WHERE sn = $1 AND deleted_at IS NULL FOR UPDATE
	`, deviceSN).Scan(&device.SN, &device.Model, &device.FirmwareArm, &device.FirmwareEsp, &device.FirmwareDSP, &device.FirmwareBMS)
	if err != nil {
		return nil, ErrDeviceNotFound
	}

	// 固件元数据
	type fwInfo struct {
		id      int64
		model   string
		version string
		target  string
		oldVer  string
	}
	infos := make([]fwInfo, 0, len(firmwareIDs))
	seenTarget := map[string]bool{}
	for _, fid := range firmwareIDs {
		var f model.Firmware
		err = tx.QueryRow(ctx, `
			SELECT id, model, version, COALESCE(target_chip,''), release_status
			FROM firmware_versions WHERE id = $1
		`, fid).Scan(&f.ID, &f.Model, &f.Version, &f.TargetChip, &f.ReleaseStatus)
		if err != nil {
			return nil, fmt.Errorf("firmware %d not found", fid)
		}
		if f.ReleaseStatus != model.FirmwareReleasePublished {
			return nil, ErrFirmwareNotPublished
		}
		if f.Model != device.Model {
			return nil, fmt.Errorf("firmware model mismatch: %s != %s", f.Model, device.Model)
		}
		target := strings.ToLower(strings.TrimSpace(f.TargetChip))
		if seenTarget[target] {
			return nil, ErrDuplicateTarget
		}
		seenTarget[target] = true
		old := ""
		switch target {
		case "arm":
			old = device.FirmwareArm
		case "esp":
			old = device.FirmwareEsp
		case "dsp":
			old = device.FirmwareDSP
		case "bms":
			old = device.FirmwareBMS
		}
		infos = append(infos, fwInfo{id: f.ID, model: f.Model, version: f.Version, target: target, oldVer: old})
	}

	// ESP 最后
	order := map[string]int{"bms": 0, "arm": 1, "dsp": 2, "esp": 3}
	// 稳定排序
	for i := 0; i < len(infos); i++ {
		for j := i + 1; j < len(infos); j++ {
			if order[infos[j].target] < order[infos[i].target] {
				infos[i], infos[j] = infos[j], infos[i]
			}
		}
	}

	triggeredBy := userID
	taskIDs := make([]int64, 0, len(infos))
	refs := make([]model.FirmwareTaskRef, 0, len(infos))
	source := model.OTASourceApp
	if forceReason != "" {
		source = model.OTASourceAdmin
	}

	for _, info := range infos {
		task := &model.UpgradeTask{
			Name:          fmt.Sprintf("升级 %s %s", info.target, info.version),
			TaskType:      model.TaskTypeSingle,
			Model:         info.model,
			TargetVersion: info.version,
			Status:        model.TaskStatusRunning,
			ExecuteMode:   model.ExecuteModeImmediate,
			TotalDevices:  1,
			Source:        source,
			TriggeredBy:   &triggeredBy,
			Notes:         forceReason,
		}
		fid := info.id
		task.FirmwareID = &fid
		err = tx.QueryRow(ctx, `
			INSERT INTO upgrade_tasks (name, task_type, firmware_id, package_id, model, target_version,
			    status, execute_mode, total_devices, created_by, source, triggered_by, notes)
			VALUES ($1, $2, $3, NULL, $4, $5, $6, $7, $8, $9, $10, $11, $12)
			RETURNING id
		`, task.Name, task.TaskType, task.FirmwareID, task.Model, task.TargetVersion,
			task.Status, task.ExecuteMode, task.TotalDevices, task.CreatedBy, task.Source, task.TriggeredBy, task.Notes).
			Scan(&task.ID)
		if err != nil {
			return nil, fmt.Errorf("insert task: %w", err)
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip,
			    old_version, status, progress, error_message, retry_count, pushed_by,
			    task_id, source, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, 'pending', 0, '', 0, $6, $7, $8, NOW(), NOW())
		`, deviceSN, info.id, info.version, info.target, info.oldVer, &triggeredBy, task.ID, source)
		if err != nil {
			return nil, fmt.Errorf("insert device_upgrade: %w", err)
		}

		taskIDs = append(taskIDs, task.ID)
		refs = append(refs, model.FirmwareTaskRef{
			TaskID:     task.ID,
			FirmwareID: info.id,
			TargetChip: info.target,
			Version:    info.version,
			Status:     model.TaskStatusRunning,
		})
	}

	taskIDsJSON, err := json.Marshal(taskIDs)
	if err != nil {
		return nil, err
	}
	_, err = tx.Exec(ctx, `
		INSERT INTO ota_idempotency_requests (user_id, device_sn, idempotency_key, operation, payload_hash, task_ids, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`, userID, deviceSN, idempotencyKey, operation, payloadHash, taskIDsJSON)
	if err != nil {
		return nil, fmt.Errorf("insert idempotency: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return refs, nil
}

func (r *OTARepository) loadTaskRefsByIDs(ctx context.Context, taskIDs []int64) ([]model.FirmwareTaskRef, error) {
	if len(taskIDs) == 0 {
		return []model.FirmwareTaskRef{}, nil
	}
	refs := make([]model.FirmwareTaskRef, 0, len(taskIDs))
	for _, tid := range taskIDs {
		var ref model.FirmwareTaskRef
		err := r.db.QueryRow(ctx, `
			SELECT t.id, COALESCE(t.firmware_id,0), COALESCE(f.target_chip,''), COALESCE(t.target_version,''), t.status
			FROM upgrade_tasks t
			LEFT JOIN firmware_versions f ON t.firmware_id = f.id
			WHERE t.id = $1
		`, tid).Scan(&ref.TaskID, &ref.FirmwareID, &ref.TargetChip, &ref.Version, &ref.Status)
		if err != nil {
			continue
		}
		refs = append(refs, ref)
	}
	return refs, nil
}

// ListUpgradeHistoryFiltered 共用 where builder 的历史查询
func (r *OTARepository) ListUpgradeHistoryFiltered(ctx context.Context, f model.UpgradeHistoryFilter) ([]model.DeviceUpgrade, int, error) {
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PageSize < 1 || f.PageSize > 100 {
		f.PageSize = 20
	}
	where := make([]string, 0, 6)
	args := make([]any, 0, 8)
	argN := 1
	if f.DeviceSN != "" {
		where = append(where, fmt.Sprintf("du.device_sn = $%d", argN))
		args = append(args, f.DeviceSN)
		argN++
	}
	if f.TargetChip != "" {
		where = append(where, fmt.Sprintf("du.target_chip = $%d", argN))
		args = append(args, f.TargetChip)
		argN++
	}
	if f.Status != "" {
		where = append(where, fmt.Sprintf("du.status = $%d", argN))
		args = append(args, f.Status)
		argN++
	}
	if f.StartTime != nil {
		where = append(where, fmt.Sprintf("du.created_at >= $%d", argN))
		args = append(args, f.StartTime.UTC())
		argN++
	}
	if f.EndTime != nil {
		where = append(where, fmt.Sprintf("du.created_at <= $%d", argN))
		args = append(args, f.EndTime.UTC())
		argN++
	}
	whereSQL := "TRUE"
	if len(where) > 0 {
		whereSQL = strings.Join(where, " AND ")
	}

	var total int
	countSQL := fmt.Sprintf(`SELECT COUNT(*) FROM device_upgrades du WHERE %s`, whereSQL)
	if err := r.db.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listArgs := append(append([]any{}, args...), f.PageSize, (f.Page-1)*f.PageSize)
	listSQL := fmt.Sprintf(`
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.stage,''), COALESCE(du.progress,0),
		       COALESCE(du.error_message,''), COALESCE(du.retry_count,0), du.pushed_by,
		       du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(du.task_id,0)
		FROM device_upgrades du
		WHERE %s
		ORDER BY du.created_at DESC
		LIMIT $%d OFFSET $%d
	`, whereSQL, argN, argN+1)

	rows, err := r.db.Query(ctx, listSQL, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	items := make([]model.DeviceUpgrade, 0, f.PageSize)
	for rows.Next() {
		var du model.DeviceUpgrade
		var taskID int64
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Stage, &du.Progress, &du.ErrorMessage, &du.RetryCount,
			&du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt, &taskID); err != nil {
			continue
		}
		if taskID > 0 {
			du.TaskID = &taskID
		}
		items = append(items, du)
	}
	return items, total, nil
}

// RetirePendingPackageTasks 收口未运行的旧 package 任务
func (r *OTARepository) RetirePendingPackageTasks(ctx context.Context) (int64, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE upgrade_tasks SET status = 'cancelled', completed_at = COALESCE(completed_at, NOW())
		WHERE task_type = 'package' AND status IN ('pending', 'scheduled')
	`)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// GetFirmwarePublishState 读取发布状态
func (r *OTARepository) GetFirmwarePublishState(ctx context.Context, id int64) (string, error) {
	var st string
	err := r.db.QueryRow(ctx, `SELECT release_status FROM firmware_versions WHERE id=$1`, id).Scan(&st)
	return st, err
}

// HardDeleteDraftFirmware 物理删除 draft 固件
func (r *OTARepository) HardDeleteDraftFirmware(ctx context.Context, id int64) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM firmware_versions WHERE id=$1 AND release_status='draft'`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("only draft firmware can be deleted")
	}
	return nil
}

// ParseHistoryTime 解析历史筛选时间
func ParseHistoryTime(s string) (*time.Time, error) {
	if s == "" {
		return nil, nil
	}
	layouts := []string{time.RFC3339, "2006-01-02 15:04:05", "2006-01-02T15:04:05Z07:00", "2006-01-02"}
	for _, layout := range layouts {
		if t, err := time.Parse(layout, s); err == nil {
			return &t, nil
		}
	}
	return nil, fmt.Errorf("invalid time: %s", s)
}
