//go:build integration

package repository

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
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
		paths, err := filepath.Glob(filepath.Join("..", "..", "..", "database", "migrations", "13[123]*.up.sql"))
		require.NoError(t, err)
		require.Len(t, paths, 3)
		for _, path := range paths {
			data, err := os.ReadFile(path)
			require.NoError(t, err)
			hardwareExec(t, pool, string(data))
		}
	}
	return pool
}

// The minimal pre-129 tables expose every column used by the tested repository
// paths without unrelated Timescale infrastructure or seeded user data. The three
// authorization projections below are the exact ones the device scope filter
// rechecks, so scope-limited candidate queries run against real SQL.
const otaHardwareMinimalSchema = `
CREATE TABLE devices (
 sn text PRIMARY KEY, model varchar(100), hardware_version varchar(50), alias text DEFAULT '',
 firmware_arm text DEFAULT '', firmware_esp text DEFAULT '', firmware_dsp text DEFAULT '',
 firmware_bms text DEFAULT '', main_version text DEFAULT '', status smallint DEFAULT 1,
 deleted_at timestamptz, updated_at timestamptz DEFAULT now()
);
CREATE TABLE users (
 id bigint PRIMARY KEY, status smallint DEFAULT 1, deleted_at timestamptz, is_system_admin boolean DEFAULT false
);
CREATE TABLE organizations (
 id bigint PRIMARY KEY, root_tenant_id bigint NOT NULL, status text DEFAULT 'active', deleted_at timestamptz
);
CREATE TABLE organization_memberships (
 id bigint PRIMARY KEY, root_tenant_id bigint NOT NULL, organization_id bigint NOT NULL, user_id bigint NOT NULL,
 version bigint NOT NULL DEFAULT 1, status text NOT NULL DEFAULT 'active', expires_at timestamptz
);
CREATE TABLE organization_closure (
 root_tenant_id bigint NOT NULL, ancestor_id bigint NOT NULL, descendant_id bigint NOT NULL
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
 model text, target_version text, status text, execute_mode text, total_devices integer DEFAULT 0, success_count integer DEFAULT 0,
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
	hardwareExec(t, pool, `INSERT INTO hardware_board_types(model,target_chip,board_code)
 SELECT h.model,t.target_chip,h.version FROM device_hardware_versions h CROSS JOIN (VALUES('arm'),('dsp'),('esp'),('bms')) t(target_chip)`)
}

func seedHardwareDevice(t *testing.T, pool *pgxpool.Pool, sn, hardware string) {
	t.Helper()
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,hardware_version,firmware_arm,firmware_esp,firmware_dsp,firmware_bms,status)
 VALUES($1,'MODEL',$2,'1.0','1.0','1.0','1.0',1)`, sn, hardware)
	board := model.NormalizeHardwareVersion(hardware)
	if board == "HW-1" || board == "HW-2" {
		hardwareExec(t, pool, `INSERT INTO device_hardware_registry(sn,verified_model,identity_state,identity_revision,source,evidence_ref) VALUES($1,'MODEL','verified',1,'fixture-ledger','factory-record')`, sn)
		hardwareExec(t, pool, `INSERT INTO device_hardware_modules(sn,verified_model,target_chip,board_code,board_uid,state,module_revision)
 SELECT $1::varchar,'MODEL',t,$2,$1::text||'-'||t,'verified',1 FROM unnest(ARRAY['arm','dsp','esp','bms']) t`, sn, board)
	}
}

func seedHardwareFirmware(t *testing.T, pool *pgxpool.Pool, chip, version string, hardware []string, published bool) *model.Firmware {
	t.Helper()
	var boards []string
	if len(hardware) > 0 {
		var err error
		boards, err = model.NormalizeHardwareVersions(hardware)
		require.NoError(t, err)
	}
	f := &model.Firmware{Model: "MODEL", TargetChip: chip, Version: version, FileURL: "/test/" + chip + version + ".bin", HardwareVersions: hardware, BoardCodes: boards, FileSHA256: strings.Repeat("a", 64)}
	r := NewOTARepository(pool)
	require.NoError(t, r.CreateFirmware(context.Background(), f))
	if published {
		require.NoError(t, r.PublishFirmware(context.Background(), f.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RolloutType: "all"}))
	}
	hardwareExec(t, pool, `INSERT INTO ota_compatibility_windows(sn,target_chip,firmware_id,file_sha256,expires_at,identity_revision,reason,actor,evidence_ref)
 SELECT sn,$1,$2,$3,NOW()+INTERVAL '1 hour',identity_revision,'test maintenance',1,'test work order' FROM device_hardware_registry`, chip, f.ID, f.FileSHA256)
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

