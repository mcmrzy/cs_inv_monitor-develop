//go:build integration

package integration

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestMigrationsForward verifies all migration files execute successfully in order.
func TestMigrationsForward(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	migrationsDir := findMigrationsDir(t)
	files := collectUpMigrations(t, migrationsDir)
	require.NotEmpty(t, files, "no migration files found")

	ctx := context.Background()
	for _, f := range files {
		t.Run(f.Name, func(t *testing.T) {
			sql, err := os.ReadFile(filepath.Join(migrationsDir, f.Name))
			require.NoError(t, err, "read migration file %s", f.Name)

			_, err = pool.Exec(ctx, string(sql))
			require.NoError(t, err, "execute migration %s", f.Name)
		})
	}
}

// TestCriticalTablesExist verifies that key tables are present after migrations.
func TestCriticalTablesExist(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	expectedTables := []string{
		"users",
		"devices",
		"stations",
		"alarms",
		"device_telemetry",
		"device_models",
		"device_model_field",
		"device_protocol_versions",
		"device_alarms",
		"device_cmd_logs",
		"device_day_data",
		"station_day_data",
		"firmware_versions",
		"device_upgrades",
		"device_telemetry_3min",
		"device_latest_state",
		"user_device_rel",
		"system_configs",
		"notifications",
		"alarm_notifications",
		"user_operation_logs",
		"verification_codes",
		"regions",
	}

	ctx := context.Background()
	rows, err := pool.Query(ctx, `
		SELECT table_name
		FROM information_schema.tables
		WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
	`)
	require.NoError(t, err)
	defer rows.Close()

	existing := make(map[string]bool)
	for rows.Next() {
		var name string
		require.NoError(t, rows.Scan(&name))
		existing[name] = true
	}

	for _, table := range expectedTables {
		t.Run(table, func(t *testing.T) {
			assert.True(t, existing[table], "table %q should exist", table)
		})
	}
}

// TestCriticalIndexesExist verifies that key indexes were created.
func TestCriticalIndexesExist(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	expectedIndexes := []string{
		"idx_users_phone",
		"idx_users_role",
		"idx_devices_sn",
		"idx_devices_user",
		"idx_devices_status",
		"idx_stations_user",
		"idx_alarms_device",
		"idx_alarms_time",
		"idx_telemetry_sn_time",
		"idx_telemetry_time",
		"idx_device_alarms_sn",
		"idx_cmd_logs_sn",
	}

	ctx := context.Background()
	rows, err := pool.Query(ctx, `
		SELECT indexname
		FROM pg_indexes
		WHERE schemaname = 'public'
	`)
	require.NoError(t, err)
	defer rows.Close()

	existing := make(map[string]bool)
	for rows.Next() {
		var name string
		require.NoError(t, rows.Scan(&name))
		existing[name] = true
	}

	for _, idx := range expectedIndexes {
		t.Run(idx, func(t *testing.T) {
			assert.True(t, existing[idx], "index %q should exist", idx)
		})
	}
}

// TestTimescaleDBHypertable verifies the device_telemetry hypertable is configured correctly.
func TestTimescaleDBHypertable(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	// Check that timescaledb extension is enabled
	var extName string
	err := pool.QueryRow(ctx, `SELECT extname FROM pg_extension WHERE extname = 'timescaledb'`).Scan(&extName)
	require.NoError(t, err, "TimescaleDB extension should be installed")
	assert.Equal(t, "timescaledb", extName)

	// Check that device_telemetry is a hypertable
	var hypertableCount int
	err = pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM _timescaledb_catalog.hypertable
		WHERE table_name = 'device_telemetry'
	`).Scan(&hypertableCount)
	require.NoError(t, err)
	assert.Equal(t, 1, hypertableCount, "device_telemetry should be a hypertable")

	// Check compression policy exists
	var compressionPolicyCount int
	err = pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM timescaledb_information.jobs
		WHERE proc_name = 'policy_compression'
		  AND hypertable_name = 'device_telemetry'
	`).Scan(&compressionPolicyCount)
	require.NoError(t, err)
	assert.GreaterOrEqual(t, compressionPolicyCount, 1, "compression policy should exist for device_telemetry")
}

// TestTimescaleDBContinuousAggregates verifies continuous aggregates are created.
func TestTimescaleDBContinuousAggregates(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	aggregates := []string{
		"device_telemetry_1min",
		"device_telemetry_1hour",
		"device_telemetry_1day",
		"device_telemetry_hour",
	}

	for _, agg := range aggregates {
		t.Run(agg, func(t *testing.T) {
			var count int
			err := pool.QueryRow(ctx, `
				SELECT COUNT(*) FROM timescaledb_information.continuous_aggregates
				WHERE view_name = $1
			`, agg).Scan(&count)
			require.NoError(t, err)
			assert.Equal(t, 1, count, "continuous aggregate %q should exist", agg)
		})
	}
}

