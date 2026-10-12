//go:build integration

package repository

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/model"
)

// Only an explicitly supplied local test server is used. Each test owns a fresh
// schema; no production configuration, secrets, or existing schema is loaded.
func setupOTAHardwareDB(t *testing.T, migrate bool) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("TEST_OTA_HARDWARE_DSN")
	if dsn == "" {
		t.Skip("set TEST_OTA_HARDWARE_DSN to a dedicated local PostgreSQL test server")
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	require.NoError(t, err)
	require.Contains(t, []string{"127.0.0.1", "localhost", "::1"}, cfg.ConnConfig.Host, "hardware integration tests require a local test server")
	ctx := context.Background()
	admin, err := pgxpool.NewWithConfig(ctx, cfg)
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))
	schema := fmt.Sprintf("ota_hardware_test_%d", time.Now().UnixNano())
	quoted := pgx.Identifier{schema}.Sanitize()
	_, err = admin.Exec(ctx, "CREATE SCHEMA "+quoted)
	require.NoError(t, err)
	cfg = cfg.Copy()
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Close()
		_, dropErr := admin.Exec(context.Background(), "DROP SCHEMA "+quoted+" CASCADE")
		assert.NoError(t, dropErr)
		admin.Close()
	})
	_, err = pool.Exec(ctx, otaHardwareMinimalSchema)
	require.NoError(t, err)
	if migrate {
		runOTAHardwareMigration(t, pool, "up")
	}
	return pool
}

// The minimal pre-129 tables expose every column used by the tested repository
// paths without unrelated Timescale/RBAC infrastructure or seeded user data.
const otaHardwareMinimalSchema = `
CREATE TABLE devices (
 sn text PRIMARY KEY, model varchar(100), hardware_version varchar(50),
 firmware_arm text DEFAULT '', firmware_esp text DEFAULT '', firmware_dsp text DEFAULT '',
 firmware_bms text DEFAULT '', main_version text DEFAULT '', status smallint DEFAULT 1,
 deleted_at timestamptz, updated_at timestamptz DEFAULT now()
);
CREATE TABLE firmware_versions (
 id bigserial PRIMARY KEY, model varchar(100) NOT NULL, target_chip varchar(50) NOT NULL,
 version varchar(50) NOT NULL, file_url text NOT NULL, file_size bigint DEFAULT 0,
 file_md5 text DEFAULT '', file_sha256 text DEFAULT '', security_version bigint DEFAULT 0,
 release_signature text DEFAULT '', changelog text DEFAULT '', is_force boolean DEFAULT false,
 uploaded_by bigint DEFAULT 0, status smallint DEFAULT 0, release_status text DEFAULT 'draft',
 created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), published_at timestamptz,
 main_version text DEFAULT '', rollout_percent integer DEFAULT 100, rollout_type text DEFAULT 'all',
 rollout_targets text DEFAULT '', rollback_to_firmware_id bigint
);
CREATE UNIQUE INDEX uq_firmware_model_target_version ON firmware_versions(model,target_chip,version);
CREATE TABLE upgrade_tasks (
 id bigserial PRIMARY KEY, name text DEFAULT '', task_type text, firmware_id bigint, package_id bigint,
 model text, target_version text, status text, execute_mode text, total_devices integer DEFAULT 0,
 created_by bigint, source text, triggered_by bigint, notes text DEFAULT '', rollout_percent integer DEFAULT 100,
 created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), completed_at timestamptz
);
CREATE TABLE device_upgrades (
 id bigserial PRIMARY KEY, device_sn text, firmware_id bigint, firmware_version text, target_chip text,
 old_version text DEFAULT '', status text, progress integer DEFAULT 0, stage text DEFAULT '',
 stage_progress integer DEFAULT 0, overall_progress integer DEFAULT 0, error_message text DEFAULT '',
 retry_count integer DEFAULT 0, pushed_by bigint, task_id bigint, source text,
 upgrade_package_id bigint, started_at timestamptz, completed_at timestamptz,
 created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now()
);
CREATE TABLE ota_idempotency_requests (
 user_id bigint, device_sn text, idempotency_key text, operation text, payload_hash text,
 task_ids jsonb, created_at timestamptz DEFAULT now(), UNIQUE(user_id,device_sn,idempotency_key)
);`

