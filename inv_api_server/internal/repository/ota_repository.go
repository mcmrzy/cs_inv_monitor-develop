package repository

import (
	"context"
	"fmt"
	"strings"
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

// UpsertDeviceUpgrade UPSERT: 同设备+同固件+同升级包=一条记录
func (r *OTARepository) UpsertDeviceUpgrade(ctx context.Context, du *model.DeviceUpgrade) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip,
		    old_version, status, progress, error_message, retry_count, pushed_by, upgrade_package_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())
		ON CONFLICT (device_sn, firmware_id, COALESCE(upgrade_package_id, 0)) DO UPDATE SET
		    status = CASE
		        WHEN device_upgrades.status = 'success' THEN device_upgrades.status
		        WHEN $6 = 'pending' AND device_upgrades.status = 'failed' THEN 'pending'
		        ELSE $6
		    END,
		    firmware_version = $3,
		    old_version = CASE WHEN device_upgrades.old_version = '' THEN $5 ELSE device_upgrades.old_version END,
		    progress = $7,
		    error_message = CASE WHEN $6 = 'failed' THEN $8 ELSE device_upgrades.error_message END,
		    retry_count = CASE WHEN $6 = 'pending' AND device_upgrades.status = 'failed'
		                  THEN device_upgrades.retry_count + 1 ELSE device_upgrades.retry_count END,
		    pushed_by = COALESCE($10, device_upgrades.pushed_by),
		    started_at = CASE WHEN $6 IN ('downloading','upgrading') AND device_upgrades.started_at IS NULL
		                THEN NOW() ELSE device_upgrades.started_at END,
		    completed_at = CASE WHEN $6 IN ('success','failed') THEN NOW() ELSE device_upgrades.completed_at END,
		    updated_at = NOW()
		RETURNING id, created_at, updated_at
	`, du.DeviceSN, du.FirmwareID, du.FirmwareVersion, du.TargetChip,
		du.OldVersion, du.Status, du.Progress, du.ErrorMessage, du.RetryCount, du.PushedBy, du.UpgradePackageID).
		Scan(&du.ID, &du.CreatedAt, &du.UpdatedAt)
}

// GetPendingUpgradeForDevice 获取设备待执行的升级（管理员推送后，设备CheckUpdate用）
func (r *OTARepository) GetPendingUpgradeForDevice(ctx context.Context, sn string) (*model.DeviceUpgrade, *model.Firmware, error) {
	var du model.DeviceUpgrade
	var fw model.Firmware
	err := r.db.QueryRow(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       f.id, f.model, f.version, f.file_url, COALESCE(f.file_size,0), COALESCE(f.file_md5,''),
		       COALESCE(f.file_sha256,''), COALESCE(f.changelog,''), f.is_force, COALESCE(f.target_chip,''), COALESCE(f.main_version,'')
		FROM device_upgrades du
		JOIN firmware_versions f ON du.firmware_id = f.id
		WHERE du.device_sn = $1 AND du.status = 'pending'
		ORDER BY du.updated_at DESC
		LIMIT 1
	`, sn).Scan(
		&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
		&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
		&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
		&fw.ID, &fw.Model, &fw.Version, &fw.FileURL, &fw.FileSize, &fw.FileMD5,
		&fw.FileSHA256, &fw.Changelog, &fw.IsForce, &fw.TargetChip, &fw.MainVersion,
	)
	if err != nil {
		return nil, nil, err
	}
	return &du, &fw, nil
}

