//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

func overviewTestDB(t *testing.T) *pgxpool.Pool {
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
	name := fmt.Sprintf("overview_%d", time.Now().UnixNano())
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
	schema, err := os.ReadFile(filepath.Join(root, "database", "schema.sql"))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(schema))
	require.NoError(t, err)
	paths, err := filepath.Glob(filepath.Join(root, "database", "migrations", "*.up.sql"))
	require.NoError(t, err)
	sort.Strings(paths)
	for _, path := range paths {
		var version int
		_, err := fmt.Sscanf(filepath.Base(path), "%d", &version)
		require.NoError(t, err)
		if version < 96 {
			continue
		}
		data, err := os.ReadFile(path)
		require.NoError(t, err)
		_, err = pool.Exec(ctx, string(data))
		require.NoError(t, err, filepath.Base(path))
	}
	return pool
}

func overviewRequest(t *testing.T, actor model.ActorContext, admin bool, path string, handler gin.HandlerFunc) map[string]any {
	t.Helper()
	recorder := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(recorder)
	c.Request = httptest.NewRequest("GET", path, nil)
	c.Set("user_id", actor.UserID)
	c.Set("actor_context", actor)
	c.Set("is_system_admin", admin)
	handler(c)
	var result map[string]any
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &result), recorder.Body.String())
	return result
}

