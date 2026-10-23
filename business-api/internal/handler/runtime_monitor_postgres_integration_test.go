//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/internal/service"
	"inv-api-server/pkg/response"

	"github.com/alicebob/miniredis/v2"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

// A private database reproduces the production failure without TimescaleDB or
// touching any application database. The migration stamp deliberately lies.
func TestRuntimeMonitorPostgresMissingColumn(t *testing.T) {
	dsn := os.Getenv("RUNTIME_MONITOR_TEST_ADMIN_DSN")
	if dsn == "" {
		t.Skip("set RUNTIME_MONITOR_TEST_ADMIN_DSN to a disposable local PostgreSQL instance")
	}
	ctx := context.Background()
	cfg, err := pgxpool.ParseConfig(dsn)
	require.NoError(t, err)
	admin, err := pgxpool.NewWithConfig(ctx, cfg)
	require.NoError(t, err)
	defer admin.Close()
	name := fmt.Sprintf("runtime_monitor_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+name)
	require.NoError(t, err)
	defer func() { _, e := admin.Exec(ctx, "DROP DATABASE "+name); require.NoError(t, e) }()
	cfg.ConnConfig.Database = name
	db, err := pgxpool.NewWithConfig(ctx, cfg)
	require.NoError(t, err)
	defer db.Close()
	_, err = db.Exec(ctx, `CREATE TABLE schema_migrations(version bigint PRIMARY KEY);
	INSERT INTO schema_migrations VALUES(91);
	CREATE TABLE device_latest_state(pv_total_power real, ac_active_power real, battery_power real, battery_soc real, updated_at timestamptz);
	CREATE TABLE device_telemetry_3min(device_sn text);`)
	require.NoError(t, err)
	s := miniredis.RunT(t)
	shared := redis.NewClient(&redis.Options{Addr: s.Addr()})
	defer shared.Close()
	rdb := repository.NewRuntimeMonitorRedis(shared)
	defer rdb.Close()
	svc := service.NewRuntimeMonitorService(repository.NewRuntimeMonitorRepository(db, rdb))
	r := gin.New()
	r.Use(middleware.RuntimeMonitor(svc))
	r.GET("/stations/:id", func(c *gin.Context) {
		var value float32
		err := db.QueryRow(c.Request.Context(), "SELECT l.ac_input_power FROM device_latest_state l").Scan(&value)
		response.InternalError(c, "get station power failed", err)
	})
	r.GET("/admin/runtime-monitor", func(c *gin.Context) { c.Set("is_system_admin", true) }, RuntimeMonitorHandler(svc))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest("GET", "/stations/123", nil))
	require.Equal(t, 500, w.Code)
	trace := w.Header().Get("X-Request-ID")
	read := func() model.RuntimeMonitorSnapshot {
		w := httptest.NewRecorder()
		r.ServeHTTP(w, httptest.NewRequest("GET", "/admin/runtime-monitor", nil))
		require.Equal(t, 200, w.Code)
		var body struct {
			Data model.RuntimeMonitorSnapshot `json:"data"`
		}
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &body))
		return body.Data
	}
	snapshot := read()
	require.Equal(t, "degraded", snapshot.Schema.Status)
	require.Len(t, snapshot.Groups, 1)
	require.Equal(t, trace, snapshot.Groups[0].RequestID)
	require.Equal(t, "42703", snapshot.Groups[0].SQLState)
	require.Contains(t, snapshot.Groups[0].Summary, "l.ac_input_power")
	_, err = db.Exec(ctx, `ALTER TABLE device_latest_state ADD COLUMN ac_input_power real, ADD COLUMN ac_charge_power real;
	ALTER TABLE device_telemetry_3min ADD COLUMN ac_input_power real, ADD COLUMN ac_charge_power real;`)
	require.NoError(t, err)
	require.Equal(t, "ok", read().Schema.Status)
}