// UpdateUpgradeStatus 更新升级状态（设备上报进度用）
func (r *OTARepository) UpdateUpgradeStatus(ctx context.Context, deviceSN string, status string, progress int, errMsg string) (int64, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE device_upgrades SET
			status = $2::varchar,
			progress = $3,
			error_message = CASE WHEN $2::varchar = 'failed' THEN $4 ELSE error_message END,
			started_at = CASE WHEN started_at IS NULL AND $2::varchar IN ('downloading','upgrading') THEN NOW() ELSE started_at END,
			completed_at = CASE WHEN $2::varchar IN ('success', 'failed') THEN NOW() ELSE completed_at END,
			updated_at = NOW()
		WHERE device_sn = $1 AND status NOT IN ('success', 'failed', 'cancelled')
	`, deviceSN, status, progress, errMsg)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// ListUpgradesByFirmware 按固件分组聚合查询（管理后台Dashboard）
func (r *OTARepository) ListUpgradesByFirmware(ctx context.Context, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	var total int
	r.db.QueryRow(ctx, `SELECT COUNT(DISTINCT firmware_id) FROM device_upgrades`).Scan(&total)

	rows, err := r.db.Query(ctx, `
		SELECT 
		    du.firmware_id,
		    du.firmware_version,
		    COALESCE(f.model,'') AS device_model,
		    COALESCE(f.target_chip,'') AS target_chip,
		    COUNT(*) AS total_devices,
		    COUNT(*) FILTER (WHERE du.status = 'success') AS success_count,
		    COUNT(*) FILTER (WHERE du.status = 'failed') AS failed_count,
		    COUNT(*) FILTER (WHERE du.status IN ('pending','downloading','upgrading')) AS pending_count,
		    MAX(du.updated_at) AS last_updated
		FROM device_upgrades du
		JOIN firmware_versions f ON du.firmware_id = f.id
		GROUP BY du.firmware_id, du.firmware_version, f.model, f.target_chip
		ORDER BY MAX(du.updated_at) DESC
		LIMIT $1 OFFSET $2
	`, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		var lastUpdated time.Time
		if err := rows.Scan(&du.FirmwareID, &du.FirmwareVersion, &du.DeviceModel, &du.TargetChip,
			&du.TotalDevices, &du.SuccessCount, &du.FailedCount, &du.PendingCount, &lastUpdated); err != nil {
			continue
		}
		result = append(result, du)
	}
	return result, total, nil
}

// ListUpgradesByFirmwareID 获取指定固件的所有设备升级详情（含设备当前芯片版本）
func (r *OTARepository) ListUpgradesByFirmwareID(ctx context.Context, firmwareID int64) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(dev.firmware_arm,'') AS current_arm_version,
		       COALESCE(dev.firmware_esp,'') AS current_esp_version,
		       COALESCE(dev.firmware_dsp,'') AS current_dsp_version,
		       COALESCE(dev.firmware_bms,'') AS current_bms_version
		FROM device_upgrades du
		LEFT JOIN devices dev ON du.device_sn = dev.sn
		WHERE du.firmware_id = $1
		ORDER BY du.updated_at DESC
	`, firmwareID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&du.CurrentArmVersion, &du.CurrentEspVersion, &du.CurrentDspVersion, &du.CurrentBmsVersion); err != nil {
			continue
		}
		result = append(result, du)
	}
	return result, nil
}

// DeleteUpgradesByFirmwareID 删除指定固件的所有设备升级记录
func (r *OTARepository) DeleteUpgradesByFirmwareID(ctx context.Context, firmwareID int64) error {
	_, err := r.db.Exec(ctx, "DELETE FROM device_upgrades WHERE firmware_id = $1", firmwareID)
	return err
}

// GetDeviceUpgradeHistory 获取指定设备的升级历史（分页）
func (r *OTARepository) GetDeviceUpgradeHistory(ctx context.Context, deviceSN string, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	var total int
	r.db.QueryRow(ctx, "SELECT COUNT(*) FROM device_upgrades WHERE device_sn = $1", deviceSN).Scan(&total)

	rows, err := r.db.Query(ctx, `
		SELECT id, device_sn, firmware_id, firmware_version, COALESCE(target_chip,''),
		       COALESCE(old_version,''), status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(retry_count,0), pushed_by, started_at, completed_at, created_at, updated_at
		FROM device_upgrades
		WHERE device_sn = $1
		ORDER BY updated_at DESC
		LIMIT $2 OFFSET $3
	`, deviceSN, pageSize, (page-1)*pageSize)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt); err != nil {
			continue
		}
		result = append(result, du)
	}
	return result, total, nil
}

// RetryFailedUpgrades 重试失败的升级（批量重置为pending）
func (r *OTARepository) RetryFailedUpgrades(ctx context.Context, firmwareID int64, deviceSNs []string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_upgrades SET
		    status = 'pending',
		    progress = 0,
		    error_message = '',
		    retry_count = retry_count + 1,
		    started_at = NULL,
		    completed_at = NULL,
		    updated_at = NOW()
		WHERE firmware_id = $1 AND device_sn = ANY($2) AND status = 'failed'
	`, firmwareID, deviceSNs)
	return err
}

// CancelUpgrade 取消待执行的升级
func (r *OTARepository) CancelUpgrade(ctx context.Context, deviceSN string, firmwareID int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_upgrades SET status = 'cancelled', completed_at = NOW(), updated_at = NOW()
		WHERE device_sn = $1 AND firmware_id = $2 AND status = 'pending'
	`, deviceSN, firmwareID)
	return err
}