func TestOrganizationOverviewPostgres(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status,is_system_admin) VALUES
			(9700,'overview-parent','hash',1,false),(9701,'overview-child','hash',1,false),
			(9702,'overview-sibling','hash',1,false),(9703,'overview-tenant','hash',1,false),
			(9704,'overview-admin','hash',1,true),(9705,'overview-multi','hash',1,false);
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status) VALUES
			(9800,9800,NULL,'manufacturer','OV-R','Root','active'),
			(9801,9800,9800,'agent','OV-A','Agent','active'),
			(9804,9800,9801,'distributor','OV-D','Distributor','active'),
			(9805,9800,9804,'installer','OV-I','Installer','active'),
			(9802,9800,9805,'customer','OV-C','Child','active'),
			(9803,9800,9800,'agent','OV-S','Sibling','active'),
			(9900,9900,NULL,'manufacturer','OV-T','Tenant','active'),
			(9901,9900,9900,'customer','OV-TC','Tenant Child','active');
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status,version) VALUES
			(9811,9800,9801,9700,'active',1),(9812,9800,9803,9700,'active',1),
			(9813,9800,9802,9701,'active',1),(9814,9800,9803,9702,'active',1),
			(9815,9900,9901,9703,'active',1),(9816,9800,9800,9704,'active',1),
			(9817,9800,9802,9705,'active',1),(9818,9900,9901,9705,'active',1);
		INSERT INTO membership_role_assignments(id,root_tenant_id,organization_id,membership_id,role_code,status) VALUES
			(9821,9800,9801,9811,'agent','active'),(9822,9800,9803,9812,'agent','active');
		INSERT INTO role_permission_grants(id,root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope) VALUES
			(9831,9800,9801,9821,'devices:view','organization_and_descendants'),
			(9832,9800,9801,9821,'stations:view','organization_and_descendants'),
			(9833,9800,9803,9822,'devices:view','organization'),
			(9834,9800,9803,9822,'stations:view','organization');
		INSERT INTO stations(id,user_id,name,province,city,address,capacity) VALUES
			(9850,9700,'Parent','','','',1),(10200,9702,'Sibling','','','',1),(10201,9703,'Tenant','','','',1);
		INSERT INTO stations(id,user_id,name,province,city,address,capacity)
			SELECT 10000+n,9701,'Child '||n,'','','',1 FROM generate_series(0,100) n;
		INSERT INTO devices(sn,model,user_id,station_id,status) VALUES
			('OV-P','TEST',9700,9850,1),('OV-A','TEST',9701,10000,1),('OV-B','TEST',9701,10100,2),
			('OV-S','TEST',9702,10200,1),('OV-T','TEST',9703,10201,1),('OV-M','TEST',9705,10201,1);
		INSERT INTO authorization_resources(root_tenant_id,organization_id,resource_type,resource_id,status)
			VALUES(9900,9901,'device','OV-M','active'),(9800,9801,'device','OV-P','active'),
			(9800,9801,'station','9850','active');
		INSERT INTO device_latest_state(device_sn,total_pv_energy,protocol_version,sequence_no,event_time,received_at) VALUES
			('OV-P',100,2,1,NOW(),NOW()),('OV-A',0,2,1,NOW(),NOW()),('OV-B',0,2,1,NOW(),NOW()),
			('OV-S',999,2,1,NOW(),NOW()),('OV-T',999,2,1,NOW(),NOW()),('OV-M',999,2,1,NOW(),NOW());
		INSERT INTO device_energy_day(device_sn,stat_date,pv_energy,total_pv_energy,timezone) VALUES
			('OV-P',CURRENT_DATE,2,100,'Asia/Shanghai'),('OV-A',CURRENT_DATE,10,70,'Asia/Shanghai'),
			('OV-A',CURRENT_DATE-1,20,70,'Asia/Shanghai'),('OV-B',CURRENT_DATE,7,20,'Asia/Shanghai');
	`)
	require.NoError(t, err)
	actor := model.ActorContext{UserID: 9700, RootTenantID: 9800, OrganizationID: 9801, MembershipID: 9811, MembershipVersion: 1}
	refreshActor := func() {
		require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=$1", actor.MembershipID).Scan(&actor.MembershipVersion))
	}
	refreshActor()
	plan, isAdmin, scopeErr := loadOverviewScope(ctx, pool, actor, false, "device")
	require.NoError(t, scopeErr)
	filter, args := repository.OverviewScopeFilter(plan, isAdmin, "d", 1)
	var scopedCount int64
	require.NoError(t, pool.QueryRow(ctx, "SELECT COUNT(*) FROM devices d WHERE d.deleted_at IS NULL AND "+filter, args...).Scan(&scopedCount))
	dashboard := NewDashboardHandler(pool, nil)
	stations := NewStationHandler(service.NewStationService(repository.NewStationRepository(pool)),
		service.NewDeviceService(repository.NewDeviceRepository(pool, nil), nil, nil, nil, "", "", pool), nil, pool, "")
	check := func(path string, handler gin.HandlerFunc) map[string]any {
		result := overviewRequest(t, actor, false, path, handler)
		require.Equal(t, float64(0), result["code"], result)
		return result["data"].(map[string]any)
	}
	t.Run("ancestor dashboard and SSE exclude sibling tenant and foreign registered asset", func(t *testing.T) {
		data := check("/dashboard/statistics", dashboard.GetStatistics)
		require.Equal(t, float64(3), data["deviceStats"].(map[string]any)["total"])
		require.Equal(t, float64(190), data["totalEnergy"], "retain historical counters after reset; never sum repeated absolute counters")
		require.Contains(t, data["totalEnergyProvenance"], "recorded_counter")
		plan, admin, err := loadOverviewScope(ctx, pool, actor, false, "device")
		require.NoError(t, err)
		stream, err := dashboard.collectDashboardSSEData(ctx, plan, admin)
		require.NoError(t, err)
		require.Equal(t, int64(3), stream["deviceStats"].(map[string]any)["total"])
	})
	t.Run("summary and page two include more than one hundred descendant stations", func(t *testing.T) {
		data := check("/stations?page=2&page_size=100", stations.List)
		require.Equal(t, float64(102), data["total"])
		require.Len(t, data["items"], 2)
		data = check("/stations/summary", stations.GetSummary)
		require.Len(t, data["stations"], 102)
		require.Equal(t, float64(102), data["summary"].(map[string]any)["totalStations"])
		require.Equal(t, float64(3), data["summary"].(map[string]any)["totalDevices"])
	})
	t.Run("station energy filter parameter offsets", func(t *testing.T) {
		result := overviewRequest(t, actor, false, "/dashboard/energy-stats?stationId=10000", dashboard.GetEnergyStats)
		require.Equal(t, float64(0), result["code"], result)
	})
	t.Run("selected context switch", func(t *testing.T) {
		switched := actor
		switched.OrganizationID, switched.MembershipID = 9803, 9812
		require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9812").Scan(&switched.MembershipVersion))
		data := overviewRequest(t, switched, false, "/dashboard/statistics", dashboard.GetStatistics)
		require.Equal(t, float64(0), data["code"], data)
		require.Equal(t, float64(1), data["data"].(map[string]any)["deviceStats"].(map[string]any)["total"])
		switched.MembershipID = 9811
		require.Equal(t, float64(403), overviewRequest(t, switched, false, "/dashboard/statistics", dashboard.GetStatistics)["code"])
	})
	for _, tc := range []struct{ name, disable, restore string }{
		{"disabled actor", "UPDATE users SET status=0 WHERE id=9700", "UPDATE users SET status=1 WHERE id=9700"},
		{"expired membership", "UPDATE organization_memberships SET expires_at=NOW()-INTERVAL '1 second' WHERE id=9811", "UPDATE organization_memberships SET expires_at=NULL WHERE id=9811"},
		{"stale membership version", "UPDATE organization_memberships SET version=2 WHERE id=9811", "UPDATE organization_memberships SET version=1 WHERE id=9811"},
		{"disabled ancestor", "UPDATE organizations SET status='disabled' WHERE id=9800", "UPDATE organizations SET status='active' WHERE id=9800"},
		{"revoked grant assignment", "UPDATE membership_role_assignments SET status='revoked' WHERE id=9821", "UPDATE membership_role_assignments SET status='active' WHERE id=9821"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			refreshActor()
			plan, admin, err := loadOverviewScope(ctx, pool, actor, false, "device")
			require.NoError(t, err)
			_, err = pool.Exec(ctx, tc.disable)
			require.NoError(t, err)
			defer func() { _, err := pool.Exec(ctx, tc.restore); require.NoError(t, err); refreshActor() }()
			require.Equal(t, float64(403), overviewRequest(t, actor, false, "/dashboard/statistics", dashboard.GetStatistics)["code"])
			require.Equal(t, float64(403), overviewRequest(t, actor, false, "/stations/summary", stations.GetSummary)["code"])
			stream, err := dashboard.collectDashboardSSEData(ctx, plan, admin)
			require.NoError(t, err)
			require.Equal(t, int64(0), stream["deviceStats"].(map[string]any)["total"], "stale plans must fail closed at final SQL")
		})
	}
	t.Run("scope definition restricts descendants", func(t *testing.T) {
		_, err := pool.Exec(ctx, `UPDATE role_permission_grants SET scope_definition='{"organization_ids":["9802"]}' WHERE id IN(9831,9832)`)
		require.NoError(t, err)
		defer func() {
			_, err := pool.Exec(ctx, "UPDATE role_permission_grants SET scope_definition='{}' WHERE id IN(9831,9832)")
			require.NoError(t, err)
			refreshActor()
		}()
		refreshActor()
		require.Equal(t, float64(2), check("/dashboard/statistics", dashboard.GetStatistics)["deviceStats"].(map[string]any)["total"])
		require.Equal(t, float64(101), check("/stations/summary", stations.GetSummary)["summary"].(map[string]any)["totalStations"])
	})
	t.Run("system admin is database validated and includes all active assets", func(t *testing.T) {
		adminActor := model.ActorContext{UserID: 9704, RootTenantID: 9800, OrganizationID: 9800, MembershipID: 9816, MembershipVersion: 1}
		data := overviewRequest(t, adminActor, true, "/dashboard/statistics", dashboard.GetStatistics)
		require.Equal(t, float64(0), data["code"], data)
		require.Equal(t, float64(6), data["data"].(map[string]any)["deviceStats"].(map[string]any)["total"])
		data = overviewRequest(t, adminActor, true, "/stations/summary", stations.GetSummary)
		require.Equal(t, float64(0), data["code"], data)
		require.Len(t, data["data"].(map[string]any)["stations"], 104)
		require.Equal(t, float64(403), overviewRequest(t, actor, true, "/dashboard/statistics", func(c *gin.Context) {
			copy := actor
			copy.OrganizationID = 9901
			c.Set("actor_context", copy)
			dashboard.GetStatistics(c)
		})["code"])
		_, err := pool.Exec(ctx, "UPDATE users SET is_system_admin=false WHERE id=9704")
		require.NoError(t, err)
		require.Equal(t, float64(403), overviewRequest(t, adminActor, true, "/dashboard/statistics", dashboard.GetStatistics)["code"])
	})
}

func TestDashboardCounterPolicyPostgres(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status) VALUES(9700,'counter-owner','hash',1);
		INSERT INTO devices(sn,model,user_id) VALUES ('COUNTER-TEST','TEST',9700);
		INSERT INTO device_latest_state(device_sn,total_pv_energy,protocol_version,sequence_no,event_time,received_at)
			VALUES ('COUNTER-TEST',50,2,1,NOW(),NOW());
		INSERT INTO device_energy_day(device_sn,stat_date,pv_energy,total_pv_energy,timezone) VALUES
			('COUNTER-TEST',CURRENT_DATE-2,30,50,'Asia/Shanghai'),('COUNTER-TEST',CURRENT_DATE-1,30,50,'Asia/Shanghai'),
			('COUNTER-TEST',CURRENT_DATE,30,50,'Asia/Shanghai');`)
	require.NoError(t, err)
	for _, value := range []string{"0", "NULL", "-1", "'Infinity'", "'NaN'", "100"} {
		_, err := pool.Exec(ctx, "UPDATE device_latest_state SET total_pv_energy="+value+" WHERE device_sn='COUNTER-TEST'")
		require.NoError(t, err)
		var total float64
		require.NoError(t, pool.QueryRow(ctx, dashboardTotalEnergySQL, []string{"COUNTER-TEST"}).Scan(&total))
		want := 90.0
		if strings.EqualFold(value, "100") {
			want = 100
		}
		require.Equal(t, want, total, value)
	}
}
