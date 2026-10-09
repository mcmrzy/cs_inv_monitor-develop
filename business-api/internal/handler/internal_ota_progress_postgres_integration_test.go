//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestInternalOTAStageProgressPersistence(t *testing.T) {
	ctx := context.Background()
	env := func(key, fallback string) string {
		if value := os.Getenv(key); value != "" {
			return value
		}
		return fallback
	}
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/", env("TEST_DB_USER", "testuser"), env("TEST_DB_PASSWORD", "testpass"), env("TEST_DB_HOST", "localhost"), env("TEST_DB_PORT", "15432"))
	admin, err := pgxpool.New(ctx, dsn+"postgres?sslmode=disable")
	require.NoError(t, err)
	defer admin.Close()
	name := fmt.Sprintf("ota_progress_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+name)
	require.NoError(t, err)
	defer func() { _, err := admin.Exec(ctx, "DROP DATABASE "+name+" WITH (FORCE)"); require.NoError(t, err) }()
	pool, err := pgxpool.New(ctx, dsn+name+"?sslmode=disable")
	require.NoError(t, err)
	defer pool.Close()
	_, err = pool.Exec(ctx, `CREATE TABLE device_upgrades (
		id bigint PRIMARY KEY, device_sn text, firmware_id bigint, task_id bigint,
		status varchar, stage varchar, progress integer, error_message text,
		started_at timestamptz, completed_at timestamptz, updated_at timestamptz DEFAULT NOW()
	)`)
	require.NoError(t, err)
	migration, err := os.ReadFile(filepath.Join("..", "..", "..", "database", "migrations", "127_ota_stage_progress.up.sql"))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(migration))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO device_upgrades (id,device_sn,firmware_id,status,progress) VALUES (1,'SN',42,'pending',0), (2,'OTHER',42,'pending',0)`)
	require.NoError(t, err)
	h := NewInternalHandler(pool, nil, nil, nil, nil, nil, nil, nil)
	post := func(body string, want int) {
		w := httptest.NewRecorder()
		c, _ := gin.CreateTestContext(w)
		c.Request = httptest.NewRequest("POST", "/internal/ota-status", strings.NewReader(body))
		c.Request.Header.Set("Content-Type", "application/json")
		h.OTAStatus(c)
		var result map[string]any
		require.NoError(t, json.Unmarshal(w.Body.Bytes(), &result))
		require.EqualValues(t, want, result["code"], w.Body.String())
	}
	post(`{"device_sn":"SN","task_id":"1","status":"installing","progress":70,"stage":"transferring","stage_progress":0,"overall_progress":70}`, 0)
	var status, stage string
	var phase, overall *int
	read := func() {
		require.NoError(t, pool.QueryRow(ctx, `SELECT status,stage,stage_progress,overall_progress FROM device_upgrades WHERE id=1`).Scan(&status, &stage, &phase, &overall))
	}
	read()
	require.Equal(t, "upgrading", status)
	require.Equal(t, "transferring", stage)
	require.Equal(t, 0, *phase)
	require.Equal(t, 70, *overall)
	post(`{"device_sn":"SN","task_id":"1","status":"verifying","progress":99,"stage_progress":100,"overall_progress":99}`, 0)
	read()
	require.Equal(t, "upgrading", status)
	require.Equal(t, 100, *phase)
	post(`{"device_sn":"SN","task_id":"1","status":"installing","progress":84}`, 0)
	read()
	require.Nil(t, phase)
	require.Nil(t, overall)
	post(`{"device_sn":"SN","status":"installing","stage_progress":101}`, 400)
	post(`{"device_sn":"SN","task_id":"1","status":"succeeded","progress":100,"stage_progress":100,"overall_progress":100}`, 0)
	read()
	require.Equal(t, "success", status)
	var otherStatus string
	require.NoError(t, pool.QueryRow(ctx, `SELECT status FROM device_upgrades WHERE id=2`).Scan(&otherStatus))
	require.Equal(t, "pending", otherStatus)
}