// GetDeviceUpgrade 获取指定设备+固件的升级记录
func (r *OTARepository) GetDeviceUpgrade(ctx context.Context, deviceSN string, firmwareID int64) (*model.DeviceUpgrade, error) {
	var du model.DeviceUpgrade
	err := r.db.QueryRow(ctx, `
		SELECT id, device_sn, firmware_id, firmware_version, COALESCE(target_chip,''),
		       COALESCE(old_version,''), status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(retry_count,0), pushed_by, started_at, completed_at, created_at, updated_at
		FROM device_upgrades
		WHERE device_sn = $1 AND firmware_id = $2
	`, deviceSN, firmwareID).Scan(
		&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
		&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
		&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &du, nil
}

// GetLatestTaskDevice 保留兼容，查询 device_upgrades
func (r *OTARepository) GetLatestTaskDevice(ctx context.Context, sn string) (*model.DeviceUpgrade, error) {
	return r.GetDeviceUpgradeBySN(ctx, sn)
}

// GetDeviceUpgradeBySN 获取设备最新的升级记录
func (r *OTARepository) GetDeviceUpgradeBySN(ctx context.Context, sn string) (*model.DeviceUpgrade, error) {
	var du model.DeviceUpgrade
	err := r.db.QueryRow(ctx, `
		SELECT id, device_sn, firmware_id, firmware_version, COALESCE(target_chip,''),
		       COALESCE(old_version,''), status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(retry_count,0), pushed_by, started_at, completed_at, created_at, updated_at
		FROM device_upgrades
		WHERE device_sn = $1
		ORDER BY updated_at DESC
		LIMIT 1
	`, sn).Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
		&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
		&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &du, nil
}

// GetDeviceOTAHistory 兼容旧接口，查询 device_upgrades
func (r *OTARepository) GetDeviceOTAHistory(ctx context.Context, sn string, page, pageSize int) ([]model.DeviceUpgrade, int, error) {
	return r.GetDeviceUpgradeHistory(ctx, sn, page, pageSize)
}

// DeviceInfo 设备基本信息
type DeviceInfo struct {
	SN            string `json:"sn"`
	Model         string `json:"model"`
	FirmwareArm   string `json:"firmware_arm"`
	FirmwareEsp   string `json:"firmware_esp"`
	FirmwareDSP   string `json:"firmware_dsp"`
	FirmwareBMS   string `json:"firmware_bms"`
	MainVersion   string `json:"main_version"`
}

// VersionSummary 生成合并主版本号，如 "V1.2.3.20240510-V1.2.0.20260629"
func (d *DeviceInfo) VersionSummary() string {
	parts := []string{}
	if d.FirmwareArm != "" {
		parts = append(parts, d.FirmwareArm)
	}
	if d.FirmwareEsp != "" {
		parts = append(parts, d.FirmwareEsp)
	}
	if d.FirmwareDSP != "" {
		parts = append(parts, d.FirmwareDSP)
	}
	if d.FirmwareBMS != "" {
		parts = append(parts, d.FirmwareBMS)
	}
	if len(parts) == 0 {
		return ""
	}
	return strings.Join(parts, "-")
}

// ChipVersions 返回各芯片当前版本的结构化 map
func (d *DeviceInfo) ChipVersions() map[string]string {
	m := map[string]string{}
	if d.FirmwareArm != "" {
		m["arm"] = d.FirmwareArm
	}
	if d.FirmwareEsp != "" {
		m["esp"] = d.FirmwareEsp
	}
	if d.FirmwareDSP != "" {
		m["dsp"] = d.FirmwareDSP
	}
	if d.FirmwareBMS != "" {
		m["bms"] = d.FirmwareBMS
	}
	return m
}

// GetDeviceBySN 根据SN获取设备信息
func (r *OTARepository) GetDeviceBySN(ctx context.Context, sn string) (*DeviceInfo, error) {
	var d DeviceInfo
	err := r.db.QueryRow(ctx, `
		SELECT sn, COALESCE(model,''), COALESCE(firmware_arm,''), COALESCE(firmware_esp,''),
		       COALESCE(firmware_dsp,''), COALESCE(firmware_bms,''), COALESCE(main_version,'')
		FROM devices WHERE sn = $1
	`, sn).Scan(&d.SN, &d.Model, &d.FirmwareArm, &d.FirmwareEsp, &d.FirmwareDSP, &d.FirmwareBMS, &d.MainVersion)
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// CheckDeviceOwnership 检查设备是否属于指定用户
func (r *OTARepository) CheckDeviceOwnership(ctx context.Context, sn string, userID int64) (bool, error) {
	var deviceUserID int64
	err := r.db.QueryRow(ctx, `SELECT COALESCE(user_id, 0) FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn).Scan(&deviceUserID)
	if err != nil {
		return false, err
	}
	if deviceUserID == userID {
		return true, nil
	}
	// 同时检查 user_device_rel 关联表
	var count int
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM user_device_rel WHERE user_id = $1 AND device_sn = $2`, userID, sn).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
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

// ========== 升级包管理 ==========

// CreateUpgradePackage 创建升级包（事务）
func (r *OTARepository) CreateUpgradePackage(ctx context.Context, pkg *model.UpgradePackage) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	err = tx.QueryRow(ctx, `
		INSERT INTO upgrade_packages (model, main_version, changelog, is_force, created_by, status)
		VALUES ($1, $2, $3, $4, $5, 1)
		RETURNING id, created_at, updated_at
	`, pkg.Model, pkg.MainVersion, pkg.Changelog, pkg.IsForce, pkg.CreatedBy).
		Scan(&pkg.ID, &pkg.CreatedAt, &pkg.UpdatedAt)
	if err != nil {
		return err
	}

	for i := range pkg.Items {
		pkg.Items[i].PackageID = pkg.ID
		err = tx.QueryRow(ctx, `
			INSERT INTO upgrade_package_items (package_id, firmware_id, target_chip, firmware_version)
			VALUES ($1, $2, $3, $4)
			RETURNING id
		`, pkg.ID, pkg.Items[i].FirmwareID, pkg.Items[i].TargetChip, pkg.Items[i].FirmwareVersion).
			Scan(&pkg.Items[i].ID)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// GetUpgradePackage 查询升级包详情（含 items）
func (r *OTARepository) GetUpgradePackage(ctx context.Context, id int64) (*model.UpgradePackage, error) {
	var pkg model.UpgradePackage
	err := r.db.QueryRow(ctx, `
		SELECT id, model, main_version, COALESCE(changelog,''), is_force, status,
		       COALESCE(created_by,0), created_at, updated_at
		FROM upgrade_packages WHERE id = $1 AND status = 1
	`, id).Scan(&pkg.ID, &pkg.Model, &pkg.MainVersion, &pkg.Changelog, &pkg.IsForce,
		&pkg.Status, &pkg.CreatedBy, &pkg.CreatedAt, &pkg.UpdatedAt)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(ctx, `
		SELECT upi.id, upi.package_id, upi.firmware_id, upi.target_chip, upi.firmware_version,
		       COALESCE(f.file_url,''), COALESCE(f.file_size,0), COALESCE(f.file_md5,''), COALESCE(f.file_sha256,'')
		FROM upgrade_package_items upi
		JOIN firmware_versions f ON upi.firmware_id = f.id
		WHERE upi.package_id = $1
		ORDER BY upi.target_chip
	`, id)
	if err != nil {
		return &pkg, nil
	}
	defer rows.Close()

	for rows.Next() {
		var item model.UpgradePackageItem
		if err := rows.Scan(&item.ID, &item.PackageID, &item.FirmwareID, &item.TargetChip,
			&item.FirmwareVersion, &item.FileURL, &item.FileSize, &item.FileMD5, &item.FileSHA256); err != nil {
			continue
		}
		pkg.Items = append(pkg.Items, item)
	}
	return &pkg, nil
}

// ListUpgradePackages 升级包列表
func (r *OTARepository) ListUpgradePackages(ctx context.Context, modelFilter string) ([]model.UpgradePackage, error) {
	query := `
		SELECT id, model, main_version, COALESCE(changelog,''), is_force, status,
		       COALESCE(created_by,0), created_at, updated_at
		FROM upgrade_packages WHERE status = 1
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

	var result []model.UpgradePackage
	for rows.Next() {
		var pkg model.UpgradePackage
		if err := rows.Scan(&pkg.ID, &pkg.Model, &pkg.MainVersion, &pkg.Changelog, &pkg.IsForce,
			&pkg.Status, &pkg.CreatedBy, &pkg.CreatedAt, &pkg.UpdatedAt); err != nil {
			continue
		}
		result = append(result, pkg)
	}

	// 批量查询 items
	for i := range result {
		pkgRows, err := r.db.Query(ctx, `
			SELECT upi.id, upi.package_id, upi.firmware_id, upi.target_chip, upi.firmware_version,
			       COALESCE(f.file_url,''), COALESCE(f.file_size,0), COALESCE(f.file_md5,''), COALESCE(f.file_sha256,'')
			FROM upgrade_package_items upi
			JOIN firmware_versions f ON upi.firmware_id = f.id
			WHERE upi.package_id = $1 ORDER BY upi.target_chip
		`, result[i].ID)
		if err == nil {
			for pkgRows.Next() {
				var item model.UpgradePackageItem
				if err := pkgRows.Scan(&item.ID, &item.PackageID, &item.FirmwareID, &item.TargetChip,
					&item.FirmwareVersion, &item.FileURL, &item.FileSize, &item.FileMD5, &item.FileSHA256); err == nil {
					result[i].Items = append(result[i].Items, item)
				}
			}
			pkgRows.Close()
		}
	}
	return result, nil
}

// DeleteUpgradePackage 软删除升级包
func (r *OTARepository) DeleteUpgradePackage(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "UPDATE upgrade_packages SET status = 0, updated_at = NOW() WHERE id = $1", id)
	return err
}

// GetLatestPackageVersion 获取指定型号的最新升级包主版本号
func (r *OTARepository) GetLatestPackageVersion(ctx context.Context, model string) (string, error) {
	var mainVersion string
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(main_version, '') FROM upgrade_packages
		WHERE model = $1 AND status = 1
		ORDER BY created_at DESC LIMIT 1
	`, model).Scan(&mainVersion)
	if err != nil {
		return "", err
	}
	return mainVersion, nil
}

// UpsertPackageUpgrade 升级包模式 UPSERT device_upgrades
func (r *OTARepository) UpsertPackageUpgrade(ctx context.Context, du *model.DeviceUpgrade) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip,
		    old_version, status, progress, error_message, retry_count, pushed_by, upgrade_package_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())
		ON CONFLICT (device_sn, firmware_id, COALESCE(upgrade_package_id, 0)) DO UPDATE SET
		    status = CASE
		        WHEN device_upgrades.status = 'success' THEN device_upgrades.status
		        WHEN $6 = 'pending' AND device_upgrades.status = 'failed' THEN 'pending'
		        ELSE $6
		    END,
		    firmware_version = $3,
		    old_version = CASE WHEN device_upgrades.old_version = '' THEN $5 ELSE device_upgrades.old_version END,
		    progress = $7,
		    error_message = CASE WHEN $6 = 'failed' THEN $8 ELSE device_upgrades.error_message END,
		    retry_count = CASE WHEN $6 = 'pending' AND device_upgrades.status = 'failed'
		                  THEN device_upgrades.retry_count + 1 ELSE device_upgrades.retry_count END,
		    pushed_by = COALESCE($10, device_upgrades.pushed_by),
		    started_at = CASE WHEN $6 IN ('downloading','upgrading') AND device_upgrades.started_at IS NULL
		                THEN NOW() ELSE device_upgrades.started_at END,
		    completed_at = CASE WHEN $6 IN ('success','failed') THEN NOW() ELSE device_upgrades.completed_at END,
		    updated_at = NOW()
		RETURNING id, created_at, updated_at
	`, du.DeviceSN, du.FirmwareID, du.FirmwareVersion, du.TargetChip,
		du.OldVersion, du.Status, du.Progress, du.ErrorMessage, du.RetryCount, du.PushedBy, du.UpgradePackageID).
		Scan(&du.ID, &du.CreatedAt, &du.UpdatedAt)
}

// GetPendingPackageUpgradeForDevice 获取设备待执行的升级包升级（返回所有芯片的升级记录）
func (r *OTARepository) GetPendingPackageUpgradeForDevice(ctx context.Context, sn string) ([]model.DeviceUpgrade, *model.UpgradePackage, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(du.upgrade_package_id, 0),
		       COALESCE(up.main_version,''), COALESCE(up.changelog,''), COALESCE(up.is_force,FALSE)
		FROM device_upgrades du
		LEFT JOIN upgrade_packages up ON du.upgrade_package_id = up.id
		WHERE du.device_sn = $1 AND du.status = 'pending' AND du.upgrade_package_id IS NOT NULL
		ORDER BY du.updated_at DESC
	`, sn)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	var upgrades []model.DeviceUpgrade
	var pkg model.UpgradePackage
	for rows.Next() {
		var du model.DeviceUpgrade
		var pkgID int64
		var mainVer, changelog string
		var isForce bool
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&pkgID, &mainVer, &changelog, &isForce); err != nil {
			continue
		}
		du.UpgradePackageID = &pkgID
		du.PackageMainVersion = mainVer
		pkg.ID = pkgID
		pkg.MainVersion = mainVer
		pkg.Changelog = changelog
		pkg.IsForce = isForce
		upgrades = append(upgrades, du)
	}
	if len(upgrades) == 0 {
		return nil, nil, nil
	}
	return upgrades, &pkg, nil
}

