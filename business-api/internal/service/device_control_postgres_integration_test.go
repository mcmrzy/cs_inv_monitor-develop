//go:build integration

package service

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"inv-api-server/internal/repository"
)

// 设备控制 9 步校验链（ValidateAndPrepareCommand）真库回归，覆盖三条主干：
//  1. 超管旁路 RBAC 后按型号能力准备命令（2026-09 修复的"超管被组织授权误拒"回归）
//  2. 非超管必须同时持有 devices:control RBAC 授权——仅设备数据归属不够
//  3. 未知/禁用/越参命令在步骤 2-4 fail-closed 拒绝

func setupDeviceControlTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()
	host, port := controlEnv("TEST_DB_HOST", "localhost"), controlEnv("TEST_DB_PORT", "15432")
	user, password := controlEnv("TEST_DB_USER", "testuser"), controlEnv("TEST_DB_PASSWORD", "testpass")
	admin, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", user, password, host, port))
	require.NoError(t, err)
	require.NoError(t, admin.Ping(ctx))
	t.Cleanup(func() { admin.Close() })

	dbName := fmt.Sprintf("device_control_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err)
	pool, err := pgxpool.New(ctx, fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, password, host, port, dbName))
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Close()
		_, _ = admin.Exec(ctx, `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=$1`, dbName)
		_, _ = admin.Exec(ctx, "DROP DATABASE IF EXISTS "+dbName)
	})

	contents, err := os.ReadFile(filepath.Clean(filepath.Join("..", "..", "..", "database", "schema.sql")))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(contents))
	require.NoError(t, err)
	replayControlMigrationTail(t, pool)
	return pool
}

// replayControlMigrationTail 回放 database/migrations/ 中 096+ 的 up 迁移，
// 与 MIGRATION_AUTO_RUN 启动回放一致，使测试库与真实生产库形态收敛
//（基线只含 0..95 的 DDL，例如 device_cmd_logs.result 的 TEXT 化在 111）。
func replayControlMigrationTail(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	migrationsDir := filepath.Clean(filepath.Join("..", "..", "..", "database", "migrations"))
	entries, err := os.ReadDir(migrationsDir)
	require.NoError(t, err)
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".up.sql") {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	for _, name := range names {
		num := 0
		fmt.Sscanf(name, "%d", &num)
		if num < 96 {
			continue
		}
		contents, err := os.ReadFile(filepath.Join(migrationsDir, name))
		require.NoError(t, err)
		_, err = pool.Exec(context.Background(), string(contents))
		require.NoError(t, err, "replay %s on squash baseline", name)
	}
}

func controlEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func seedControlFixture(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO users(id, phone, password_hash, is_system_admin, status) VALUES
			(300, 'ctl-owner', 'hash', false, 1),
			(301, 'ctl-superadmin', 'hash', true, 1);
		INSERT INTO device_models(id, model_code, model_name) VALUES (500, 'TST-CTL', 'Control Test Model');
		INSERT INTO devices(sn, model_id, user_id) VALUES ('CTL-SN-001', 500, 300);
		INSERT INTO device_model_commands(model_id, command_code, display_name_key, parameter_schema, is_enabled, permission_code) VALUES
			(500, 'set_output_priority', 'cmd.set_output_priority',
			 '{"args":[{"key":"value","type":"integer","enum":[0,1,2],"unit":""}]}', true, 'devices_control'),
			(500, 'set_max_charge_current', 'cmd.set_max_charge_current',
			 '{"args":[{"key":"value","type":"number","min":0,"max":60,"unit":"A"}]}', true, 'devices_control'),
			(500, 'set_buzzer', 'cmd.set_buzzer',
			 '{"args":[{"key":"value","type":"boolean"}]}', false, NULL);
	`)
	require.NoError(t, err)
}

// seedControlGrantForOwner 给设备属主(user 300)补一条 agents 组织链上的 devices:control 授权。
func seedControlGrantForOwner(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO organizations(id, root_tenant_id, parent_id, org_type, code, name, status) VALUES
			(400, 400, NULL, 'manufacturer', 'CTL-M', 'Ctl Manufacturer', 'active'),
			(401, 400, 400, 'agent', 'CTL-A', 'Ctl Agent', 'active');
		INSERT INTO organization_memberships(id, root_tenant_id, organization_id, user_id, status, version)
			VALUES (4001, 400, 401, 300, 'active', 1);
		INSERT INTO membership_role_assignments(id, root_tenant_id, organization_id, membership_id, role_code, status)
			VALUES (4101, 400, 401, 4001, 'agent', 'active');
		INSERT INTO role_permission_grants(root_tenant_id, organization_id, role_assignment_id, permission_code, data_scope, scope_definition)
			VALUES (400, 401, 4101, 'devices:control', 'organization_and_descendants', '{}'::jsonb);
	`)
	require.NoError(t, err)
}

