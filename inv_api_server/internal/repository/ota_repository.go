package repository

import (
	"context"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type OTARepository struct {
	db *pgxpool.Pool
}

func NewOTARepository(db *pgxpool.Pool) *OTARepository {
	return &OTARepository{db: db}
}

func (r *OTARepository) CreateFirmware(ctx context.Context, f *model.Firmware) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO firmware_versions (model, target_chip, main_version, version, file_url, file_size, file_md5, file_sha256, changelog, is_force, uploaded_by, status, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,1,NOW())
		RETURNING id, created_at
	`, f.Model, f.TargetChip, f.MainVersion, f.Version, f.FileURL, f.FileSize, f.FileMD5, f.FileSHA256, f.Changelog, f.IsForce, f.UploadedBy).
		Scan(&f.ID, &f.CreatedAt)
}

func (r *OTARepository) ListFirmware(ctx context.Context, modelFilter string) ([]model.Firmware, error) {
	query := `
		SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, COALESCE(uploaded_by,0), status, created_at,
		       COALESCE(target_chip,''), COALESCE(main_version,'')
		FROM firmware_versions WHERE status = 1
	`
	args := []interface{}{}
	if modelFilter != "" {
		query += " AND model = $1"
		args = append(args, modelFilter)
	}
	query += " ORDER BY created_at DESC"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.Firmware
	for rows.Next() {
		var f model.Firmware
		if err := rows.Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
			&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
			&f.Status, &f.CreatedAt, &f.TargetChip, &f.MainVersion); err != nil {
			continue
		}
		result = append(result, f)
	}
	return result, nil
}

func (r *OTARepository) GetFirmware(ctx context.Context, id int64) (*model.Firmware, error) {
	var f model.Firmware
	err := r.db.QueryRow(ctx, `
		SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, COALESCE(uploaded_by,0), status, created_at,
		       COALESCE(target_chip,''), COALESCE(main_version,'')
		FROM firmware_versions WHERE id = $1
	`, id).Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
		&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
		&f.Status, &f.CreatedAt, &f.TargetChip, &f.MainVersion)
	return &f, err
}

func (r *OTARepository) DeleteFirmware(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "UPDATE firmware_versions SET status = 0 WHERE id = $1", id)
	return err
}

// FindExistingTask 查找同一设备+固件的已有任务（failed/pending 状态），用于复用
func (r *OTARepository) FindExistingTask(ctx context.Context, sn string, firmwareID int64) (*model.OtaTask, error) {
	t := &model.OtaTask{}
	err := r.db.QueryRow(ctx, `
		SELECT t.id, t.name, t.firmware_id, t.firmware_version, t.model, t.target_type, COALESCE(t.target_value,''),
		       t.total_count, t.success_count, t.fail_count, t.status, COALESCE(t.description,''), t.created_by,
		       COALESCE(t.push_strategy,'all_at_once'), COALESCE(t.push_percentage,100), COALESCE(t.batch_size,10),
		       t.scheduled_at, COALESCE(t.auto_rollback, FALSE), COALESCE(t.rollback_threshold,30),
		       COALESCE(t.current_batch,0), COALESCE(t.total_batches,0),
		       t.created_at, COALESCE(t.started_at, t.created_at), t.completed_at, t.updated_at
		FROM ota_tasks t
		WHERE t.firmware_id = $1 AND t.target_value = $2 AND t.status IN ('failed','pending')
		ORDER BY t.created_at DESC LIMIT 1
	`, firmwareID, sn).Scan(&t.ID, &t.Name, &t.FirmwareID, &t.FirmwareVersion, &t.Model,
		&t.TargetType, &t.TargetValue, &t.TotalCount, &t.SuccessCount, &t.FailCount,
		&t.Status, &t.Description, &t.CreatedBy, &t.PushStrategy, &t.PushPercentage,
		&t.BatchSize, &t.ScheduledAt, &t.AutoRollback, &t.RollbackThreshold,
		&t.CurrentBatch, &t.TotalBatches,
		&t.CreatedAt, &t.StartedAt, &t.CompletedAt, &t.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return t, nil
}

func (r *OTARepository) CreateTask(ctx context.Context, t *model.OtaTask) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO ota_tasks (name, firmware_id, firmware_version, model, target_type, target_value, total_count,
		                       success_count, fail_count, status, description, created_by, push_strategy, push_percentage, batch_size,
		                       scheduled_at, auto_rollback, rollback_threshold, current_batch, total_batches, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,NOW(),NOW())
		RETURNING id, created_at, updated_at
	`, t.Name, t.FirmwareID, t.FirmwareVersion, t.Model, t.TargetType, t.TargetValue,
		t.TotalCount, t.SuccessCount, t.FailCount, t.Status, t.Description, t.CreatedBy,
		t.PushStrategy, t.PushPercentage, t.BatchSize,
		t.ScheduledAt, t.AutoRollback, t.RollbackThreshold, t.CurrentBatch, t.TotalBatches).
		Scan(&t.ID, &t.CreatedAt, &t.UpdatedAt)
}