// UpdateDeviceMainVersion 更新设备主版本号
func (r *OTARepository) UpdateDeviceMainVersion(ctx context.Context, sn string, mainVersion string) error {
	_, err := r.db.Exec(ctx, "UPDATE devices SET main_version = $1, updated_at = NOW() WHERE sn = $2", mainVersion, sn)
	return err
}

// GetSuccessfulUpgradesByPackage 获取升级包下所有成功升级的记录
func (r *OTARepository) GetSuccessfulUpgradesByPackage(ctx context.Context, packageID int64) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(du.upgrade_package_id, 0)
		FROM device_upgrades du
		WHERE du.upgrade_package_id = $1 AND du.status = 'success'
		ORDER BY du.updated_at DESC
	`, packageID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var upgrades []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		var pkgID int64
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&pkgID); err != nil {
			continue
		}
		du.UpgradePackageID = &pkgID
		upgrades = append(upgrades, du)
	}
	return upgrades, nil
}

// FindFirmwareByVersion 按 model+version+target_chip 查找固件
func (r *OTARepository) FindFirmwareByVersion(ctx context.Context, deviceModel, version, targetChip string) (*model.Firmware, error) {
	var f model.Firmware
	err := r.db.QueryRow(ctx, `
		SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, COALESCE(uploaded_by,0), status, created_at,
		       COALESCE(target_chip,''), COALESCE(main_version,'')
		FROM firmware_versions
		WHERE model = $1 AND version = $2 AND target_chip = $3 AND status = 1
		LIMIT 1
	`, deviceModel, version, targetChip).Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
		&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
		&f.Status, &f.CreatedAt, &f.TargetChip, &f.MainVersion)
	if err != nil {
		return nil, err
	}
	return &f, nil
}

// GetPackageUpgradesByPackageID 获取指定升级包的所有设备升级记录
func (r *OTARepository) GetPackageUpgradesByPackageID(ctx context.Context, packageID int64) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(du.upgrade_package_id, 0)
		FROM device_upgrades du
		WHERE du.upgrade_package_id = $1
		ORDER BY du.device_sn, du.target_chip
	`, packageID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		var pkgID int64
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&pkgID); err != nil {
			continue
		}
		du.UpgradePackageID = &pkgID
		result = append(result, du)
	}
	return result, nil
}

