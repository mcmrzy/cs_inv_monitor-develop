//go:build integration

package handler

import (
	"context"
	"fmt"
	"net/http/httptest"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestDeviceAssignmentOrganizationScope(t *testing.T) {
	pool := assignmentTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,nickname,status,is_system_admin) VALUES
		(99400,'assignment-admin','hash','Admin',1,true),
		(99401,'assignment-agent','hash','Agent',1,false),
		(99402,'assignment-customer','hash','Customer',1,false),
		(99403,'assignment-sibling','hash','Sibling',1,false);
		INSERT INTO organizations(id,root_tenant_id,parent_id,org_type,code,name,status) VALUES
		(99400,99400,NULL,'manufacturer','ASSIGN-R','Root','active'),
		(99401,99400,99400,'agent','ASSIGN-A','Agent','active'),
		(99410,99400,99401,'distributor','ASSIGN-D','Distributor','active'),
		(99411,99400,99410,'installer','ASSIGN-I','Installer','active'),
		(99402,99400,99411,'customer','ASSIGN-C','Customer','active'),
		(99403,99400,99400,'agent','ASSIGN-S','Sibling','active');
		INSERT INTO organization_memberships(id,root_tenant_id,organization_id,user_id,status,version) VALUES
		(99401,99400,99401,99401,'active',1),(99402,99400,99402,99402,'active',1),(99403,99400,99403,99403,'active',1);
		INSERT INTO membership_role_assignments(id,root_tenant_id,organization_id,membership_id,role_code,status) VALUES
		(99401,99400,99401,99401,'agent','active'),(99402,99400,99402,99402,'customer','active');
		INSERT INTO role_permission_grants(root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope)
		SELECT 99400,99401,99401,p,'organization_and_descendants' FROM unnest(ARRAY['devices:view','devices:edit','stations:view','stations:edit']) p;
		INSERT INTO role_permission_grants(root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope)
		SELECT 99400,99402,99402,p,'self' FROM unnest(ARRAY['devices:view','devices:edit','stations:view','stations:edit']) p;
		INSERT INTO stations(id,user_id,name,province,city,address,capacity,timezone) VALUES
		(99402,99402,'Customer station','','','',0,'UTC'),(99404,99402,'Second customer station','','','',0,'Asia/Shanghai'),(99403,99403,'Sibling station','','','',0,'Asia/Shanghai');
		INSERT INTO devices(sn,model,user_id) VALUES
		('ASSIGN-AGENT','L10',99401),('ASSIGN-CHILD','L10',99402),
		('ASSIGN-SIBLING','L10',99403),('ASSIGN-UNBOUND','L10',0);`)
	require.NoError(t, err)
	cache := redis.NewClient(&redis.Options{Addr: miniredis.RunT(t).Addr()})
	t.Cleanup(func() { cache.Close() })
	h := NewDeviceHandler(service.NewDeviceService(repository.NewDeviceRepository(pool, cache), cache, repository.NewModelRepository(pool, cache), nil, "", "", pool),
		nil, service.NewStationService(repository.NewStationRepository(pool)), nil, nil,
		service.NewUserService(repository.NewUserRepository(pool, nil), nil), pool)
	actor := func(id int64) model.ActorContext {
		a := model.ActorContext{UserID: id, RootTenantID: 99400, OrganizationID: id, MembershipID: id, MembershipVersion: 1}
		if id == 99400 {
			a.RootTenantID = id
		}
		if id != 99400 {
			require.NoError(t, pool.QueryRow(ctx, `SELECT version FROM organization_memberships WHERE id=$1`, id).Scan(&a.MembershipVersion))
		}
		return a
	}
	for _, tc := range []struct {
		id   int64
		want []string
	}{
		{99400, []string{"ASSIGN-AGENT", "ASSIGN-CHILD", "ASSIGN-SIBLING", "ASSIGN-UNBOUND"}},
		{99401, []string{"ASSIGN-AGENT", "ASSIGN-CHILD"}},
		{99402, []string{"ASSIGN-CHILD"}},
	} {
		t.Run(fmt.Sprintf("list_%d", tc.id), func(t *testing.T) {
			result := overviewRequest(t, actor(tc.id), tc.id == 99400, "/devices", h.List)
			require.EqualValues(t, 0, result["code"])
			page := result["data"].(map[string]any)
			require.EqualValues(t, len(tc.want), page["total"])
			var sns []string
			for _, item := range page["items"].([]any) {
				d := item.(map[string]any)
				sns = append(sns, d["sn"].(string))
				if d["sn"] == "ASSIGN-CHILD" {
					require.NotNil(t, d["owner"])
					require.Equal(t, "Customer", d["owner"].(map[string]any)["nickname"])
				}
				if d["sn"] == "ASSIGN-UNBOUND" {
					require.Nil(t, d["owner"])
				}
			}
			sort.Strings(sns)
			require.Equal(t, tc.want, sns)
		})
	}
	t.Run("descendant_detail_is_visible", func(t *testing.T) {
		result := overviewRequest(t, actor(99401), false, "/devices/by-sn/ASSIGN-CHILD", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "sn", Value: "ASSIGN-CHILD"}}
			h.GetDetail(c)
		})
		require.EqualValues(t, 0, result["code"])
	})
	t.Run("sibling_detail_is_denied", func(t *testing.T) {
		result := overviewRequest(t, actor(99401), false, "/devices/by-sn/ASSIGN-SIBLING", func(c *gin.Context) {
			c.Params = gin.Params{{Key: "sn", Value: "ASSIGN-SIBLING"}}
			h.GetDetail(c)
		})
		require.EqualValues(t, 403, result["code"])
	})
	t.Run("search_pagination_share_scope", func(t *testing.T) {
		result := overviewRequest(t, actor(99401), false, "/devices?keyword=CHILD&page_size=1", h.List)
		require.EqualValues(t, 0, result["code"])
		page := result["data"].(map[string]any)
		require.EqualValues(t, 1, page["total"])
		require.Len(t, page["items"], 1)
	})
	request := func(id int64, sn string, station int64, guarded bool) int {
		r := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(r)
		c.Request = httptest.NewRequest("POST", "/devices/add-to-station", strings.NewReader(fmt.Sprintf(`{"sn":%q,"station_id":%d,"only_unassigned":%t}`, sn, station, guarded)))
		c.Request.Header.Set("Content-Type", "application/json")
		c.Set("user_id", id)
		c.Set("actor_context", actor(id))
		c.Set("is_system_admin", id == 99400)
		h.AddToStation(c)
		return r.Code
	}
	t.Run("administrator_assigns_foreign_device", func(t *testing.T) {
		require.Equal(t, 200, request(99400, "ASSIGN-SIBLING", 99402, true))
	})
	t.Run("agent_assigns_descendant_without_changing_owner", func(t *testing.T) {
		require.Equal(t, 200, request(99401, "ASSIGN-CHILD", 99402, true))
		var owner int64
		var tz string
		require.NoError(t, pool.QueryRow(ctx, `SELECT user_id,timezone FROM devices WHERE sn='ASSIGN-CHILD'`).Scan(&owner, &tz))
		require.EqualValues(t, 99402, owner)
		require.Equal(t, "UTC", tz)
		require.Equal(t, 409, request(99401, "ASSIGN-CHILD", 99402, true))
	})
	t.Run("sibling_station_and_device_denied", func(t *testing.T) {
		require.Equal(t, 403, request(99401, "ASSIGN-AGENT", 99403, true))
		require.Equal(t, 403, request(99401, "ASSIGN-SIBLING", 99402, false))
	})
	editPlans := func() (model.ScopePlan, model.ScopePlan) {
		a := actor(99401)
		dp, _, err := loadResourceScope(ctx, pool, a, false, "devices:edit", "device")
		require.NoError(t, err)
		sp, _, err := loadResourceScope(ctx, pool, a, false, "stations:edit", "station")
		require.NoError(t, err)
		return dp, sp
	}
	repo := repository.NewDeviceRepository(pool, cache)
	t.Run("cached_scope_rechecks_registered_owner", func(t *testing.T) {
		dp, sp := editPlans()
		_, err := pool.Exec(ctx, `INSERT INTO authorization_resources(root_tenant_id,organization_id,resource_type,resource_id,status) VALUES(99400,99403,'device','ASSIGN-AGENT','active')`)
		require.NoError(t, err)
		assigned, err := repo.AssignToStationScoped(ctx, "ASSIGN-AGENT", 99402, dp, sp, false, true)
		require.ErrorIs(t, err, repository.ErrAssignmentOutOfScope)
		require.False(t, assigned)
		_, err = pool.Exec(ctx, `DELETE FROM authorization_resources WHERE resource_type='device' AND resource_id='ASSIGN-AGENT'`)
		require.NoError(t, err)
	})
	t.Run("cached_scope_rechecks_revoked_edit_grant", func(t *testing.T) {
		dp, sp := editPlans()
		_, err := pool.Exec(ctx, `DELETE FROM role_permission_grants WHERE role_assignment_id=99401 AND permission_code='stations:edit'`)
		require.NoError(t, err)
		assigned, err := repo.AssignToStationScoped(ctx, "ASSIGN-AGENT", 99402, dp, sp, false, true)
		require.ErrorIs(t, err, repository.ErrAssignmentOutOfScope)
		require.False(t, assigned)
		_, err = pool.Exec(ctx, `INSERT INTO role_permission_grants(root_tenant_id,organization_id,role_assignment_id,permission_code,data_scope) VALUES(99400,99401,99401,'stations:edit','organization_and_descendants')`)
		require.NoError(t, err)
	})
	t.Run("concurrent_addition_has_one_winner", func(t *testing.T) {
		dp, sp := editPlans()
		type outcome struct {
			assigned bool
			err      error
		}
		results := make(chan outcome, 2)
		start := make(chan struct{})
		var wg sync.WaitGroup
		for _, station := range []int64{99402, 99404} {
			wg.Add(1)
			go func(station int64) {
				defer wg.Done()
				<-start
				assigned, err := repo.AssignToStationScoped(ctx, "ASSIGN-AGENT", station, dp, sp, false, true)
				results <- outcome{assigned, err}
			}(station)
		}
		close(start)
		wg.Wait()
		close(results)
		winners := 0
		for result := range results {
			require.NoError(t, result.err)
			if result.assigned {
				winners++
			}
		}
		require.Equal(t, 1, winners)
		var owner int64
		require.NoError(t, pool.QueryRow(ctx, `SELECT user_id FROM devices WHERE sn='ASSIGN-AGENT'`).Scan(&owner))
		require.EqualValues(t, 99401, owner)
	})
	t.Run("read_grant_does_not_authorize_assignment", func(t *testing.T) {
		_, err := pool.Exec(ctx, `DELETE FROM role_permission_grants WHERE role_assignment_id=99401 AND permission_code='devices:edit'`)
		require.NoError(t, err)
		require.Equal(t, 403, request(99401, "ASSIGN-AGENT", 99402, true))
	})
	// Wait for successful requests' asynchronous audit before fixture cleanup.
	require.Eventually(t, func() bool {
		var count int
		err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM audit_logs WHERE action='bind' AND detail->>'sn' IN ('ASSIGN-CHILD','ASSIGN-SIBLING')`).Scan(&count)
		return err == nil && count == 2
	}, time.Second, 10*time.Millisecond)
}
