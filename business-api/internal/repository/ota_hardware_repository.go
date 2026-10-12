package repository

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5"
	"inv-api-server/internal/model"
)

func (r *OTARepository) ListHardwareVersions(ctx context.Context, deviceModel string) ([]model.DeviceHardwareVersion, error) {
	rows, err := r.db.Query(ctx, `SELECT model,version,description FROM device_hardware_versions WHERE ($1='' OR model=$1) ORDER BY model,version`, deviceModel)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []model.DeviceHardwareVersion{}
	for rows.Next() {
		var v model.DeviceHardwareVersion
		if err = rows.Scan(&v.Model, &v.Version, &v.Description); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (r *OTARepository) CreateHardwareVersion(ctx context.Context, v *model.DeviceHardwareVersion) error {
	_, err := r.db.Exec(ctx, `INSERT INTO device_hardware_versions (model,version,description) VALUES ($1,$2,$3)`, v.Model, v.Version, v.Description)
	return err
}

func writeFirmwareHardware(ctx context.Context, tx pgx.Tx, f *model.Firmware, versions []string) error {
	normalized, err := model.NormalizeHardwareVersions(versions)
	if err != nil {
		return err
	}
	for _, v := range normalized {
		_, err = tx.Exec(ctx, `INSERT INTO firmware_hardware_versions (firmware_id,model,target_chip,firmware_version,hardware_version) VALUES ($1,$2,$3,$4,$5)`, f.ID, f.Model, f.TargetChip, f.Version, v)
		if err != nil {
			return fmt.Errorf("保存硬件兼容范围: %w", err)
		}
	}
	f.HardwareVersions = normalized
	return nil
}

func (r *OTARepository) UpdateFirmwareHardwareVersions(ctx context.Context, id int64, versions []string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var f model.Firmware
	var lockedID int64
	if err = tx.QueryRow(ctx, `SELECT id FROM firmware_versions WHERE id=$1 FOR UPDATE`, id).Scan(&lockedID); err != nil {
		return err
	}
	err = scanFirmware(tx.QueryRow(ctx, `SELECT `+firmwareSelectCols("f")+` FROM firmware_versions f WHERE f.id=$1`, id), &f)
	if err != nil {
		return err
	}
	if len(f.HardwareVersions) > 0 && (f.ReleaseStatus != model.FirmwareReleaseDraft || f.PublishedAt != nil) {
		return model.ErrFirmwareHardwareImmutable
	}
	if _, err = tx.Exec(ctx, `DELETE FROM firmware_hardware_versions WHERE firmware_id=$1`, id); err != nil {
		return err
	}
	if err = writeFirmwareHardware(ctx, tx, &f, versions); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ValidateFirmwareForDevice re-reads current metadata; cached pending payloads cannot bypass checks.
func (r *OTARepository) ValidateFirmwareForDevice(ctx context.Context, sn string, id int64) (*model.Firmware, *DeviceInfo, error) {
	d, err := r.GetDeviceInfoForOTA(ctx, sn)
	if err != nil {
		return nil, nil, err
	}
	f, err := r.GetFirmware(ctx, id)
	if err != nil {
		return nil, d, err
	}
	if !d.HardwareKnown {
		return f, d, model.ErrHardwareVersionUnknown
	}
	if err = model.CheckFirmwareHardware(f, d.Model, d.HardwareVersion); err != nil {
		return f, d, err
	}
	if f.ReleaseStatus != model.FirmwareReleasePublished {
		return f, d, ErrFirmwareNotPublished
	}
	if !firmwareEligibleForDevice(f, sn) {
		return f, d, fmt.Errorf("设备不在固件发布范围或灰度内")
	}
	return f, d, nil
}

func (r *OTARepository) ValidateFirmwareRollback(ctx context.Context, id int64, rollback *int64) error {
	f, err := r.GetFirmware(ctx, id)
	if err != nil {
		return err
	}
	if len(f.HardwareVersions) == 0 {
		return model.ErrFirmwareHardwareUnspecified
	}
	if rollback == nil {
		return nil
	}
	previous, err := r.GetFirmware(ctx, *rollback)
	if err != nil {
		return err
	}
	if previous.ReleaseStatus != model.FirmwareReleasePublished || previous.TargetChip != f.TargetChip || previous.ID == f.ID {
		return model.ErrHardwareIncompatible
	}
	for _, v := range f.HardwareVersions {
		if err = model.CheckFirmwareHardware(previous, f.Model, v); err != nil {
			return err
		}
	}
	return nil
}

func validateFirmwareRollbackTx(ctx context.Context, tx pgx.Tx, id int64, rollback *int64) error {
	var f model.Firmware
	var lockedID int64
	if err := tx.QueryRow(ctx, `SELECT id FROM firmware_versions WHERE id=$1 FOR UPDATE`, id).Scan(&lockedID); err != nil {
		return err
	}
	if err := scanFirmware(tx.QueryRow(ctx, `SELECT `+firmwareSelectCols("f")+` FROM firmware_versions f WHERE f.id=$1`, id), &f); err != nil {
		return err
	}
	if len(f.HardwareVersions) == 0 {
		return model.ErrFirmwareHardwareUnspecified
	}
	if rollback == nil {
		return nil
	}
	if *rollback == id {
		return model.ErrHardwareIncompatible
	}
	var previous model.Firmware
	if err := scanFirmware(tx.QueryRow(ctx, `SELECT `+firmwareSelectCols("f")+` FROM firmware_versions f WHERE f.id=$1 FOR SHARE`, *rollback), &previous); err != nil {
		return err
	}
	if previous.ReleaseStatus != model.FirmwareReleasePublished || previous.TargetChip != f.TargetChip {
		return model.ErrHardwareIncompatible
	}
	for _, v := range f.HardwareVersions {
		if err := model.CheckFirmwareHardware(&previous, f.Model, v); err != nil {
			return err
		}
	}
	return nil
}
