//go:build integration

package repository

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
	"inv-api-server/internal/model"
)

func TestOverviewStationGridPowerPostgres(t *testing.T) {
	pool := setupStationGridTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `INSERT INTO users(id,status,is_system_admin) VALUES(99109,1,true);
	INSERT INTO stations(id) VALUES(99109);
	INSERT INTO devices(sn,station_id,status) VALUES('GRID-A',99109,1),('GRID-B',99109,1),('GRID-OFF',99109,0);
	INSERT INTO device_latest_state(device_sn,ac_input_power,ac_charge_power)
	VALUES('GRID-A',1200,600),('GRID-B',NULL,400),('GRID-OFF',9000,9000);`)
	require.NoError(t, err)
	repo := NewDeviceRepository(pool, nil)
	actor := model.ActorContext{UserID: 99109, RootTenantID: 99109, OrganizationID: 99109, MembershipID: 99109, MembershipVersion: 1}
	read := func() *float64 {
		power, err := repo.GetOverviewStationPower(ctx, model.ScopePlan{Actor: actor, ResourceType: "station"}, model.ScopePlan{Actor: actor, ResourceType: "device"}, true, 99109)
		require.NoError(t, err)
		if power.Grid != nil {
			require.NotNil(t, power.GridUpdatedAt)
		}
		return power.Grid
	}
	require.NotNil(t, read())
	require.Equal(t, 2200.0, *read())
	_, err = pool.Exec(ctx, `UPDATE device_latest_state SET updated_at=NOW()-INTERVAL '6 minutes' WHERE device_sn='GRID-A'`)
	require.NoError(t, err)
	require.Equal(t, 400.0, *read())
	_, err = pool.Exec(ctx, `UPDATE device_latest_state SET ac_charge_power=0 WHERE device_sn='GRID-B'`)
	require.NoError(t, err)
	require.Equal(t, 0.0, *read())
	_, err = pool.Exec(ctx, `UPDATE device_latest_state SET ac_charge_power=NULL WHERE device_sn='GRID-B'`)
	require.NoError(t, err)
	require.Nil(t, read())
}

// Query-focused fixture: grid aggregation does not require TimescaleDB functions.
func setupStationGridTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable",
		envOrFallback("TEST_DB_USER", "testuser"), envOrFallback("TEST_DB_PASSWORD", "testpass"),
		envOrFallback("TEST_DB_HOST", "localhost"), envOrFallback("TEST_DB_PORT", "15432"))
	config, err := pgxpool.ParseConfig(dsn)
	require.NoError(t, err)
	admin, err := pgxpool.NewWithConfig(ctx, config)
	require.NoError(t, err)
	t.Cleanup(admin.Close)
	dbName := fmt.Sprintf("station_grid_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+dbName)
	require.NoError(t, err)
	config.ConnConfig.Database = dbName
	pool, err := pgxpool.NewWithConfig(ctx, config)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Close()
		_, err := admin.Exec(ctx, "DROP DATABASE "+dbName)
		require.NoError(t, err)
	})
	_, err = pool.Exec(ctx, `
	CREATE TABLE users(id bigint PRIMARY KEY,status int,is_system_admin boolean,deleted_at timestamptz);
	CREATE TABLE organizations(id bigint,root_tenant_id bigint,status text,deleted_at timestamptz);
	CREATE TABLE organization_memberships(id bigint,root_tenant_id bigint,user_id bigint,organization_id bigint,version bigint,status text,expires_at timestamptz);
	CREATE TABLE organization_closure(root_tenant_id bigint,ancestor_id bigint,descendant_id bigint);
	CREATE TABLE stations(id bigint PRIMARY KEY,deleted_at timestamptz);
	CREATE TABLE devices(sn text PRIMARY KEY,station_id bigint,status int,deleted_at timestamptz);
	CREATE TABLE device_latest_state(device_sn text PRIMARY KEY,pv_total_power real,ac_active_power real,battery_power real,battery_soc real,
	 ac_input_power real,ac_charge_power real,updated_at timestamptz NOT NULL DEFAULT NOW());
	CREATE TABLE device_telemetry_3min(device_sn text,bms_summary jsonb,received_at timestamptz,event_time timestamptz);`)
	require.NoError(t, err)
	return pool
}
