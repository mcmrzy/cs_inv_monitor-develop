//go:build integration

package handler

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

// assignmentTestDB loads the actual relational DDL needed by the assignment
// handlers into an isolated PostgreSQL database. This fixture deliberately does
// not load or emulate TimescaleDB, compression policies, or full migrations.
// Existing overview tests retain their complete TimescaleDB bootstrap.
func assignmentTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	env := func(key, fallback string) string {
		if value := os.Getenv(key); value != "" {
			return value
		}
		return fallback
	}
	ctx := context.Background()
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/", env("TEST_DB_USER", "testuser"), env("TEST_DB_PASSWORD", "testpass"),
		env("TEST_DB_HOST", "localhost"), env("TEST_DB_PORT", "15432"))
	admin, err := pgxpool.New(ctx, dsn+"postgres?sslmode=disable")
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))
	name := fmt.Sprintf("assignment_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+name)
	require.NoError(t, err)
	pool, err := pgxpool.New(ctx, dsn+name+"?sslmode=disable")
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Close()
		_, err := admin.Exec(ctx, "DROP DATABASE "+name+" WITH (FORCE)")
		require.NoError(t, err)
		admin.Close()
	})
	root := filepath.Join("..", "..", "..")
	read := func(parts ...string) string {
		data, err := os.ReadFile(filepath.Join(append([]string{root, "database"}, parts...)...))
		require.NoError(t, err)
		return strings.ReplaceAll(string(data), "\r\n", "\n")
	}
	schema := read("schema.sql")
	exec := func(sql, description string) {
		_, err := pool.Exec(ctx, sql)
		require.NoError(t, err, description)
	}
	// Extract complete original statements instead of maintaining simplified
	// copies of the production columns and relational constraints.
	table := func(name string) {
		pattern := `(?ms)^CREATE TABLE IF NOT EXISTS ` + regexp.QuoteMeta(name) + ` \(.*?^\);`
		statement := regexp.MustCompile(pattern).FindString(schema)
		require.NotEmpty(t, statement, "schema table %s", name)
		exec(statement, "load table "+name)
	}
	for _, name := range []string{"users", "stations", "device_models", "devices", "user_device_rel", "device_latest_state", "device_telemetry_3min", "audit_logs"} {
		table(name)
	}
	modelLifecycle := regexp.MustCompile(`(?m)^ALTER TABLE device_models ADD COLUMN IF NOT EXISTS lifecycle_status .*;`).FindString(schema)
	require.NotEmpty(t, modelLifecycle)
	exec(modelLifecycle, "load model lifecycle column")
	start := strings.Index(schema, "CREATE TABLE IF NOT EXISTS organizations (")
	require.NotEqual(t, -1, start)
	end := strings.Index(schema[start:], "-- 成员转移审批表")
	require.NotEqual(t, -1, end)
	exec(schema[start:start+end], "load organization hierarchy and membership DDL")
	for _, name := range []string{"membership_role_assignments", "role_permission_grants", "authorization_resources", "resource_grants"} {
		table(name)
	}
	exec(read("migrations.archive", "067_add_authorization_session_versions.up.sql"), "load authorization version triggers")
	view := regexp.MustCompile(`(?ms)^CREATE OR REPLACE VIEW v_device_latest AS.*?^FROM device_latest_state;`).FindString(schema)
	require.NotEmpty(t, view)
	exec(view, "load latest telemetry view")
	deviceColumns := regexp.MustCompile(`(?ms)^ALTER TABLE devices\n.*?;`).FindString(read("migrations", "096_add_csl10_6k2_v21.up.sql"))
	require.NotEmpty(t, deviceColumns)
	exec(deviceColumns, "load device information columns from migration 096")
	exec(read("migrations", "126_arm_cmd08_bms_summary.up.sql"), "load optional BMS summary columns")
	return pool
}