func (r *OTARepository) ListTasks(ctx context.Context, status string, page, pageSize int) ([]model.OtaTask, int, error) {
	var total int
	r.db.QueryRow(ctx, "SELECT COUNT(*) FROM ota_tasks WHERE ($1='' OR status=$1)", status).Scan(&total)

	rows, err := r.db.Query(ctx, `
		SELECT id, name, firmware_id, firmware_version, model, target_type, COALESCE(target_value,''),
		       total_count, success_count, fail_count, status, COALESCE(description,''), created_by,
		       COALESCE(push_strategy,'all_at_once'), COALESCE(push_percentage,100), COALESCE(batch_size,10),
		       scheduled_at, COALESCE(auto_rollback, FALSE), COALESCE(rollback_threshold,30),
		       COALESCE(current_batch,0), COALESCE(total_batches,0),
		       created_at, COALESCE(started_at, created_at), completed_at, updated_at
		FROM ota_tasks WHERE ($1='' OR status=$1)
		ORDER BY created_at DESC LIMIT $2 OFFSET $3
	`, status, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var tasks []model.OtaTask
	for rows.Next() {
		var t model.OtaTask
		if err := rows.Scan(&t.ID, &t.Name, &t.FirmwareID, &t.FirmwareVersion, &t.Model,
			&t.TargetType, &t.TargetValue, &t.TotalCount, &t.SuccessCount, &t.FailCount,
			&t.Status, &t.Description, &t.CreatedBy, &t.PushStrategy, &t.PushPercentage,
			&t.BatchSize, &t.ScheduledAt, &t.AutoRollback, &t.RollbackThreshold,
			&t.CurrentBatch, &t.TotalBatches,
			&t.CreatedAt, &t.StartedAt, &t.CompletedAt, &t.UpdatedAt); err != nil {
			continue
		}
		tasks = append(tasks, t)
	}
	return tasks, total, nil
}

func (r *OTARepository) GetTask(ctx context.Context, id string) (*model.OtaTask, error) {
	var t model.OtaTask
	err := r.db.QueryRow(ctx, `
		SELECT id, name, firmware_id, firmware_version, model, target_type, COALESCE(target_value,''),
		       total_count, success_count, fail_count, status, COALESCE(description,''), created_by,
		       COALESCE(push_strategy,'all_at_once'), COALESCE(push_percentage,100), COALESCE(batch_size,10),
		       scheduled_at, COALESCE(auto_rollback, FALSE), COALESCE(rollback_threshold,30),
		       COALESCE(current_batch,0), COALESCE(total_batches,0),
		       created_at, COALESCE(started_at, created_at), completed_at, updated_at
		FROM ota_tasks WHERE id = $1
	`, id).Scan(&t.ID, &t.Name, &t.FirmwareID, &t.FirmwareVersion, &t.Model,
		&t.TargetType, &t.TargetValue, &t.TotalCount, &t.SuccessCount, &t.FailCount,
		&t.Status, &t.Description, &t.CreatedBy, &t.PushStrategy, &t.PushPercentage,
		&t.BatchSize, &t.ScheduledAt, &t.AutoRollback, &t.RollbackThreshold,
		&t.CurrentBatch, &t.TotalBatches,
		&t.CreatedAt, &t.StartedAt, &t.CompletedAt, &t.UpdatedAt)
	return &t, err
}

// UpdateTask 更新任务的多个字段（用于复用已有任务）
func (r *OTARepository) UpdateTask(ctx context.Context, t *model.OtaTask) error {
	_, err := r.db.Exec(ctx, `
		UPDATE ota_tasks SET
			status = $1, fail_count = $2, success_count = $3,
			completed_at = $4, updated_at = NOW()
		WHERE id = $5
	`, t.Status, t.FailCount, t.SuccessCount, t.CompletedAt, t.ID)
	return err
}

func (r *OTARepository) UpdateTaskStatus(ctx context.Context, id string, status string) error {
	now := time.Now()
	_, err := r.db.Exec(ctx, `
		UPDATE ota_tasks SET status = $1::varchar, updated_at = $3,
		    started_at = CASE WHEN $1::varchar = 'running' AND started_at IS NULL THEN $3 ELSE started_at END,
		    completed_at = CASE WHEN $1::varchar IN ('completed','failed') THEN $3 ELSE NULL END
		WHERE id = $2
	`, status, id, now)
	return err
}

// DeleteTask 删除任务及其关联的设备记录
func (r *OTARepository) DeleteTask(ctx context.Context, id string) error {
	// 先删除关联的设备记录
	_, err := r.db.Exec(ctx, "DELETE FROM ota_task_devices WHERE task_id = $1", id)
	if err != nil {
		return err
	}
	// 删除任务
	_, err = r.db.Exec(ctx, "DELETE FROM ota_tasks WHERE id = $1", id)
	return err
}

func (r *OTARepository) UpsertTaskDevice(ctx context.Context, td *model.OtaTaskDevice) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO ota_task_devices (task_id, device_sn, status, progress, error_message, old_version, new_version, completed_at, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW())
		ON CONFLICT (task_id, device_sn) DO UPDATE SET
		    status = $3, progress = $4, error_message = $5,
		    old_version = COALESCE(NULLIF($6,''), ota_task_devices.old_version),
		    new_version = COALESCE(NULLIF($7,''), ota_task_devices.new_version),
		    completed_at = CASE WHEN $3 IN ('success','failed') THEN NOW() ELSE NULL END
	`, td.TaskID, td.DeviceSN, td.Status, td.Progress, td.ErrorMessage, td.OldVersion, td.NewVersion, td.CompletedAt)
	return err
}

func (r *OTARepository) ListTaskDevices(ctx context.Context, taskID string) ([]model.OtaTaskDevice, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, task_id, device_sn,
		       status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(old_version,''), COALESCE(new_version,''),
		       completed_at, created_at
		FROM ota_task_devices WHERE task_id = $1 ORDER BY id
	`, taskID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []model.OtaTaskDevice
	for rows.Next() {
		var d model.OtaTaskDevice
		if err := rows.Scan(&d.ID, &d.TaskID, &d.DeviceSN,
			&d.Status, &d.Progress, &d.ErrorMessage,
			&d.OldVersion, &d.NewVersion,
			&d.CompletedAt, &d.CreatedAt); err != nil {
			continue
		}
		devices = append(devices, d)
	}
	return devices, nil
}