func runOTAHardwareMigration(t *testing.T, pool *pgxpool.Pool, direction string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), otaHardwareMigration(t, direction))
	require.NoError(t, err, "migration 129 %s", direction)
}

func otaHardwareMigration(t *testing.T, direction string) string {
	t.Helper()
	paths, err := filepath.Glob(filepath.Join("..", "..", "..", "database", "migrations", "129*."+direction+".sql"))
	require.NoError(t, err)
	require.Len(t, paths, 1)
	data, err := os.ReadFile(paths[0])
	require.NoError(t, err)
	return string(data)
}

func hardwareExec(t *testing.T, pool *pgxpool.Pool, sql string, args ...any) {
	t.Helper()
	_, err := pool.Exec(context.Background(), sql, args...)
	require.NoError(t, err)
}

func hardwareSQLState(t *testing.T, err error, expected string) {
	t.Helper()
	require.Error(t, err)
	var pgErr *pgconn.PgError
	require.ErrorAs(t, err, &pgErr)
	assert.Equal(t, expected, pgErr.Code)
}

func seedHardwareCatalog(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	hardwareExec(t, pool, `INSERT INTO device_hardware_versions(model,version) VALUES ('MODEL','HW-1'),('MODEL','HW-2'),('OTHER','HW-1')`)
}

func seedHardwareDevice(t *testing.T, pool *pgxpool.Pool, sn, hardware string) {
	t.Helper()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,hardware_version,firmware_arm,firmware_esp,firmware_dsp,firmware_bms,status)
 VALUES($1,'MODEL',$2,'1.0','1.0','1.0','1.0',1)`, sn, hardware)
}

func seedHardwareFirmware(t *testing.T, pool *pgxpool.Pool, chip, version string, hardware []string, published bool) *model.Firmware {
	t.Helper()
	f := &model.Firmware{Model: "MODEL", TargetChip: chip, Version: version, FileURL: "/test/" + chip + version + ".bin", HardwareVersions: hardware}
	r := NewOTARepository(pool)
	require.NoError(t, r.CreateFirmware(context.Background(), f))
	if published {
		require.NoError(t, r.PublishFirmware(context.Background(), f.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RolloutType: "all"}))
	}
	return f
}

func TestOTAHardwareMigrationReplayAndRollback(t *testing.T) {
	pool := setupOTAHardwareDB(t, false)
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,hardware_version) VALUES
 ('normalized','MODEL',' hw-1 '),('empty','MODEL',''),('null','MODEL',NULL),('deleted','MODEL','HW-9')`)
	hardwareExec(t, pool, `UPDATE devices SET deleted_at=now() WHERE sn='deleted'`)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(device_sn,status) VALUES('normalized','success')`)
	runOTAHardwareMigration(t, pool, "up")
	runOTAHardwareMigration(t, pool, "up")
	var versions []string
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT array_agg(version ORDER BY version) FROM device_hardware_versions WHERE model='MODEL'`).Scan(&versions))
	assert.Equal(t, []string{"HW-1"}, versions)
	var snapshot string
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT hardware_version FROM device_upgrades`).Scan(&snapshot))
	assert.Empty(t, snapshot, "existing historical rows must not acquire guessed hardware")
	runOTAHardwareMigration(t, pool, "down")
	runOTAHardwareMigration(t, pool, "down")
	runOTAHardwareMigration(t, pool, "up")
	seedHardwareCatalogAfterReplay(t, pool)
}

func seedHardwareCatalogAfterReplay(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	hardwareExec(t, pool, `INSERT INTO device_hardware_versions(model,version) VALUES('MODEL','HW-2')`)
	hardwareExec(t, pool, `INSERT INTO firmware_versions(model,target_chip,version,file_url) VALUES
 ('MODEL','arm','2.0','/one.bin'),('MODEL','arm','2.0','/two.bin')`)
	_, err := pool.Exec(context.Background(), otaHardwareMigration(t, "down"))
	require.Error(t, err, "rollback cannot restore the old key after divergent builds exist")
	var catalogExists bool
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT to_regclass('device_hardware_versions') IS NOT NULL`).Scan(&catalogExists))
	assert.True(t, catalogExists, "failed rollback must preserve compatibility catalog")
}