// TestTelemetryInsertAndQuery verifies we can insert and query telemetry data.
func TestTelemetryInsertAndQuery(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()
	testSN := fmt.Sprintf("INTEGRATION-TEST-%d", time.Now().UnixNano())

	// Insert test telemetry data
	for i := 0; i < 10; i++ {
		_, err := pool.Exec(ctx, `
			INSERT INTO device_telemetry (device_sn, model_code, topic, data, total_active_power, daily_energy, work_state, internal_temperature, time)
			VALUES ($1, 'INV-5000-TL', 'cs_inv/test/data/status',
				'{"voltage": 220.5, "current": 10.2}'::jsonb,
				$2, $3, 'running', $4, $5)
		`, testSN, 2250.0+float64(i)*10, float64(i)*0.5, 35.5+float64(i)*0.1,
			time.Now().Add(-time.Duration(10-i)*time.Minute))
		require.NoError(t, err)
	}

	// Query back
	var count int
	err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_telemetry WHERE device_sn = $1`, testSN).Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 10, count)

	// Query latest view
	var latestSN string
	var latestPower float64
	err = pool.QueryRow(ctx, `
		SELECT device_sn, total_active_power FROM v_device_latest WHERE device_sn = $1
	`, testSN).Scan(&latestSN, &latestPower)
	require.NoError(t, err)
	assert.Equal(t, testSN, latestSN)
	assert.Greater(t, latestPower, 0.0)

	// Cleanup
	_, _ = pool.Exec(ctx, `DELETE FROM device_telemetry WHERE device_sn = $1`, testSN)
}

// TestTriggersAndFunctions verifies update_updated_at_column trigger function works.
func TestTriggersAndFunctions(t *testing.T) {
	cfg := LoadConfig()
	requireService(t, cfg.DBHost, cfg.DBPort, "PostgreSQL")
	pool := ConnectDB(t, cfg)
	defer pool.Close()

	ctx := context.Background()

	// Insert a test user
	testPhone := fmt.Sprintf("138%08d", time.Now().UnixNano()%100000000)
	_, err := pool.Exec(ctx, `
		INSERT INTO users (phone, password_hash, nickname, role, status)
		VALUES ($1, '$2a$10$dummyhash', 'trigger-test', 5, 1)
	`, testPhone)
	require.NoError(t, err)

	// Get initial updated_at
	var initialUpdatedAt time.Time
	err = pool.QueryRow(ctx, `SELECT updated_at FROM users WHERE phone = $1`, testPhone).Scan(&initialUpdatedAt)
	require.NoError(t, err)

	// Wait and update
	time.Sleep(1100 * time.Millisecond)
	_, err = pool.Exec(ctx, `UPDATE users SET nickname = 'trigger-updated' WHERE phone = $1`, testPhone)
	require.NoError(t, err)

	// Check updated_at changed
	var newUpdatedAt time.Time
	err = pool.QueryRow(ctx, `SELECT updated_at FROM users WHERE phone = $1`, testPhone).Scan(&newUpdatedAt)
	require.NoError(t, err)
	assert.True(t, newUpdatedAt.After(initialUpdatedAt), "updated_at should be auto-updated by trigger")

	// Cleanup
	_, _ = pool.Exec(ctx, `DELETE FROM users WHERE phone = $1`, testPhone)
}

// ---------- helpers ----------

type migrationFile struct {
	Name   string
	Number int
}

func findMigrationsDir(t *testing.T) string {
	t.Helper()
	// Try common paths
	candidates := []string{
		"../../database/migrations",
		"../../../database/migrations",
		filepath.Join(os.Getenv("PROJECT_ROOT"), "database/migrations"),
	}
	for _, p := range candidates {
		abs, _ := filepath.Abs(p)
		if info, err := os.Stat(abs); err == nil && info.IsDir() {
			return abs
		}
	}
	t.Skip("migrations directory not found; set PROJECT_ROOT env var")
	return ""
}

func collectUpMigrations(t *testing.T, dir string) []migrationFile {
	t.Helper()
	entries, err := os.ReadDir(dir)
	require.NoError(t, err)

	var files []migrationFile
	for _, e := range entries {
		name := e.Name()
		if strings.HasSuffix(name, ".up.sql") || (strings.HasSuffix(name, ".sql") && !strings.Contains(name, ".down.")) {
			num := 0
			fmt.Sscanf(name, "%d", &num)
			files = append(files, migrationFile{Name: name, Number: num})
		}
	}
	sort.Slice(files, func(i, j int) bool {
		return files[i].Number < files[j].Number
	})
	return files
}