// GetUpgradeBySNAndPackage 获取设备在某个升级包下的所有升级记录
func (r *OTARepository) GetUpgradeBySNAndPackage(ctx context.Context, sn string, packageID int64) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(du.upgrade_package_id, 0)
		FROM device_upgrades du
		WHERE du.device_sn = $1 AND du.upgrade_package_id = $2
		ORDER BY du.target_chip
	`, sn, packageID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		var pkgID int64
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&pkgID); err != nil {
			continue
		}
		du.UpgradePackageID = &pkgID
		result = append(result, du)
	}
	return result, nil
}

// GetUpgradeByID 根据 ID 获取单条升级记录
func (r *OTARepository) GetUpgradeByID(ctx context.Context, id int64) (*model.DeviceUpgrade, error) {
	var du model.DeviceUpgrade
	err := r.db.QueryRow(ctx, `
		SELECT id, device_sn, firmware_id, firmware_version, COALESCE(target_chip,''),
		       COALESCE(old_version,''), status, COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(retry_count,0), pushed_by, started_at, completed_at, created_at, updated_at,
		       COALESCE(upgrade_package_id, 0)
		FROM device_upgrades WHERE id = $1
	`, id).Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
		&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
		&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
		&du.UpgradePackageID)
	if err != nil {
		return nil, err
	}
	return &du, nil
}

// GetPendingUpgradesBySN 获取设备所有待执行的升级记录
func (r *OTARepository) GetPendingUpgradesBySN(ctx context.Context, sn string) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, device_sn, firmware_id, firmware_version, COALESCE(target_chip,''),
		       COALESCE(old_version,''), COALESCE(status,''), COALESCE(progress,0), COALESCE(error_message,''),
		       COALESCE(retry_count,0), pushed_by, started_at, completed_at, created_at, updated_at,
		       COALESCE(upgrade_package_id, 0)
		FROM device_upgrades
		WHERE device_sn = $1 AND status = 'pending'
		ORDER BY created_at DESC
	`, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var upgrades []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		var pkgID int64
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&pkgID); err != nil {
			continue
		}
		if pkgID > 0 {
			du.UpgradePackageID = &pkgID
		}
		upgrades = append(upgrades, du)
	}
	return upgrades, nil
}

