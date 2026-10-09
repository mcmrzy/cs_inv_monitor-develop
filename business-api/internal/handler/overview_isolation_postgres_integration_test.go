//go:build integration

package handler

import (
	"context"
	"io"
	"strings"
	"testing"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestStationOverviewDeviceIsolationPostgres(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status) VALUES(9600,'overview-isolation','hash',1);
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status) VALUES
			(9600,9600,NULL,'manufacturer','ISO-R','Root','active'),
			(9601,9600,9600,'agent','ISO-A','Agent','active'),
			(9602,9600,9600,'agent','ISO-S','Sibling','active'),
			(9603,9603,NULL,'manufacturer','ISO-T','Tenant','active');
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status,version)
			VALUES(9610,9600,9601,9600,'active',1);
		INSERT INTO membership_role_assignments(id,root_tenant_id,organization_id,membership_id,role_code,status)
			VALUES(9611,9600,9601,9610,'agent','active');
		INSERT INTO role_permission_grants(id,root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope) VALUES
			(9612,9600,9601,9611,'stations:view','organization'),
			(9613,9600,9601,9611,'devices:view','organization');
		INSERT INTO stations(id,user_id,name,province,city,address,capacity,timezone)
			VALUES(9620,9600,'Visible station','','','',10,'UTC');
		INSERT INTO devices(sn,model,user_id,station_id,status) VALUES
			('ISO-OWN','TEST',9600,9620,1),('ISO-SIBLING','TEST',9600,9620,2),('ISO-TENANT','TEST',9600,9620,1);
		INSERT INTO authorization_resources(root_tenant_id,organization_id,resource_type,resource_id,status) VALUES
			(9600,9601,'station','9620','active'),(9600,9601,'device','ISO-OWN','active'),
			(9600,9602,'device','ISO-SIBLING','active'),(9603,9603,'device','ISO-TENANT','active');
		INSERT INTO device_latest_state(device_sn,protocol_version,sequence_no,event_time,received_at,ac_active_power,total_pv_energy,pv_total_power,battery_power,battery_soc) VALUES
			('ISO-OWN',2,1,NOW(),NOW(),123,100,321,444,20),('ISO-SIBLING',2,1,NOW(),NOW(),999,9000,999,999,99),('ISO-TENANT',2,1,NOW(),NOW(),999,9000,999,999,99);
		INSERT INTO device_telemetry_3min(device_sn,protocol_version,sequence_no,event_time,received_at,data_hash,bms_summary)
			SELECT sn,2,1,NOW()-INTERVAL '1 minute',NOW(),sn,jsonb_build_object('layout',0,'bms_online',1,'soc',80,'voltage',51.2,'current',-12,'expires_at',NOW()+INTERVAL '200 seconds')
			FROM devices WHERE sn IN ('ISO-OWN','ISO-SIBLING','ISO-TENANT');
		INSERT INTO device_energy_day(device_sn,stat_date,timezone,pv_energy,total_pv_energy) VALUES
			('ISO-OWN',CURRENT_DATE,'UTC',7,100),('ISO-SIBLING',CURRENT_DATE,'UTC',999,9000),('ISO-TENANT',CURRENT_DATE,'UTC',999,9000)
			ON CONFLICT(device_sn,stat_date) DO UPDATE SET pv_energy=EXCLUDED.pv_energy,total_pv_energy=EXCLUDED.total_pv_energy;
	`)
	require.NoError(t, err)
	actor := model.ActorContext{UserID: 9600, RootTenantID: 9600, OrganizationID: 9601, MembershipID: 9610}
	refresh := func() {
		require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9610").Scan(&actor.MembershipVersion))
	}
	refresh()
	h := NewStationHandler(service.NewStationService(repository.NewStationRepository(pool)),
		service.NewDeviceService(repository.NewDeviceRepository(pool, nil), nil, nil, nil, "", "", pool), nil, pool, "")
	check := func(wantDevices, wantEnergy, wantPower float64) {
		listed := overviewRequest(t, actor, false, "/stations", h.List)
		require.Equal(t, float64(0), listed["code"], listed)
		items := listed["data"].(map[string]any)["items"].([]any)
		require.Len(t, items, 1)
		item := items[0].(map[string]any)
		require.Equal(t, wantDevices, item["device_count"])
		require.Equal(t, wantDevices, item["online_count"])
		require.Equal(t, float64(0), item["fault_count"])
		require.Equal(t, wantEnergy, item["today_generation"])
		wantTotal := 0.0
		if wantDevices > 0 {
			wantTotal = 100
		}
		require.Equal(t, wantTotal, item["total_generation"])
		result := overviewRequest(t, actor, false, "/stations/summary", h.GetSummary)
		require.Equal(t, float64(0), result["code"], result)
		data := result["data"].(map[string]any)
		summary := data["summary"].(map[string]any)
		require.Equal(t, float64(1), summary["totalStations"])
		require.Equal(t, wantDevices, summary["totalDevices"])
		require.Equal(t, wantEnergy, summary["todayGeneration"])
		require.Equal(t, wantEnergy, summary["monthGeneration"])
		require.Equal(t, wantTotal, summary["totalGeneration"])
		require.Equal(t, wantPower, summary["total_power"])
		detail := overviewRequest(t, actor, false, "/stations/9620", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "id", Value: "9620"}}
			h.GetByID(c)
		})
		require.Equal(t, float64(0), detail["code"], detail)
		data = detail["data"].(map[string]any)
		require.Len(t, data["devices"], int(wantDevices))
		station := data["station"].(map[string]any)
		require.Equal(t, wantDevices, station["device_count"])
		require.Equal(t, wantEnergy, station["today_energy"])
		require.Equal(t, wantEnergy, station["month_energy"])
		require.Equal(t, wantEnergy, station["year_energy"])
		require.Equal(t, wantTotal, station["total_energy"])
		require.Equal(t, wantPower, station["total_power"])
		require.Equal(t, wantPower, station["load_power"])
		if wantDevices > 0 {
			require.Equal(t, float64(321), station["pv_power"])
			require.InDelta(t, -614.4, station["batt_power"], 0.001)
			require.Equal(t, float64(80), station["batt_soc"])
			require.Equal(t, "ISO-OWN", data["devices"].([]any)[0].(map[string]any)["sn"])
		} else {
			require.Zero(t, station["pv_power"])
			require.Zero(t, station["batt_power"])
			require.Zero(t, station["batt_soc"])
		}
		history := overviewRequest(t, actor, false, "/stations/9620/statistics", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "id", Value: "9620"}}
			h.GetStatistics(c)
		})
		require.Equal(t, float64(0), history["code"], history)
		if wantDevices == 0 {
			require.Empty(t, history["data"])
		} else {
			items := history["data"].([]any)
			require.Len(t, items, 1)
			require.Equal(t, wantEnergy, items[0].(map[string]any)["energy_produce"])
		}
		hourly := overviewRequest(t, actor, false, "/stations/9620/statistics?period=hour", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "id", Value: "9620"}}
			h.GetStatistics(c)
		})
		require.Equal(t, float64(0), hourly["code"], hourly)
		if wantDevices == 0 {
			require.Empty(t, hourly["data"])
		}
	}
	check(1, 7, 123)
	_, err = pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status) VALUES(9604,'overview-descendant','hash',1);
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status)
			VALUES(9604,9600,9601,'distributor','ISO-C','Child','active');
		UPDATE stations SET user_id=9604 WHERE id=9620;
		UPDATE authorization_resources SET organization_id=9604 WHERE resource_type='station' AND resource_id='9620';
		UPDATE role_permission_grants SET data_scope='organization_and_descendants' WHERE id=9612;
	`)
	require.NoError(t, err)
	refresh()
	check(1, 7, 123)
	for _, write := range []gin.HandlerFunc{h.Update, h.Delete, h.Assign} {
		result := overviewRequest(t, actor, false, "/stations/9620", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "id", Value: "9620"}}
			c.Request.Method = "PUT"
			c.Request.Header.Set("Content-Type", "application/json")
			c.Request.Body = io.NopCloser(strings.NewReader(`{"user_id":9600}`))
			write(c)
		})
		require.Equal(t, float64(403), result["code"], result)
	}
	allowed, err := h.stationService.HasAccess(ctx, actor.UserID, 9620)
	require.NoError(t, err)
	require.False(t, allowed, "read scope must not expand legacy write access")
	stationPlan, admin, err := loadOverviewScope(ctx, pool, actor, false, "station")
	require.NoError(t, err)
	devicePlan, _, err := loadOverviewScope(ctx, pool, actor, false, "device")
	require.NoError(t, err)
	_, err = pool.Exec(ctx, "DELETE FROM role_permission_grants WHERE id=9613")
	require.NoError(t, err)
	refresh()
	check(0, 0, 0)
	stats, err := service.NewStationService(repository.NewStationRepository(pool)).OverviewDeviceStats(ctx, stationPlan, devicePlan, admin, []int64{9620})
	require.NoError(t, err)
	require.Zero(t, stats[9620].DeviceCount, "cached grants must be rechecked in final SQL")
	devices, err := h.deviceService.GetOverviewStationDevices(ctx, stationPlan, devicePlan, admin, 9620)
	require.NoError(t, err)
	require.Empty(t, devices)
	power, err := h.deviceService.GetOverviewStationPower(ctx, stationPlan, devicePlan, admin, 9620)
	require.NoError(t, err)
	require.Zero(t, power)
	history, err := h.stationService.GetOverviewStatistics(ctx, stationPlan, devicePlan, admin, 9620, "2000-01-01", "2100-01-01", "day", "UTC")
	require.NoError(t, err)
	require.Empty(t, history, "cached grants must not expose historical device data")
	_, err = pool.Exec(ctx, "UPDATE authorization_resources SET organization_id=9602 WHERE resource_type='station' AND resource_id='9620'")
	require.NoError(t, err)
	for _, read := range []gin.HandlerFunc{h.GetByID, h.GetStatistics} {
		result := overviewRequest(t, actor, false, "/stations/9620", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "id", Value: "9620"}}
			read(c)
		})
		require.Equal(t, float64(403), result["code"], "registered station transfer must hide detail and history")
	}
}