func newControlTestService(pool *pgxpool.Pool) *DeviceService {
	checker := NewPermChecker(nil, repository.NewUserRepository(pool, nil))
	svc := NewDeviceService(repository.NewDeviceRepository(pool, nil), nil,
		repository.NewModelRepository(pool, nil), checker, "", "", pool)
	// 步骤 5/6 依赖 Redis 在线状态与 BMS 限值，真库测试置 nil 走跳过分支
	svc.limitChecker = nil
	svc.preconditionChecker = nil
	return svc
}

func TestValidateAndPrepareCommandSuperadminBypassesRBACAndPrepares(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	svc := newControlTestService(pool)

	prepared, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 1}, true)
	require.NoError(t, err)
	require.NotNil(t, prepared)
	assert.NotEmpty(t, prepared.TaskID)
	assert.Equal(t, "set_output_priority", prepared.Command)
	assert.True(t, prepared.HasV2Spec)
	require.Len(t, prepared.Args, 1)
	assert.Equal(t, "1", fmt.Sprint(prepared.Args[0]))
	require.NotNil(t, prepared.Caps)
	assert.Equal(t, "set_output_priority", prepared.Caps.CommandCode)
	assert.True(t, prepared.Caps.IsEnabled)
}

func TestValidateAndPrepareCommandRejectsUnknownCommand(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	svc := newControlTestService(pool)

	_, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_nonexistent", nil, true)
	var cmdErr *CommandError
	require.ErrorAs(t, err, &cmdErr)
	assert.Equal(t, ErrUnsupportedCommand, cmdErr.Code)
	assert.Equal(t, 400, cmdErr.StatusCode)
}

func TestValidateAndPrepareCommandRejectsDisabledCommand(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	svc := newControlTestService(pool)

	_, err := svc.ValidateAndPrepareCommand(context.Background(), 301, "CTL-SN-001",
		"set_buzzer", map[string]interface{}{"value": true}, true)
	var cmdErr *CommandError
	require.ErrorAs(t, err, &cmdErr)
	assert.Equal(t, ErrUnsupportedCommand, cmdErr.Code)
	assert.Equal(t, 403, cmdErr.StatusCode)
}

func TestValidateAndPrepareCommandRejectsOutOfRangeAndMissingParams(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	svc := newControlTestService(pool)
	ctx := context.Background()

	for name, params := range map[string]map[string]interface{}{
		"enum 越界": {"value": 9},
		"缺必填参数":   {},
		"未知参数":    {"value": 1, "extra": "x"},
	} {
		t.Run(name, func(t *testing.T) {
			_, err := svc.ValidateAndPrepareCommand(ctx, 301, "CTL-SN-001",
				"set_output_priority", params, true)
			var cmdErr *CommandError
			require.ErrorAs(t, err, &cmdErr)
			assert.Equal(t, ErrInvalidRange, cmdErr.Code)
			assert.Equal(t, 400, cmdErr.StatusCode)
		})
	}
}

func TestValidateAndPrepareCommandOwnerWithoutRBACGrantDenied(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	svc := newControlTestService(pool)

	// user 300 是设备属主但没有 devices:control RBAC 授权：仅数据归属不够
	_, err := svc.ValidateAndPrepareCommand(context.Background(), 300, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 1}, false)
	var cmdErr *CommandError
	require.ErrorAs(t, err, &cmdErr)
	assert.Equal(t, ErrUnsupportedCommand, cmdErr.Code)
	assert.Equal(t, 403, cmdErr.StatusCode)
}

func TestValidateAndPrepareCommandOwnerWithRBACGrantAllowed(t *testing.T) {
	pool := setupDeviceControlTestDB(t)
	seedControlFixture(t, pool)
	seedControlGrantForOwner(t, pool)
	svc := newControlTestService(pool)

	prepared, err := svc.ValidateAndPrepareCommand(context.Background(), 300, "CTL-SN-001",
		"set_output_priority", map[string]interface{}{"value": 2}, false)
	require.NoError(t, err)
	require.NotNil(t, prepared)
	assert.NotEmpty(t, prepared.TaskID)
	require.Len(t, prepared.Args, 1)
	assert.Equal(t, "2", fmt.Sprint(prepared.Args[0]))
}