func TestOTAHardwareDatabaseConstraints(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	f1 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, false)
	f2 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-2"}, false)
	assert.NotEqual(t, f1.ID, f2.ID, "same software version permits different hardware builds")
	sql := `INSERT INTO firmware_hardware_versions(firmware_id,model,target_chip,firmware_version,hardware_version) VALUES($1,$2,$3,$4,$5)`
	_, err := pool.Exec(context.Background(), sql, f2.ID, "MODEL", "arm", "2.0", "HW-1")
	hardwareSQLState(t, err, "23505")
	_, err = pool.Exec(context.Background(), sql, f2.ID, "MODEL", "arm", "2.0", "HW-MISSING")
	hardwareSQLState(t, err, "23503")
	_, err = pool.Exec(context.Background(), sql, f2.ID, "OTHER", "arm", "2.0", "HW-1")
	hardwareSQLState(t, err, "23503")
	_, err = pool.Exec(context.Background(), sql, f2.ID, "MODEL", "dsp", "2.0", "HW-1")
	hardwareSQLState(t, err, "23503")
	_, err = pool.Exec(context.Background(), sql, f2.ID, "MODEL", "arm", "9.0", "HW-1")
	hardwareSQLState(t, err, "23503")
}

func TestOTAHardwareCreateFirmwareIsAtomicAndRequiresCatalog(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	repo := NewOTARepository(pool)
	for _, hardware := range [][]string{nil, {}, {"HW-MISSING"}, {"HW-1", "HW-MISSING"}} {
		f := &model.Firmware{Model: "MODEL", TargetChip: "arm", Version: "2.0", FileURL: "/test.bin", HardwareVersions: hardware}
		require.Error(t, repo.CreateFirmware(context.Background(), f), "%v", hardware)
		var count int
		require.NoError(t, pool.QueryRow(context.Background(), `SELECT count(*) FROM firmware_versions`).Scan(&count))
		assert.Zero(t, count, "invalid range must leave no firmware row")
	}
	f := seedHardwareFirmware(t, pool, "arm", "2.0", []string{" hw-2 ", "HW-1", "hw-1"}, false)
	loaded, err := repo.GetFirmware(context.Background(), f.ID)
	require.NoError(t, err)
	assert.Equal(t, []string{"HW-1", "HW-2"}, loaded.HardwareVersions)
}