// ========== 升级任务管理 ==========

// CreateUpgradeTask 创建升级任务
func (r *OTARepository) CreateUpgradeTask(ctx context.Context, t *model.UpgradeTask) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO upgrade_tasks (name, task_type, firmware_id, package_id, model, target_version,
		    status, execute_mode, scheduled_at, rollout_percent, total_devices, created_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		RETURNING id, created_at, updated_at
	`, t.Name, t.TaskType, t.FirmwareID, t.PackageID, t.Model, t.TargetVersion,
		t.Status, t.ExecuteMode, t.ScheduledAt, t.RolloutPercent, t.TotalDevices, t.CreatedBy).
		Scan(&t.ID, &t.CreatedAt, &t.UpdatedAt)
}

// GetUpgradeTask 获取升级任务详情
func (r *OTARepository) GetUpgradeTask(ctx context.Context, id int64) (*model.UpgradeTask, error) {
	var t model.UpgradeTask
	err := r.db.QueryRow(ctx, `
		SELECT id, COALESCE(name,''), task_type, firmware_id, package_id, model,
		       COALESCE(target_version,''), status, execute_mode, scheduled_at,
		       rollout_percent, total_devices, success_count, failed_count,
		       created_by, created_at, executed_at, completed_at, updated_at
		FROM upgrade_tasks WHERE id = $1
	`, id).Scan(&t.ID, &t.Name, &t.TaskType, &t.FirmwareID, &t.PackageID, &t.Model,
		&t.TargetVersion, &t.Status, &t.ExecuteMode, &t.ScheduledAt,
		&t.RolloutPercent, &t.TotalDevices, &t.SuccessCount, &t.FailedCount,
		&t.CreatedBy, &t.CreatedAt, &t.ExecutedAt, &t.CompletedAt, &t.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// ListUpgradeTasks 升级任务列表（分页+状态筛选）
func (r *OTARepository) ListUpgradeTasks(ctx context.Context, page, pageSize int, statusFilter string) ([]model.UpgradeTask, int, error) {
	var total int
	countQuery := "SELECT COUNT(*) FROM upgrade_tasks"
	query := `
		SELECT id, COALESCE(name,''), task_type, firmware_id, package_id, model,
		       COALESCE(target_version,''), status, execute_mode, scheduled_at,
		       rollout_percent, total_devices, success_count, failed_count,
		       created_by, created_at, executed_at, completed_at, updated_at
		FROM upgrade_tasks
	`
	args := []interface{}{}
	if statusFilter != "" {
		if statusFilter == "active" {
			// "active" 表示进行中的任务（排除已完成、已取消）
			countQuery += " WHERE status NOT IN ('completed','cancelled')"
			query += " WHERE status NOT IN ('completed','cancelled')"
		} else {
			countQuery += " WHERE status = $1"
			query += " WHERE status = $1"
			args = append(args, statusFilter)
		}
	}
	r.db.QueryRow(ctx, countQuery, args...).Scan(&total)

	query += " ORDER BY created_at DESC"
	offset := (page - 1) * pageSize
	query += fmt.Sprintf(" LIMIT %d OFFSET %d", pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var result []model.UpgradeTask
	for rows.Next() {
		var t model.UpgradeTask
		if err := rows.Scan(&t.ID, &t.Name, &t.TaskType, &t.FirmwareID, &t.PackageID, &t.Model,
			&t.TargetVersion, &t.Status, &t.ExecuteMode, &t.ScheduledAt,
			&t.RolloutPercent, &t.TotalDevices, &t.SuccessCount, &t.FailedCount,
			&t.CreatedBy, &t.CreatedAt, &t.ExecutedAt, &t.CompletedAt, &t.UpdatedAt); err != nil {
			continue
		}
		result = append(result, t)
	}
	return result, total, nil
}

// UpdateUpgradeTaskStatus 更新任务状态
func (r *OTARepository) UpdateUpgradeTaskStatus(ctx context.Context, id int64, status string) error {
	var executedAt, completedAt *time.Time
	now := time.Now()

	if status == "running" {
		// 只有 executed_at 为 NULL 时才设置
		executedAt = &now
	}
	if status == "completed" || status == "partial_success" || status == "failed" || status == "cancelled" {
		completedAt = &now
	}

	// 使用 COALESCE 保留已有值：若新值为 NULL 则保持原值
	_, err := r.db.Exec(ctx, `
		UPDATE upgrade_tasks SET
		    status = $2,
		    executed_at = CASE WHEN $3::timestamp IS NOT NULL AND executed_at IS NULL THEN $3::timestamp ELSE executed_at END,
		    completed_at = CASE WHEN $4::timestamp IS NOT NULL AND completed_at IS NULL THEN $4::timestamp ELSE completed_at END,
		    updated_at = NOW()
		WHERE id = $1
	`, id, status, executedAt, completedAt)
	return err
}

// UpdateUpgradeTaskCounts 更新任务统计
func (r *OTARepository) UpdateUpgradeTaskCounts(ctx context.Context, taskID int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE upgrade_tasks SET
		    success_count = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'success'),
		    failed_count = (SELECT COUNT(*) FROM device_upgrades WHERE task_id = $1 AND status = 'failed'),
		    updated_at = NOW()
		WHERE id = $1
	`, taskID)
	return err
}

