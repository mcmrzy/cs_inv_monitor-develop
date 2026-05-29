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
		INSERT INTO firmware_versions (model, version, file_url, file_size, file_md5, file_sha256, changelog, is_force, uploaded_by, status, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,1,NOW(),NOW())
		RETURNING id, created_at, updated_at
	`, f.Model, f.Version, f.FileURL, f.FileSize, f.FileMD5, f.FileSHA256, f.Changelog, f.IsForce, f.UploadedBy).
		Scan(&f.ID, &f.CreatedAt, &f.UpdatedAt)
}

func (r *OTARepository) ListFirmware(ctx context.Context, modelFilter string) ([]model.Firmware, error) {
	query := `
		SELECT id, model, version, file_url, COALESCE(file_size,0), COALESCE(file_md5,''),
		       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, uploaded_by, status, created_at, updated_at
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
			&f.Status, &f.CreatedAt, &f.UpdatedAt); err != nil {
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
		       COALESCE(file_sha256,''), COALESCE(changelog,''), is_force, uploaded_by, status, created_at, updated_at
		FROM firmware_versions WHERE id = $1
	`, id).Scan(&f.ID, &f.Model, &f.Version, &f.FileURL, &f.FileSize,
		&f.FileMD5, &f.FileSHA256, &f.Changelog, &f.IsForce, &f.UploadedBy,
		&f.Status, &f.CreatedAt, &f.UpdatedAt)
	return &f, err
}

func (r *OTARepository) DeleteFirmware(ctx context.Context, id int64) error {
	_, err := r.db.Exec(ctx, "UPDATE firmware_versions SET status = 0 WHERE id = $1", id)
	return err
}

func (r *OTARepository) CreateTask(ctx context.Context, t *model.OtaTask) error {
	return r.db.QueryRow(ctx, `
		INSERT INTO ota_tasks (name, firmware_id, firmware_version, model, target_type, target_value, total_count,
		                       success_count, fail_count, status, description, created_by, push_strategy, push_percentage, batch_size, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,NOW(),NOW())
		RETURNING id, created_at, updated_at
	`, t.Name, t.FirmwareID, t.FirmwareVersion, t.Model, t.TargetType, t.TargetValue,
		t.TotalCount, t.SuccessCount, t.FailCount, t.Status, t.Description, t.CreatedBy,
		t.PushStrategy, t.PushPercentage, t.BatchSize).
		Scan(&t.ID, &t.CreatedAt, &t.UpdatedAt)
}

func (r *OTARepository) ListTasks(ctx context.Context, status string, page, pageSize int) ([]model.OtaTask, int, error) {
	var total int
	r.db.QueryRow(ctx, "SELECT COUNT(*) FROM ota_tasks WHERE ($1='' OR status=$1)", status).Scan(&total)

	rows, err := r.db.Query(ctx, `
		SELECT id, name, firmware_id, firmware_version, model, target_type, COALESCE(target_value,''),
		       total_count, success_count, fail_count, status, COALESCE(description,''), created_by,
		       COALESCE(push_strategy,'all_at_once'), COALESCE(push_percentage,100), COALESCE(batch_size,10),
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
			&t.BatchSize, &t.CreatedAt, &t.StartedAt, &t.CompletedAt, &t.UpdatedAt); err != nil {
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
		       created_at, COALESCE(started_at, created_at), completed_at, updated_at
		FROM ota_tasks WHERE id = $1
	`, id).Scan(&t.ID, &t.Name, &t.FirmwareID, &t.FirmwareVersion, &t.Model,
		&t.TargetType, &t.TargetValue, &t.TotalCount, &t.SuccessCount, &t.FailCount,
		&t.Status, &t.Description, &t.CreatedBy, &t.PushStrategy, &t.PushPercentage,
		&t.BatchSize, &t.CreatedAt, &t.StartedAt, &t.CompletedAt, &t.UpdatedAt)
	return &t, err
}

func (r *OTARepository) UpdateTaskStatus(ctx context.Context, id string, status string) error {
	now := time.Now()
	_, err := r.db.Exec(ctx, `
		UPDATE ota_tasks SET status = $1, updated_at = $3,
		    started_at = COALESCE(started_at, CASE WHEN $1='running' THEN $3 ELSE NULL END),
		    completed_at = CASE WHEN $1 IN ('completed','failed') THEN $3 ELSE NULL END
		WHERE id = $2
	`, status, id, now)
	return err
}

func (r *OTARepository) UpsertTaskDevice(ctx context.Context, td *model.OtaTaskDevice) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO ota_task_devices (task_id, device_sn, old_version, new_version, status, progress, error_message, mqtt_message, started_at, completed_at, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW())
		ON CONFLICT (task_id, device_sn) DO UPDATE SET
		    status = $5, progress = $6, error_message = $7, mqtt_message = $8,
		    started_at = COALESCE(ota_task_devices.started_at, $9),
		    completed_at = CASE WHEN $5 IN ('success','failed') THEN NOW() ELSE NULL END
	`, td.TaskID, td.DeviceSN, td.OldVersion, td.NewVersion, td.Status,
		td.Progress, td.ErrorMessage, td.MQTTMessage, td.StartedAt, td.CompletedAt)
	return err
}

func (r *OTARepository) ListTaskDevices(ctx context.Context, taskID string) ([]model.OtaTaskDevice, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, task_id, device_sn, COALESCE(old_version,''), COALESCE(new_version,''),
		       status, COALESCE(progress,0), COALESCE(error_message,''), COALESCE(mqtt_message,''),
		       started_at, completed_at, created_at
		FROM ota_task_devices WHERE task_id = $1 ORDER BY id
	`, taskID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []model.OtaTaskDevice
	for rows.Next() {
		var d model.OtaTaskDevice
		if err := rows.Scan(&d.ID, &d.TaskID, &d.DeviceSN, &d.OldVersion, &d.NewVersion,
			&d.Status, &d.Progress, &d.ErrorMessage, &d.MQTTMessage,
			&d.StartedAt, &d.CompletedAt, &d.CreatedAt); err != nil {
			continue
		}
		devices = append(devices, d)
	}
	return devices, nil
}