func TestOTAHardwareDeviceFirmwareSelection(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", " hw-1 ")
	seedHardwareDevice(t, pool, "two", "HW-2")
	seedHardwareDevice(t, pool, "unknown", "")
	seedHardwareDevice(t, pool, "unregistered", "HW-99")
	f1 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	f2 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-2"}, true)
	seedHardwareFirmware(t, pool, "arm", "3.0", []string{"HW-1"}, false)
	hardwareExec(t, pool, `INSERT INTO firmware_versions(model,target_chip,version,file_url,release_status,status,published_at)
 VALUES('MODEL','arm','99.0','/legacy.bin','published',1,now())`)
	repo := NewOTARepository(pool)
	for hardware, expected := range map[string]int64{" hw-1 ": f1.ID, "HW-2": f2.ID} {
		found, err := repo.FindFirmwareByVersion(context.Background(), "MODEL", "2.0", "arm", hardware)
		require.NoError(t, err)
		assert.Equal(t, expected, found.ID, "rollback version lookup must select the hardware's exact build")
	}
	_, err := repo.FindFirmwareByVersion(context.Background(), "MODEL", "2.0", "arm")
	require.Error(t, err, "a same-version lookup without hardware must not choose an arbitrary file")
	for sn, expected := range map[string]int64{"one": f1.ID, "two": f2.ID} {
		resources, err := repo.ListPublishedFirmwareForDevice(context.Background(), sn, "arm")
		require.NoError(t, err)
		require.Len(t, resources, 1)
		assert.Equal(t, expected, resources[0].ID)
		latest, err := repo.GetLatestFirmware(context.Background(), sn, "MODEL", "arm")
		require.NoError(t, err)
		assert.Equal(t, expected, latest.ID)
	}
	for _, sn := range []string{"unknown", "unregistered"} {
		resources, err := repo.ListPublishedFirmwareForDevice(context.Background(), sn, "arm")
		require.NoError(t, err)
		assert.Empty(t, resources)
		_, err = repo.GetLatestFirmware(context.Background(), sn, "MODEL", "arm")
		require.Error(t, err)
	}
	common := seedHardwareFirmware(t, pool, "esp", "2.0", []string{"HW-1", "HW-2"}, true)
	for _, sn := range []string{"one", "two"} {
		fw, _, err := repo.ValidateFirmwareForDevice(context.Background(), sn, common.ID)
		require.NoError(t, err)
		assert.Equal(t, common.ID, fw.ID)
	}
	_, _, err = repo.ValidateFirmwareForDevice(context.Background(), "one", f2.ID)
	require.Error(t, err)
	hardwareExec(t, pool, `UPDATE devices SET hardware_version='HW-2' WHERE sn='one'`)
	_, _, err = repo.ValidateFirmwareForDevice(context.Background(), "one", f1.ID)
	require.Error(t, err, "dispatch guard must read current device hardware")
}

func TestOTAHardwareTasksRejectForceAndRemainAtomic(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	seedHardwareDevice(t, pool, "unknown", "")
	seedHardwareDevice(t, pool, "unregistered", "HW-99")
	arm := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	dsp := seedHardwareFirmware(t, pool, "dsp", "2.0", []string{"HW-2"}, true)
	repo := NewOTARepository(pool)
	for _, test := range []struct {
		sn  string
		ids []int64
	}{
		{"unknown", []int64{arm.ID}}, {"unregistered", []int64{arm.ID}},
		{"one", []int64{dsp.ID}}, {"one", []int64{arm.ID, dsp.ID}},
	} {
		for _, force := range []string{"", "administrator forced upgrade"} {
			_, err := repo.CreateIndependentFirmwareTasks(context.Background(), 1, test.sn, test.ids, fmt.Sprintf("%s-%v-%s", test.sn, test.ids, force), "trigger", force)
			require.Error(t, err)
			for _, table := range []string{"upgrade_tasks", "device_upgrades", "ota_idempotency_requests"} {
				var count int
				require.NoError(t, pool.QueryRow(context.Background(), "SELECT count(*) FROM "+table).Scan(&count))
				assert.Zero(t, count, "rejected batch leaves no %s", table)
			}
		}
	}
	refs, err := repo.CreateIndependentFirmwareTasks(context.Background(), 1, "one", []int64{arm.ID}, "success", "trigger", "")
	require.NoError(t, err)
	require.Len(t, refs, 1)
	var snapshot string
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT hardware_version FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&snapshot))
	assert.Equal(t, "HW-1", snapshot)
	hardwareExec(t, pool, `UPDATE devices SET hardware_version='HW-2' WHERE sn='one'`)
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT hardware_version FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&snapshot))
	assert.Equal(t, "HW-1", snapshot, "history records hardware at creation, independent of later identity updates")
}