// GetPendingOTATaskForDevice 获取设备待处理的OTA任务（已通知但未执行）
func (r *OTARepository) GetPendingOTATaskForDevice(ctx context.Context, sn string) (*model.OtaTask, *model.Firmware, error) {
	var task model.OtaTask
	var fw model.Firmware
	err := r.db.QueryRow(ctx, `
		SELECT t.id, t.name, t.firmware_id, t.firmware_version, t.model, t.status,
		       f.id, f.model, f.version, f.file_url, COALESCE(f.file_size,0), COALESCE(f.file_md5,''),
		       COALESCE(f.changelog,''), f.is_force
		FROM ota_task_devices td
		JOIN ota_tasks t ON td.task_id = t.id
		JOIN firmware_versions f ON t.firmware_id = f.id
		WHERE td.device_sn = $1 
		  AND td.status = 'notified'
		  AND t.status IN ('notified', 'notifying')
		ORDER BY t.created_at DESC
		LIMIT 1
	`, sn).Scan(
		&task.ID, &task.Name, &task.FirmwareID, &task.FirmwareVersion, &task.Model, &task.Status,
		&fw.ID, &fw.Model, &fw.Version, &fw.FileURL, &fw.FileSize, &fw.FileMD5,
		&fw.Changelog, &fw.IsForce,
	)
	if err != nil {
		return nil, nil, err
	}
	return &task, &fw, nil
}