func TestSyntheticAdminOverviewPostgres(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status,is_system_admin) VALUES(9500,'synthetic-admin','hash',1,true);
		INSERT INTO stations(id,user_id,name,province,city,address,capacity,timezone) VALUES(9501,9500,'Admin station','','','',10,'UTC');
		INSERT INTO devices(sn,model,user_id,station_id,status) VALUES('SYNTHETIC-DEVICE','TEST',9500,9501,1);
	`)
	require.NoError(t, err)
	actor := model.ActorContext{UserID: 9500, RootTenantID: 9500, OrganizationID: 9500, MembershipID: 9500, MembershipVersion: 1}
	dashboard := NewDashboardHandler(pool, nil)
	stations := NewStationHandler(service.NewStationService(repository.NewStationRepository(pool)),
		service.NewDeviceService(repository.NewDeviceRepository(pool, nil), nil, nil, nil, "", "", pool), nil, pool, "")
	checkReads := func(want float64) {
		for _, read := range []gin.HandlerFunc{stations.GetByID, stations.GetStatistics} {
			result := overviewRequest(t, actor, true, "/stations/9501", func(c *gin.Context) {
				c.Params = gin.Params{{Key: "id", Value: "9501"}}
				read(c)
			})
			require.Equal(t, want, result["code"], result)
		}
	}
	result := overviewRequest(t, actor, true, "/dashboard/statistics", dashboard.GetStatistics)
	require.Equal(t, float64(0), result["code"], result)
	require.Equal(t, float64(1), result["data"].(map[string]any)["deviceStats"].(map[string]any)["total"])
	result = overviewRequest(t, actor, true, "/stations/summary", stations.GetSummary)
	require.Equal(t, float64(0), result["code"], result)
	require.Equal(t, float64(1), result["data"].(map[string]any)["summary"].(map[string]any)["totalDevices"])
	checkReads(0)
	plan, admin, err := loadOverviewScope(ctx, pool, actor, true, "device")
	require.NoError(t, err)
	for _, change := range []struct{ disable, restore string }{
		{"UPDATE users SET is_system_admin=false WHERE id=9500", "UPDATE users SET is_system_admin=true WHERE id=9500"},
		{"UPDATE users SET status=0 WHERE id=9500", "UPDATE users SET status=1 WHERE id=9500"},
		{"UPDATE users SET deleted_at=NOW() WHERE id=9500", "UPDATE users SET deleted_at=NULL WHERE id=9500"},
	} {
		_, err = pool.Exec(ctx, change.disable)
		require.NoError(t, err)
		require.Equal(t, float64(403), overviewRequest(t, actor, true, "/dashboard/statistics", dashboard.GetStatistics)["code"])
		require.Equal(t, float64(403), overviewRequest(t, actor, true, "/stations/summary", stations.GetSummary)["code"])
		checkReads(403)
		stream, err := dashboard.collectDashboardSSEData(ctx, plan, admin)
		require.NoError(t, err)
		require.Zero(t, stream["deviceStats"].(map[string]any)["total"])
		_, err = pool.Exec(ctx, change.restore)
		require.NoError(t, err)
	}
	_, err = pool.Exec(ctx, `
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status) VALUES(9500,9500,NULL,'manufacturer','SYN-R','Root','active');
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status,version,expires_at)
			VALUES(9500,9500,9500,9500,'active',1,NOW()-INTERVAL '1 second');
	`)
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9500").Scan(&actor.MembershipVersion))
	require.Equal(t, float64(403), overviewRequest(t, actor, true, "/dashboard/statistics", dashboard.GetStatistics)["code"], "real expired membership must not fall back to synthetic admin")
	checkReads(403)
	_, err = pool.Exec(ctx, "UPDATE organization_memberships SET expires_at=NULL WHERE id=9500")
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9500").Scan(&actor.MembershipVersion))
	require.Equal(t, float64(0), overviewRequest(t, actor, true, "/dashboard/statistics", dashboard.GetStatistics)["code"])
	checkReads(0)
	_, err = pool.Exec(ctx, "UPDATE organization_memberships SET status='disabled' WHERE id=9500")
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9500").Scan(&actor.MembershipVersion))
	require.Equal(t, float64(403), overviewRequest(t, actor, true, "/dashboard/statistics", dashboard.GetStatistics)["code"])
	require.Equal(t, float64(403), overviewRequest(t, actor, true, "/stations/summary", stations.GetSummary)["code"])
	checkReads(403)
	stream, err := dashboard.collectDashboardSSEData(ctx, plan, admin)
	require.NoError(t, err)
	require.Zero(t, stream["deviceStats"].(map[string]any)["total"], "synthetic plan cannot bypass a subsequently disabled real membership")
	_, err = pool.Exec(ctx, "UPDATE organization_memberships SET status='active' WHERE id=9500")
	require.NoError(t, err)
	require.NoError(t, pool.QueryRow(ctx, "SELECT version FROM organization_memberships WHERE id=9500").Scan(&actor.MembershipVersion))
	_, err = pool.Exec(ctx, "UPDATE organizations SET status='disabled' WHERE id=9500")
	require.NoError(t, err)
	require.Equal(t, float64(403), overviewRequest(t, actor, true, "/stations/summary", stations.GetSummary)["code"])
}