func TestOTAHardwareScopeLifecycle(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	f := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, false)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	require.NoError(t, repo.UpdateFirmwareHardwareVersions(ctx, f.ID, []string{"HW-1", "HW-2"}))
	require.Error(t, repo.UpdateFirmwareHardwareVersions(ctx, f.ID, []string{"HW-MISSING"}))
	loaded, err := repo.GetFirmware(ctx, f.ID)
	require.NoError(t, err)
	assert.Equal(t, []string{"HW-1", "HW-2"}, loaded.HardwareVersions, "failed adjustment keeps previous scope")
	require.NoError(t, repo.PublishFirmware(ctx, f.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100}))
	require.Error(t, repo.UpdateFirmwareHardwareVersions(ctx, f.ID, []string{"HW-2"}))
	require.NoError(t, repo.DisableFirmware(ctx, f.ID, 1))
	require.Error(t, repo.UpdateFirmwareHardwareVersions(ctx, f.ID, []string{"HW-1"}), "once-published scope stays immutable while disabled")
	var legacyID int64
	require.NoError(t, pool.QueryRow(ctx, `INSERT INTO firmware_versions(model,target_chip,version,file_url,release_status,status,published_at)
 VALUES('MODEL','arm','legacy','/legacy.bin','published',1,now()) RETURNING id`).Scan(&legacyID))
	require.NoError(t, repo.UpdateFirmwareHardwareVersions(ctx, legacyID, []string{"HW-1"}))
	require.Error(t, repo.UpdateFirmwareHardwareVersions(ctx, legacyID, []string{"HW-2"}), "legacy empty scope permits exactly one audited backfill")
}

func TestOTAHardwareHistoryRollbackChoosesCurrentHardware(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	old1 := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-1"}, true)
	old2 := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-2"}, true)
	new1 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(device_sn,firmware_id,firmware_version,target_chip,old_version,status)
 VALUES('one',$1,'2.0','arm','1.0','success')`, new1.ID)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	for _, test := range []struct {
		hardware string
		expected int64
	}{{"HW-1", old1.ID}, {"HW-2", old2.ID}, {"", 0}} {
		hardwareExec(t, pool, `UPDATE devices SET hardware_version=$1 WHERE sn='one'`, test.hardware)
		history, total, err := repo.ListUpgradeHistoryFiltered(ctx, model.UpgradeHistoryFilter{DeviceSN: "one", Page: 1, PageSize: 10})
		require.NoError(t, err)
		assert.Equal(t, 1, total)
		require.Len(t, history, 1)
		assert.Equal(t, test.expected, history[0].RollbackFirmwareID)
		assert.Equal(t, "HW-1", history[0].HardwareVersion, "response preserves task creation hardware, independent of rollback selection")
	}
}

func TestOTAHardwarePublishRollbackCoversEntireScope(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	old1 := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-1"}, true)
	oldCommon := seedHardwareFirmware(t, pool, "arm", "1.1", []string{"HW-1", "HW-2"}, true)
	wrongModule := seedHardwareFirmware(t, pool, "dsp", "1.0", []string{"HW-1", "HW-2"}, true)
	draft := seedHardwareFirmware(t, pool, "arm", "1.2", []string{"HW-1", "HW-2"}, false)
	next := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1", "HW-2"}, false)
	for _, rollback := range []int64{old1.ID, wrongModule.ID, draft.ID, next.ID} {
		err := repo.PublishFirmware(ctx, next.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RollbackToFirmwareID: &rollback})
		require.Error(t, err, "rollback must be a distinct published compatible build covering every hardware")
		loaded, err := repo.GetFirmware(ctx, next.ID)
		require.NoError(t, err)
		assert.Equal(t, model.FirmwareReleaseDraft, loaded.ReleaseStatus)
		assert.Nil(t, loaded.PublishedAt)
	}
	require.NoError(t, repo.PublishFirmware(ctx, next.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RollbackToFirmwareID: &oldCommon.ID}))
	loaded, err := repo.GetFirmware(ctx, next.ID)
	require.NoError(t, err)
	require.NotNil(t, loaded.RollbackToFirmwareID)
	assert.Equal(t, oldCommon.ID, *loaded.RollbackToFirmwareID)
	require.Error(t, repo.UpdateFirmwareRollout(ctx, next.ID, model.FirmwarePublishOptions{RolloutPercent: 20, RollbackToFirmwareID: &old1.ID}))
	loaded, err = repo.GetFirmware(ctx, next.ID)
	require.NoError(t, err)
	assert.Equal(t, 100, loaded.RolloutPercent, "invalid rollback must not partially change rollout")
	assert.Equal(t, oldCommon.ID, *loaded.RollbackToFirmwareID)
}

func TestOTAHardwarePublishReadsScopeAfterConcurrentEdit(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	repo := NewOTARepository(pool)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	old := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-1"}, true)
	next := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, false)
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer tx.Rollback(context.Background())
	_, err = tx.Exec(ctx, `SELECT id FROM firmware_versions WHERE id=$1 FOR UPDATE`, next.ID)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `DELETE FROM firmware_hardware_versions WHERE firmware_id=$1`, next.ID)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `INSERT INTO firmware_hardware_versions(firmware_id,model,target_chip,firmware_version,hardware_version)
 VALUES($1,'MODEL','arm','2.0','HW-2')`, next.ID)
	require.NoError(t, err)
	done := make(chan error, 1)
	go func() {
		done <- repo.PublishFirmware(ctx, next.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RollbackToFirmwareID: &old.ID})
	}()
	require.Eventually(t, func() bool {
		var blocked bool
		queryErr := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity
 WHERE pid<>pg_backend_pid() AND state='active' AND wait_event_type='Lock' AND query LIKE '%firmware_versions%FOR UPDATE%')`).Scan(&blocked)
		return queryErr == nil && blocked
	}, 2*time.Second, 20*time.Millisecond, "publication should wait for the scope edit's parent row lock")
	require.NoError(t, tx.Commit(ctx))
	select {
	case publishErr := <-done:
		require.Error(t, publishErr, "after waiting for an edit, publication must check committed HW-2 scope against HW-1 rollback")
	case <-ctx.Done():
		t.Fatal("publication did not finish after scope lock was released")
	}
	loaded, err := repo.GetFirmware(context.Background(), next.ID)
	require.NoError(t, err)
	assert.Equal(t, []string{"HW-2"}, loaded.HardwareVersions)
	assert.Equal(t, model.FirmwareReleaseDraft, loaded.ReleaseStatus)
}