// DeviceInfo 设备基本信息
type DeviceInfo struct {
	SN              string `json:"sn"`
	Model           string `json:"model"`
	FirmwareVersion string `json:"firmware_version"`
}

// GetDeviceBySN 根据SN获取设备信息
func (r *OTARepository) GetDeviceBySN(ctx context.Context, sn string) (*DeviceInfo, error) {
	var d DeviceInfo
	err := r.db.QueryRow(ctx, `
		SELECT sn, COALESCE(model,''), COALESCE(firmware_version,'')
		FROM devices WHERE sn = $1
	`, sn).Scan(&d.SN, &d.Model, &d.FirmwareVersion)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// GetLatestFirmware 获取指定型号的最新固件
func (r *OTARepository) GetLatestFirmware(ctx context.Context, deviceModel string, targetChip string) (*model.Firmware, error) {
	var f model.Firmware
	var err error
	if targetChip != "" {
		err = r.db.QueryRow(ctx, `
			SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
			       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, COALESCE(uploaded_by,0), status, created_at,
			       COALESCE(target_chip,''), COALESCE(main_version,'')
			FROM firmware_versions
			WHERE target_chip = $1 AND model = $2 AND status = 1
			ORDER BY created_at DESC
			LIMIT 1
		`, targetChip, deviceModel).Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
			&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
			&f.Status, &f.CreatedAt, &f.TargetChip, &f.MainVersion)
	} else {
		err = r.db.QueryRow(ctx, `
			SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
			       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, COALESCE(uploaded_by,0), status, created_at,
			       COALESCE(target_chip,''), COALESCE(main_version,'')
			FROM firmware_versions
			WHERE model = $1 AND status = 1
			ORDER BY created_at DESC
			LIMIT 1
		`, deviceModel).Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
			&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
			&f.Status, &f.CreatedAt, &f.TargetChip, &f.MainVersion)
	}
	if err != nil {
		return nil, err
	}
	return &f, nil
}

