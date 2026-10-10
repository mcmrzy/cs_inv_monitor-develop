//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestStationAssignmentGuardHTTP(t *testing.T) {
	pool := overviewTestDB(t)
	ctx := context.Background()
	_, err := pool.Exec(ctx, `
		INSERT INTO users(id,phone,password_hash,status) VALUES(99311,'assignment-http','hash',1);
		INSERT INTO stations(id,user_id,name,province,city,address,capacity) VALUES
		(99311,99311,'First','','','',0),(99312,99311,'Second','','','',0);
		INSERT INTO devices(sn,model,user_id,station_id) VALUES('ASSIGNMENT-HTTP','L10',99311,99311);`)
	require.NoError(t, err)
	h := NewDeviceHandler(
		service.NewDeviceService(repository.NewDeviceRepository(pool, nil), nil, nil, nil, "", "", pool),
		nil, service.NewStationService(repository.NewStationRepository(pool)), nil, nil,
		service.NewUserService(repository.NewUserRepository(pool, nil), nil), pool,
	)
	for _, guarded := range []bool{true, false} {
		body := `{"sn":"ASSIGNMENT-HTTP","station_id":99312}`
		if guarded {
			body = `{"sn":"ASSIGNMENT-HTTP","station_id":99312,"only_unassigned":true}`
		}
		recorder := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(recorder)
		c.Request = httptest.NewRequest("POST", "/devices/add-to-station", strings.NewReader(body))
		c.Request.Header.Set("Content-Type", "application/json")
		c.Set("user_id", int64(99311))
		c.Set("is_system_admin", false)
		h.AddToStation(c)
		var response map[string]any
		require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
		wantStatus, wantCode, wantStation := 200, 0, int64(99312)
		if guarded {
			wantStatus, wantCode, wantStation = 409, 409, 99311
		}
		require.Equal(t, wantStatus, recorder.Code, recorder.Body.String())
		require.EqualValues(t, wantCode, response["code"])
		var station int64
		require.NoError(t, pool.QueryRow(ctx, `SELECT station_id FROM devices WHERE sn='ASSIGNMENT-HTTP'`).Scan(&station))
		require.Equal(t, wantStation, station)
	}
	require.Eventually(t, func() bool {
		var count int
		err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM audit_logs WHERE detail->>'sn'='ASSIGNMENT-HTTP' AND action='bind'`).Scan(&count)
		return err == nil && count == 1
	}, time.Second, 10*time.Millisecond, "wait for the asynchronous audit before dropping the fixture database")
}