func TestOTAHardwareLocalResultPreservesExactBuildAndSnapshot(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	seedHardwareDevice(t, pool, "two", "HW-2")
	seedHardwareDevice(t, pool, "unknown", "")
	build1 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	build2 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-2"}, true)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	for _, test := range []struct {
		sn      string
		id      int64
		version string
	}{
		{"one", build2.ID, "2.0"}, {"unknown", build1.ID, "2.0"}, {"one", build1.ID, "9.0"},
	} {
		_, err := repo.CreateTaskFromLocalOTA(ctx, 1, test.sn, "arm", test.version, "", test.id)
		require.Error(t, err)
		for _, table := range []string{"upgrade_tasks", "device_upgrades"} {
			var count int
			require.NoError(t, pool.QueryRow(ctx, "SELECT count(*) FROM "+table).Scan(&count))
			assert.Zero(t, count, "invalid local result must roll back %s", table)
		}
	}
	for _, test := range []struct {
		sn, hardware string
		id           int64
	}{{"one", "HW-1", build1.ID}, {"two", "HW-2", build2.ID}} {
		taskID, err := repo.CreateTaskFromLocalOTA(ctx, 1, test.sn, "arm", "2.0", "", test.id)
		require.NoError(t, err)
		var actualID int64
		var snapshot, status, current string
		require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_id,hardware_version,status FROM device_upgrades WHERE task_id=$1`, taskID).Scan(&actualID, &snapshot, &status))
		assert.Equal(t, test.id, actualID)
		var taskFirmwareID int64
		require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_id FROM upgrade_tasks WHERE id=$1`, taskID).Scan(&taskFirmwareID))
		assert.Equal(t, test.id, taskFirmwareID, "task and device history refer to the same actual build")
		assert.Equal(t, test.hardware, snapshot)
		assert.Equal(t, model.UpgradeStatusSuccess, status)
		require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_arm FROM devices WHERE sn=$1`, test.sn).Scan(&current))
		assert.Equal(t, "2.0", current)
	}
	// An older client without the new ID still resolves the unique hardware
	// build, even when another board's same-version file was uploaded later.
	taskID, err := repo.CreateTaskFromLocalOTA(ctx, 1, "one", "arm", "2.0", "")
	require.NoError(t, err)
	var actualID int64
	require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_id FROM device_upgrades WHERE task_id=$1`, taskID).Scan(&actualID))
	assert.Equal(t, build1.ID, actualID)
	hardwareExec(t, pool, `UPDATE devices SET hardware_version='HW-2' WHERE sn='one'`)
	history, _, err := repo.ListUpgradeHistoryFiltered(ctx, model.UpgradeHistoryFilter{DeviceSN: "one", Page: 1, PageSize: 10})
	require.NoError(t, err)
	require.Len(t, history, 2)
	for _, item := range history {
		assert.Equal(t, build1.ID, item.FirmwareID)
		assert.Equal(t, "HW-1", item.HardwareVersion)
	}
}