// DeleteUpgradeTask 删除升级任务
func (r *OTARepository) DeleteUpgradeTask(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "DELETE FROM upgrade_tasks WHERE id = $1", id)
	return err
}

// ListUpgradeDevicesByTaskID 获取任务下的设备升级详情
func (r *OTARepository) ListUpgradeDevicesByTaskID(ctx context.Context, taskID int64) ([]model.DeviceUpgrade, error) {
	rows, err := r.db.Query(ctx, `
		SELECT du.id, du.device_sn, du.firmware_id, du.firmware_version, COALESCE(du.target_chip,''),
		       COALESCE(du.old_version,''), du.status, COALESCE(du.progress,0), COALESCE(du.error_message,''),
		       COALESCE(du.retry_count,0), du.pushed_by, du.started_at, du.completed_at, du.created_at, du.updated_at,
		       COALESCE(dev.firmware_arm,'') AS current_arm_version,
		       COALESCE(dev.firmware_esp,'') AS current_esp_version,
		       COALESCE(dev.firmware_dsp,'') AS current_dsp_version,
		       COALESCE(dev.firmware_bms,'') AS current_bms_version
		FROM device_upgrades du
		LEFT JOIN devices dev ON du.device_sn = dev.sn
		WHERE du.task_id = $1
		ORDER BY du.device_sn, du.target_chip
	`, taskID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.DeviceUpgrade
	for rows.Next() {
		var du model.DeviceUpgrade
		if err := rows.Scan(&du.ID, &du.DeviceSN, &du.FirmwareID, &du.FirmwareVersion, &du.TargetChip,
			&du.OldVersion, &du.Status, &du.Progress, &du.ErrorMessage,
			&du.RetryCount, &du.PushedBy, &du.StartedAt, &du.CompletedAt, &du.CreatedAt, &du.UpdatedAt,
			&du.CurrentArmVersion, &du.CurrentEspVersion, &du.CurrentDspVersion, &du.CurrentBmsVersion); err != nil {
			continue
		}
		result = append(result, du)
	}
	return result, nil
}

// UpsertDeviceUpgradeWithTask 带 task_id 的 UPSERT
func (r *OTARepository) UpsertDeviceUpgradeWithTask(ctx context.Context, du *model.DeviceUpgrade) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO device_upgrades (device_sn, firmware_id, firmware_version, target_chip,
		    old_version, status, progress, error_message, retry_count, pushed_by, upgrade_package_id, task_id, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW(), NOW())
		ON CONFLICT (device_sn, firmware_id, COALESCE(upgrade_package_id, 0)) DO UPDATE SET
		    status = CASE
		        WHEN device_upgrades.status = 'success' THEN device_upgrades.status
		        WHEN $6 = 'pending' AND device_upgrades.status = 'failed' THEN 'pending'
		        ELSE $6
		    END,
		    firmware_version = $3,
		    old_version = CASE WHEN device_upgrades.old_version = '' THEN $5 ELSE device_upgrades.old_version END,
		    progress = $7,
		    error_message = CASE WHEN $6 = 'failed' THEN $8 ELSE device_upgrades.error_message END,
		    retry_count = CASE WHEN $6 = 'pending' AND device_upgrades.status = 'failed'
		                  THEN device_upgrades.retry_count + 1 ELSE device_upgrades.retry_count END,
		    pushed_by = COALESCE($10, device_upgrades.pushed_by),
		    task_id = COALESCE($12, device_upgrades.task_id),
		    started_at = CASE WHEN $6 IN ('downloading','upgrading') AND device_upgrades.started_at IS NULL
		                THEN NOW() ELSE device_upgrades.started_at END,
		    completed_at = CASE WHEN $6 IN ('success','failed') THEN NOW() ELSE device_upgrades.completed_at END,
		    updated_at = NOW()
		RETURNING id, created_at, updated_at
	`, du.DeviceSN, du.FirmwareID, du.FirmwareVersion, du.TargetChip,
		du.OldVersion, du.Status, du.Progress, du.ErrorMessage, du.RetryCount, du.PushedBy, du.UpgradePackageID, du.TaskID).
		Scan(&du.ID, &du.CreatedAt, &du.UpdatedAt)
}

// RetryFailedUpgradesByTask 重试任务下失败的升级
func (r *OTARepository) RetryFailedUpgradesByTask(ctx context.Context, taskID int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_upgrades SET
		    status = 'pending',
		    progress = 0,
		    error_message = '',
		    retry_count = retry_count + 1,
		    started_at = NULL,
		    completed_at = NULL,
		    updated_at = NOW()
		WHERE task_id = $1 AND status = 'failed'
	`, taskID)
	return err
}

