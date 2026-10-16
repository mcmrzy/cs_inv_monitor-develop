//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"
)

func TestInternalOTAAttemptCallbacks(t *testing.T) {
	ctx := context.Background()
	pool := newOTAAttemptTestPool(t)
	h := &InternalHandler{db: pool}
	for _, endpoint := range []string{"status", "ack"} {
		t.Run(endpoint, func(t *testing.T) {
			for _, tc := range []struct {
				name, taskID, sn, initial string
				retry, wantCode           int
				wantChanged               bool
			}{
				{"active retry", "1-r1", "SN", "pending", 1, 0, true},
				{"original numeric", "1", "SN", "pending", 0, 0, true},
				{"stale numeric attempt", "1", "SN", "pending", 1, 0, false},
				{"stale retry attempt", "1-r1", "SN", "pending", 2, 0, false},
				{"future retry attempt", "1-r2", "SN", "pending", 1, 0, false},
				{"unknown explicit row", "999", "SN", "pending", 0, 0, false},
				{"wrong device explicit row", "2", "SN", "pending", 0, 0, false},
				{"wrong payload device", "1-r1", "OTHER", "pending", 1, 0, false},
				{"terminal success", "1-r1", "SN", "success", 1, 0, false},
				{"terminal failed", "1-r1", "SN", "failed", 1, 0, false},
				{"terminal cancelled", "1-r1", "SN", "cancelled", 1, 0, false},
				{"malformed ID", "bad", "SN", "pending", 0, 400, false},
				{"noncanonical retry", "1-r0", "SN", "pending", 1, 400, false},
				{"empty legacy first attempt", "", "SN", "pending", 0, 0, true},
				{"empty legacy cannot update retry", "", "SN", "pending", 1, 0, false},
			} {
				t.Run(tc.name, func(t *testing.T) {
					_, err := pool.Exec(ctx, `TRUNCATE device_upgrades;
						INSERT INTO device_upgrades (id,device_sn,firmware_id,status,retry_count,progress,updated_at)
						VALUES (2,'OTHER',42,'pending',0,0,NOW()), (3,'SN',43,'pending',1,0,NOW())`)
					require.NoError(t, err)
					_, err = pool.Exec(ctx, `INSERT INTO device_upgrades (id,device_sn,firmware_id,status,retry_count,progress)
						VALUES (1,'SN',42,$1,$2,0)`, tc.initial, tc.retry)
					require.NoError(t, err)
					payload := map[string]any{"device_sn": tc.sn, "task_id": tc.taskID, "firmware_id": 42,
						"status": "cancelled", "progress": 71, "stage_progress": 20, "overall_progress": 71, "ack": true}
					callback := h.OTAStatus
					if endpoint == "ack" {
						callback = h.OTACmdAck
					}
					postOTAAttempt(t, callback, payload, tc.wantCode)
					var status string
					var progress int
					require.NoError(t, pool.QueryRow(ctx, `SELECT status,progress FROM device_upgrades WHERE id=1`).Scan(&status, &progress))
					wantStatus := tc.initial
					if tc.wantChanged {
						wantStatus = "cancelled"
						if endpoint == "ack" {
							wantStatus = "upgrading"
						}
					}
					require.Equal(t, wantStatus, status)
					if tc.wantChanged && endpoint == "status" {
						require.Equal(t, 71, progress)
						var phase, overall int
						require.NoError(t, pool.QueryRow(ctx, `SELECT stage_progress,overall_progress FROM device_upgrades WHERE id=1`).Scan(&phase, &overall))
						require.Equal(t, 20, phase)
						require.Equal(t, 71, overall)
					} else {
						require.Zero(t, progress)
					}
					var unchanged int
					require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_upgrades WHERE id IN (2,3) AND status='pending' AND progress=0`).Scan(&unchanged))
					require.Equal(t, 2, unchanged, "explicit task IDs must never fall back to another active row")
					if tc.wantChanged && endpoint == "ack" {
						// Repeated ACK after completion must not promote the next pending chip.
						_, err = pool.Exec(ctx, `UPDATE device_upgrades SET status='success' WHERE id=1`)
						require.NoError(t, err)
						postOTAAttempt(t, callback, payload, 0)
						require.NoError(t, pool.QueryRow(ctx, `SELECT COUNT(*) FROM device_upgrades WHERE id IN (2,3) AND status='pending'`).Scan(&unchanged))
						require.Equal(t, 2, unchanged)
					}
				})
			}
		})
	}
	t.Run("negative ACK does not mutate even with malformed token", func(t *testing.T) {
		var before, after string
		require.NoError(t, pool.QueryRow(ctx, `SELECT json_agg(d ORDER BY id)::text FROM device_upgrades d`).Scan(&before))
		postOTAAttempt(t, h.OTACmdAck, map[string]any{"device_sn": "SN", "task_id": "bad", "ack": false}, 0)
		require.NoError(t, pool.QueryRow(ctx, `SELECT json_agg(d ORDER BY id)::text FROM device_upgrades d`).Scan(&after))
		require.Equal(t, before, after)
	})
}

func postOTAAttempt(t *testing.T, endpoint gin.HandlerFunc, payload map[string]any, wantCode int) {
	t.Helper()
	body, err := json.Marshal(payload)
	require.NoError(t, err)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest("POST", "/internal/ota", strings.NewReader(string(body)))
	c.Request.Header.Set("Content-Type", "application/json")
	endpoint(c)
	var result map[string]any
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &result))
	require.EqualValues(t, wantCode, result["code"], w.Body.String())
}

func TestInternalOTASuccessFollowOnUsesReportedAttempt(t *testing.T) {
	for _, taskID := range []string{"1-r1", ""} {
		t.Run("token="+taskID, func(t *testing.T) {
			ctx := context.Background()
			pool := newOTAAttemptTestPool(t)
			h := &InternalHandler{db: pool}
			retryCount := 1
			if taskID == "" {
				retryCount = 0
			}
			_, err := pool.Exec(ctx, `
				CREATE TABLE devices (sn text PRIMARY KEY, firmware_arm text, firmware_dsp text, updated_at timestamptz);
				INSERT INTO devices VALUES ('SN','arm-old','dsp-old',NOW());
				CREATE TABLE upgrade_tasks (id bigint PRIMARY KEY, status text, total_devices integer,
					success_count integer DEFAULT 0, failed_count integer DEFAULT 0,
					executed_at timestamptz, completed_at timestamptz, updated_at timestamptz);
				INSERT INTO upgrade_tasks (id,status,total_devices) VALUES (101,'pending',1),(202,'pending',1);
				INSERT INTO device_upgrades (id,device_sn,firmware_id,task_id,status,retry_count,progress,target_chip,firmware_version,updated_at)
				VALUES (2,'SN',43,202,'success',1,100,'arm','arm-other',NOW()+INTERVAL '1 hour')`)
			require.NoError(t, err)
			_, err = pool.Exec(ctx, `INSERT INTO device_upgrades
				(id,device_sn,firmware_id,task_id,status,retry_count,progress,target_chip,firmware_version)
				VALUES (1,'SN',42,101,'upgrading',$1,99,'dsp','1.1.50')`, retryCount)
			require.NoError(t, err)
			postOTAAttempt(t, h.OTAStatus, map[string]any{
				"device_sn": "SN", "task_id": taskID, "status": "success", "progress": 100,
			}, 0)
			var arm, dsp string
			require.NoError(t, pool.QueryRow(ctx, `SELECT firmware_arm,firmware_dsp FROM devices WHERE sn='SN'`).Scan(&arm, &dsp))
			require.Equal(t, "arm-old", arm, "the newer success row belongs to another target")
			require.Equal(t, "1.1.50", dsp)
			require.Eventually(t, func() bool {
				var status string
				var success int
				err := pool.QueryRow(ctx, `SELECT status,success_count FROM upgrade_tasks WHERE id=101`).Scan(&status, &success)
				return err == nil && status == "completed" && success == 1
			}, 2*time.Second, 10*time.Millisecond, "statistics must follow the reported upgrade's parent task")
			var otherStatus string
			var otherSuccess int
			require.NoError(t, pool.QueryRow(ctx, `SELECT status,success_count FROM upgrade_tasks WHERE id=202`).Scan(&otherStatus, &otherSuccess))
			require.Equal(t, "pending", otherStatus)
			require.Zero(t, otherSuccess)
		})
	}
}

func newOTAAttemptTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
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
	t.Cleanup(admin.Close)
	name := fmt.Sprintf("ota_attempt_%d", time.Now().UnixNano())
	_, err = admin.Exec(ctx, "CREATE DATABASE "+name)
	require.NoError(t, err)
	t.Cleanup(func() { _, err := admin.Exec(ctx, "DROP DATABASE "+name+" WITH (FORCE)"); require.NoError(t, err) })
	pool, err := pgxpool.New(ctx, dsn+name+"?sslmode=disable")
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	_, err = pool.Exec(ctx, `CREATE TABLE device_upgrades (
		id bigint PRIMARY KEY, device_sn text, firmware_id bigint, task_id bigint,
		status varchar, stage varchar, progress integer, error_message text,
		target_chip text, firmware_version text,
		retry_count integer NOT NULL DEFAULT 0, stage_progress integer, overall_progress integer,
		started_at timestamptz, completed_at timestamptz, updated_at timestamptz DEFAULT NOW())`)
	require.NoError(t, err)
	return pool
}