func TestOTAHardwareConcurrentLegacyBackfillOnlyRunsOnce(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var id int64
	require.NoError(t, pool.QueryRow(ctx, `INSERT INTO firmware_versions(model,target_chip,version,file_url,release_status,status,published_at)
 VALUES('MODEL','arm','legacy','/legacy.bin','published',1,now()) RETURNING id`).Scan(&id))
	tx, err := pool.Begin(ctx)
	require.NoError(t, err)
	defer tx.Rollback(context.Background())
	_, err = tx.Exec(ctx, `SELECT id FROM firmware_versions WHERE id=$1 FOR UPDATE`, id)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `INSERT INTO firmware_hardware_versions(firmware_id,model,target_chip,firmware_version,hardware_version)
 VALUES($1,'MODEL','arm','legacy','HW-1')`, id)
	require.NoError(t, err)
	done := make(chan error, 1)
	go func() { done <- NewOTARepository(pool).UpdateFirmwareHardwareVersions(ctx, id, []string{"HW-2"}) }()
	require.Eventually(t, func() bool {
		var blocked bool
		queryErr := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity
 WHERE pid<>pg_backend_pid() AND state='active' AND wait_event_type='Lock' AND query LIKE '%firmware_versions%FOR UPDATE%')`).Scan(&blocked)
		return queryErr == nil && blocked
	}, 2*time.Second, 20*time.Millisecond)
	require.NoError(t, tx.Commit(ctx))
	select {
	case updateErr := <-done:
		require.Error(t, updateErr, "the second backfill must see the first committed range and reject changing published scope")
	case <-ctx.Done():
		t.Fatal("backfill did not finish after scope lock was released")
	}
	f, err := NewOTARepository(pool).GetFirmware(context.Background(), id)
	require.NoError(t, err)
	assert.Equal(t, []string{"HW-1"}, f.HardwareVersions)
}

func TestOTAHardwareDeviceVersionQueryIncludesHardware(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", " hw-1 ")
	seedHardwareDevice(t, pool, "two", "HW-2")
	seedHardwareDevice(t, pool, "unknown", "")
	seedHardwareDevice(t, pool, "deleted", "HW-1")
	hardwareExec(t, pool, `UPDATE devices SET deleted_at=now() WHERE sn='deleted'`)
	rows, err := NewOTARepository(pool).GetDevicesByFirmwareVersion(context.Background(), "MODEL", "arm", "1.0")
	require.NoError(t, err)
	require.Len(t, rows, 3)
	bySN := make(map[string]string)
	for _, row := range rows {
		bySN[row.SN] = row.HardwareVersion
	}
	assert.Equal(t, map[string]string{"one": " hw-1 ", "two": "HW-2", "unknown": ""}, bySN, "bulk selector receives actual raw hardware instead of silently conflating same-model devices")
}