// CancelUpgradesByTask 取消任务下待执行的升级
func (r *OTARepository) CancelUpgradesByTask(ctx context.Context, taskID int64) error {
	_, err := r.db.Exec(ctx, `
		UPDATE device_upgrades SET status = 'cancelled', completed_at = NOW(), updated_at = NOW()
		WHERE task_id = $1 AND status = 'pending'
	`, taskID)
	return err
}

// GetTaskStats 获取任务统计
func (r *OTARepository) GetTaskStats(ctx context.Context) (pending, running, todayCompleted, failed int, err error) {
	err = r.db.QueryRow(ctx, `
		SELECT
		    COUNT(*) FILTER (WHERE status IN ('pending','scheduled')),
		    COUNT(*) FILTER (WHERE status = 'running'),
		    COUNT(*) FILTER (WHERE status IN ('completed','partial_success') AND completed_at >= CURRENT_DATE),
		    COUNT(*) FILTER (WHERE status = 'failed')
		FROM upgrade_tasks
	`).Scan(&pending, &running, &todayCompleted, &failed)
	return
}

// ReportLocalOTAResult 本地OTA完成后，更新设备固件版本并记录升级历史
func (r *OTARepository) ReportLocalOTAResult(ctx context.Context, sn string, targetChip string, newVersion string, mainVersion string) error {
	// 1. 更新设备对应芯片的固件版本
	var updateCol string
	switch targetChip {
	case "arm":
		updateCol = "firmware_arm"
	case "esp":
		updateCol = "firmware_esp"
	case "dsp":
		updateCol = "firmware_dsp"
	case "bms":
		updateCol = "firmware_bms"
	}
	if updateCol != "" && newVersion != "" {
		if _, err := r.db.Exec(ctx, fmt.Sprintf(
			"UPDATE devices SET %s = $2, updated_at = NOW() WHERE sn = $1",
			updateCol,
		), sn, newVersion); err != nil {
			return fmt.Errorf("update firmware version: %w", err)
		}
	}

	// 2. 如果有 mainVersion，更新设备主版本号
	if mainVersion != "" {
		if _, err := r.db.Exec(ctx,
			"UPDATE devices SET main_version = $2, updated_at = NOW() WHERE sn = $1",
			sn, mainVersion); err != nil {
			return fmt.Errorf("update main version: %w", err)
		}
	}

	// 3. 记录一条 device_upgrades 历史记录（标记为本地升级）
	if newVersion != "" {
		if _, err := r.db.Exec(ctx, `
			INSERT INTO device_upgrades (device_sn, firmware_version, target_chip, old_version, status, completed_at, created_at, updated_at)
			VALUES ($1, $2, $3, '', 'success', NOW(), NOW(), NOW())
		`, sn, newVersion, targetChip); err != nil {
			return fmt.Errorf("insert upgrade record: %w", err)
		}
	}

	return nil
}