func TestOTAHardwareMetadataOptionalAndCatalogWritesAtomic(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	repo := NewOTARepository(pool)
	for _, scope := range [][]string{{"HW-MISSING"}, {"HW-1", "HW-MISSING"}} {
		f := &model.Firmware{Model: "MODEL", TargetChip: "arm", Version: "2.0", FileURL: "/test.bin", HardwareVersions: scope}
		require.Error(t, repo.CreateFirmware(context.Background(), f))
		var n int
		require.NoError(t, pool.QueryRow(context.Background(), `SELECT count(*) FROM firmware_versions`).Scan(&n))
		require.Zero(t, n)
	}
	f := seedHardwareFirmware(t, pool, "arm", "2.0", nil, true)
	got, err := repo.GetFirmware(context.Background(), f.ID)
	require.NoError(t, err)
	require.Empty(t, got.HardwareVersions)
	require.Empty(t, got.BoardCodes)

}

func TestOTAHardwareDeviceFirmwareSelection(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	for _, pair := range [][2]string{{"one", "HW-1"}, {"two", "HW-2"}, {"unknown", ""}, {"unregistered", "HW-99"}} {
		seedHardwareDevice(t, pool, pair[0], pair[1])
	}
	first := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	latest := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-2"}, true)
	seedHardwareFirmware(t, pool, "arm", "9.0", nil, false)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	found, err := repo.FindFirmwareByVersion(ctx, "MODEL", "2.0", "arm")
	require.NoError(t, err)
	require.Equal(t, latest.ID, found.ID)
	for _, sn := range []string{"one", "two", "unknown", "unregistered"} {
		resources, err := repo.ListPublishedFirmwareForDevice(ctx, sn, "arm")
		require.NoError(t, err)
		require.Len(t, resources, 2)
		fw, err := repo.GetLatestFirmware(ctx, sn, "MODEL", "arm")
		require.NoError(t, err)
		require.Equal(t, latest.ID, fw.ID)
		_, _, err = repo.ValidateFirmwareForDevice(ctx, sn, first.ID)
		require.NoError(t, err)
	}
	hardwareExec(t, pool, `UPDATE device_hardware_modules SET board_code='HW-2',module_revision=2 WHERE sn='one' AND target_chip='arm'`)
	_, _, err = repo.ValidateFirmwareForDevice(ctx, "one", first.ID)
	require.NoError(t, err)

}