// GetLatestMainVersion 获取指定芯片的最大主版本号
func (r *OTARepository) GetLatestMainVersion(ctx context.Context, targetChip string) (string, error) {
	var mainVersion string
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(MAX(main_version), '') 
		FROM firmware_versions 
		WHERE target_chip = $1 AND status = 1
	`, targetChip).Scan(&mainVersion)
	if err != nil {
		return "", err
	}
	return mainVersion, nil
}

// GetLatestTaskDevice 获取设备最新的OTA任务设备记录
func (r *OTARepository) GetLatestTaskDevice(ctx context.Context, sn string) (*model.OtaTaskDevice, error) {
	var d model.OtaTaskDevice
	err := r.db.QueryRow(ctx, `
		SELECT id, task_id, device_sn,
		       status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(old_version,''), COALESCE(new_version,''),
		       completed_at, created_at
		FROM ota_task_devices
		WHERE device_sn = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, sn).Scan(&d.ID, &d.TaskID, &d.DeviceSN,
		&d.Status, &d.Progress, &d.ErrorMessage,
		&d.OldVersion, &d.NewVersion,
		&d.CompletedAt, &d.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// GetDeviceOTAHistory 获取设备OTA历史
func (r *OTARepository) GetDeviceOTAHistory(ctx context.Context, sn string, page, pageSize int) ([]model.OtaTaskDevice, int, error) {
	var total int
	r.db.QueryRow(ctx, "SELECT COUNT(*) FROM ota_task_devices WHERE device_sn = $1", sn).Scan(&total)

	rows, err := r.db.Query(ctx, `
		SELECT id, task_id, device_sn,
		       status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(old_version,''), COALESCE(new_version,''),
		       completed_at, created_at
		FROM ota_task_devices
		WHERE device_sn = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, sn, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var devices []model.OtaTaskDevice
	for rows.Next() {
		var d model.OtaTaskDevice
		if err := rows.Scan(&d.ID, &d.TaskID, &d.DeviceSN,
			&d.Status, &d.Progress, &d.ErrorMessage,
			&d.OldVersion, &d.NewVersion,
			&d.CompletedAt, &d.CreatedAt); err != nil {
			continue
		}
		devices = append(devices, d)
	}
	return devices, total, nil
}

// ========== App版本管理 ==========

// GetLatestAppVersion 获取指定平台的最新App版本
func (r *OTARepository) GetLatestAppVersion(ctx context.Context, platform string) (*model.AppVersion, error) {
	var v model.AppVersion
	err := r.db.QueryRow(ctx, `
		SELECT id, platform, version_code, version_name, 
		       COALESCE(download_url,''), COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(changelog,''), is_force, COALESCE(min_supported_version,0),
		       COALESCE(rollout_percentage,100), COALESCE(is_rolled_back,FALSE), rolled_back_at,
		       status, created_at
		FROM app_versions
		WHERE platform = $1 AND status = 1 AND COALESCE(is_rolled_back, FALSE) = FALSE
		ORDER BY version_code DESC
		LIMIT 1
	`, platform).Scan(&v.ID, &v.Platform, &v.VersionCode, &v.VersionName,
		&v.DownloadURL, &v.FileSize, &v.FileMD5,
		&v.Changelog, &v.IsForce, &v.MinSupportedVersion,
		&v.RolloutPercentage, &v.IsRolledBack, &v.RolledBackAt,
		&v.Status, &v.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// CreateAppVersion 创建App版本
func (r *OTARepository) CreateAppVersion(ctx context.Context, v *model.AppVersion) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO app_versions (platform, version_code, version_name, download_url, file_size, file_md5, changelog, is_force, min_supported_version, rollout_percentage, status, created_by)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,1,$11)
		RETURNING id, created_at
	`, v.Platform, v.VersionCode, v.VersionName, v.DownloadURL, v.FileSize, v.FileMD5,
		v.Changelog, v.IsForce, v.MinSupportedVersion, v.RolloutPercentage, v.CreatedBy).
		Scan(&v.ID, &v.CreatedAt)
}

// ListAppVersions 列出所有App版本
func (r *OTARepository) ListAppVersions(ctx context.Context, platform string) ([]model.AppVersion, error) {
	query := `
		SELECT id, platform, version_code, version_name, 
		       COALESCE(download_url,''), COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(changelog,''), is_force, COALESCE(min_supported_version,0),
		       COALESCE(rollout_percentage,100), COALESCE(is_rolled_back,FALSE), rolled_back_at,
		       status, created_at
		FROM app_versions WHERE status = 1
	`
	args := []interface{}{}
	if platform != "" {
		query += " AND platform = $1"
		args = append(args, platform)
	}
	query += " ORDER BY version_code DESC"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.AppVersion
	for rows.Next() {
		var v model.AppVersion
		if err := rows.Scan(&v.ID, &v.Platform, &v.VersionCode, &v.VersionName,
			&v.DownloadURL, &v.FileSize, &v.FileMD5,
			&v.Changelog, &v.IsForce, &v.MinSupportedVersion,
			&v.RolloutPercentage, &v.IsRolledBack, &v.RolledBackAt,
			&v.Status, &v.CreatedAt); err != nil {
			continue
		}
		result = append(result, v)
	}
	return result, nil
}

// UpdateAppVersionRollout 更新App版本灰度比例
func (r *OTARepository) UpdateAppVersionRollout(ctx context.Context, id int64, percentage int) error {
	_, err := r.db.Exec(ctx, "UPDATE app_versions SET rollout_percentage = $1, updated_at = NOW() WHERE id = $2", percentage, id)
	return err
}

// RollbackAppVersion 回滚App版本
func (r *OTARepository) RollbackAppVersion(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "UPDATE app_versions SET is_rolled_back = TRUE, rolled_back_at = NOW(), rollout_percentage = 0, updated_at = NOW() WHERE id = $1", id)
	return err
}

// RestoreAppVersion 恢复已回滚的App版本
func (r *OTARepository) RestoreAppVersion(ctx context.Context, id int64, percentage int) error {
	_, err := r.db.Exec(ctx, "UPDATE app_versions SET is_rolled_back = FALSE, rolled_back_at = NULL, rollout_percentage = $1, updated_at = NOW() WHERE id = $2", percentage, id)
	return err
}

// DeleteAppVersion 删除App版本（软删除）
func (r *OTARepository) DeleteAppVersion(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "UPDATE app_versions SET status = 0 WHERE id = $1", id)
	return err
}