func TestOTAModelTargetTasksRemainAtomicAndPreserveHistory(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	arm := seedHardwareFirmware(t, pool, "arm", "2.0", nil, true)
	draft := seedHardwareFirmware(t, pool, "dsp", "2.0", nil, false)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	_, err := repo.CreateIndependentFirmwareTasks(ctx, 1, "one", []int64{arm.ID, draft.ID}, "rejected", "trigger", "")
	require.Error(t, err)
	for _, table := range []string{"upgrade_tasks", "device_upgrades", "ota_idempotency_requests"} {
		var n int
		require.NoError(t, pool.QueryRow(ctx, "SELECT count(*) FROM "+table).Scan(&n))
		require.Zero(t, n)
	}
	refs, err := repo.CreateIndependentFirmwareTasks(ctx, 1, "one", []int64{arm.ID}, "success", "trigger", "")
	require.NoError(t, err)
	require.Len(t, refs, 1)
	var snapshot string
	require.NoError(t, pool.QueryRow(ctx, `SELECT hardware_version FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&snapshot))
	require.Equal(t, "HW-1", snapshot)
	hardwareExec(t, pool, `UPDATE devices SET hardware_version='HW-2' WHERE sn='one'`)
	require.NoError(t, pool.QueryRow(ctx, `SELECT hardware_version FROM device_upgrades WHERE task_id=$1`, refs[0].TaskID).Scan(&snapshot))
	require.Equal(t, "HW-1", snapshot)

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

func TestOTARollbackSelectionUsesModelTargetAndPreservesHistory(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	seedHardwareDevice(t, pool, "one", "HW-1")
	_ = seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-1"}, true)
	old1 := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-2"}, true)
	new1 := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)
	hardwareExec(t, pool, `INSERT INTO device_upgrades(device_sn,firmware_id,firmware_version,target_chip,old_version,status)
 VALUES('one',$1,'2.0','arm','1.0','success')`, new1.ID)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	for _, test := range []struct {
		hardware string
		expected int64
	}{{"HW-1", old1.ID}, {"HW-2", old1.ID}, {"", old1.ID}} {
		hardwareExec(t, pool, `UPDATE devices SET hardware_version=$1 WHERE sn='one'`, test.hardware)
		history, total, err := repo.ListUpgradeHistoryFiltered(ctx, model.UpgradeHistoryFilter{DeviceSN: "one", Page: 1, PageSize: 10})
		require.NoError(t, err)
		assert.Equal(t, 1, total)
		require.Len(t, history, 1)
		assert.Equal(t, test.expected, history[0].RollbackFirmwareID)
		assert.Equal(t, "HW-1", history[0].HardwareVersion, "response preserves task creation hardware, independent of rollback selection")
	}
}

func TestOTARollbackPublishRequiresPublishedModelTarget(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	repo := NewOTARepository(pool)
	ctx := context.Background()
	old1 := seedHardwareFirmware(t, pool, "arm", "1.0", []string{"HW-1"}, true)
	oldCommon := seedHardwareFirmware(t, pool, "arm", "1.1", []string{"HW-1", "HW-2"}, true)
	wrongModule := seedHardwareFirmware(t, pool, "dsp", "1.0", []string{"HW-1", "HW-2"}, true)
	draft := seedHardwareFirmware(t, pool, "arm", "1.2", []string{"HW-1", "HW-2"}, false)
	next := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1", "HW-2"}, false)
	for _, rollback := range []int64{wrongModule.ID, draft.ID, next.ID} {
		err := repo.PublishFirmware(ctx, next.ID, 1, model.FirmwarePublishOptions{RolloutPercent: 100, RollbackToFirmwareID: &rollback})
		require.Error(t, err, "rollback must be a distinct published build for the same model and target")
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
	require.NoError(t, repo.UpdateFirmwareRollout(ctx, next.ID, model.FirmwarePublishOptions{RolloutPercent: 20, RollbackToFirmwareID: &old1.ID}))
	loaded, err = repo.GetFirmware(ctx, next.ID)
	require.NoError(t, err)
	assert.Equal(t, 20, loaded.RolloutPercent, "historical range does not block same-model/target rollback")
	assert.Equal(t, old1.ID, *loaded.RollbackToFirmwareID)
}

func TestOTAPublishAllowsConcurrentHistoricalScopeEdit(t *testing.T) {
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
	_, err = tx.Exec(ctx, `DELETE FROM firmware_board_types WHERE firmware_id=$1`, next.ID)
	require.NoError(t, err)
	_, err = tx.Exec(ctx, `INSERT INTO firmware_board_types(firmware_id,model,target_chip,firmware_version,board_code)
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
		require.NoError(t, publishErr, "historical scope edit does not block same-model target rollback")
	case <-ctx.Done():
		t.Fatal("publication did not finish after scope lock was released")
	}
	loaded, err := repo.GetFirmware(context.Background(), next.ID)
	require.NoError(t, err)
	assert.Equal(t, []string{"HW-2"}, loaded.BoardCodes)
	assert.Equal(t, model.FirmwareReleasePublished, loaded.ReleaseStatus)
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

// Task creation must offer the devices the dispatch path will accept, and keep
// every other same-model device visible with the reason it cannot be picked.
func TestOTAHardwareTaskCandidatesReportEligibility(t *testing.T) {
	pool := setupOTAHardwareDB(t, true)
	seedHardwareCatalog(t, pool)
	hardwareExec(t, pool, `INSERT INTO users(id,status,is_system_admin) VALUES(7,1,TRUE)`)
	hardwareExec(t, pool, `INSERT INTO organizations(id,root_tenant_id,status) VALUES(11,7,'active')`)
	hardwareExec(t, pool, `INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,version,status) VALUES(21,7,11,7,1,'active')`)
	seedHardwareDevice(t, pool, "CAND-A", "HW-1")
	seedHardwareDevice(t, pool, "CAND-B", "HW-2")
	seedHardwareDevice(t, pool, "CAND-C", "HW-9")
	hardwareExec(t, pool, `INSERT INTO devices(sn,model,hardware_version,firmware_arm) VALUES('CAND-OTHER','OTHER','HW-1','1.0')`)
	created := seedHardwareFirmware(t, pool, "arm", "2.0", []string{"HW-1"}, true)

	actor := model.ActorContext{UserID: 7, RootTenantID: 7, OrganizationID: 11, MembershipID: 21, MembershipVersion: 1}
	plan := model.ScopePlan{Actor: actor, PermissionCode: "devices:view", ResourceType: "device"}
	repo := NewOTARepository(pool)
	// The service always re-reads the firmware: the in-memory upload struct keeps
	// its draft state even after a publish.
	fw, err := repo.GetFirmware(context.Background(), created.ID)
	require.NoError(t, err)

	list, err := repo.ListTaskCandidates(context.Background(), fw, plan, true)
	require.NoError(t, err)
	require.Equal(t, 3, list.Total, "other models stay out of the candidate list")
	require.Equal(t, 3, list.EligibleCount)
	require.Equal(t, 0, list.ExcludedCount)
	bySN := map[string]model.OTATaskCandidate{}
	for _, c := range list.Items {
		bySN[c.SN] = c
	}
	require.True(t, bySN["CAND-A"].Eligible)
	assert.Equal(t, "HW-1", bySN["CAND-A"].BoardCode)
	assert.Equal(t, "1.0", bySN["CAND-A"].CurrentVersion)
	assert.True(t, bySN["CAND-B"].Eligible, "board scope is historical metadata")
	assert.True(t, bySN["CAND-C"].Eligible, "no registry is required")
	_, listed := bySN["CAND-OTHER"]
	assert.False(t, listed)

	hardwareExec(t, pool, `UPDATE device_hardware_registry SET frozen=TRUE WHERE sn='CAND-A'`)
	list, err = repo.ListTaskCandidates(context.Background(), fw, plan, true)
	require.NoError(t, err)
	require.Equal(t, 3, list.EligibleCount, "historical registry state does not block upgrades")
	require.Equal(t, 0, list.ExcludedCount)

	// The candidate list is a projection only: verdicts follow the current row, so
	// re-enabling the registry and reverting the firmware to draft must both show up.
	hardwareExec(t, pool, `UPDATE device_hardware_registry SET frozen=FALSE WHERE sn='CAND-A'`)
	list, err = repo.ListTaskCandidates(context.Background(), fw, plan, true)
	require.NoError(t, err)
	require.Equal(t, 3, list.EligibleCount)

	hardwareExec(t, pool, `UPDATE organization_memberships SET status='revoked' WHERE id=21`)
	denied, err := repo.ListTaskCandidates(context.Background(), fw, plan, true)
	require.NoError(t, err)
	require.Empty(t, denied.Items, "revoked membership cannot list candidates")
	hardwareExec(t, pool, `UPDATE organization_memberships SET status='active' WHERE id=21`)

	hardwareExec(t, pool, `UPDATE firmware_versions SET release_status='draft', status=0 WHERE id=$1`, fw.ID)
	draft, err := repo.GetFirmware(context.Background(), fw.ID)
	require.NoError(t, err)
	list, err = repo.ListTaskCandidates(context.Background(), draft, plan, true)
	require.NoError(t, err)
	require.Equal(t, 0, list.EligibleCount)
	for _, c := range list.Items {
		if c.SN == "CAND-A" {
			assert.Equal(t, "firmware_not_published", c.Reason)
		}
	}
}
