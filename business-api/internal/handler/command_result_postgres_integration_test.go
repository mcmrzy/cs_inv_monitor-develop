//go:build integration

package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

// Exercises the production atomic SQL against PostgreSQL temporary tables.
// It needs only a disposable local test connection; no production tables change.
func TestCommandResultPostgresStagesAndIdempotency(t *testing.T) {
	ctx := context.Background()
	env := func(key, fallback string) string {
		if v := os.Getenv(key); v != "" {
			return v
		}
		return fallback
	}
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = fmt.Sprintf("postgres://%s:%s@%s:%s/postgres?sslmode=disable", env("TEST_DB_USER", "testuser"), env("TEST_DB_PASSWORD", "testpass"), env("TEST_DB_HOST", "localhost"), env("TEST_DB_PORT", "15432"))
	}
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatalf("connect disposable test PostgreSQL: %v", err)
	}
	defer conn.Close(ctx)
	_, err = conn.Exec(ctx, `CREATE TEMP TABLE device_cmd_logs(task_id varchar(50) PRIMARY KEY,device_sn varchar(50),status varchar(20),result text,message text,data jsonb);
	CREATE TEMP TABLE device_commands(task_id uuid PRIMARY KEY,device_sn varchar(50),status varchar(20),result_code varchar(64),result_message text,response_data jsonb,acknowledged_at timestamptz,completed_at timestamptz);`)
	if err != nil {
		t.Fatal(err)
	}
	task := "00112233-4455-6677-8899-aabbccddeeff"
	if _, err = conn.Exec(ctx, `INSERT INTO device_cmd_logs(task_id,device_sn,status)VALUES($1,'SN001','sent')`, task); err != nil {
		t.Fatal(err)
	}
	if _, err = conn.Exec(ctx, `INSERT INTO device_commands(task_id,device_sn,status)VALUES($1::uuid,'SN001','sent')`, task); err != nil {
		t.Fatal(err)
	}
	apply := func(sn, stage, result string) int64 {
		t.Helper()
		status, err := commandResultStatus(stage, result, false, nil)
		if err != nil {
			t.Fatal(err)
		}
		if status == "ignored" {
			return 0
		}
		rev := uint64(42)
		data := mergeCommandStageData(nil, stage, json.RawMessage(`[80]`), &rev)
		var count int64
		err = conn.QueryRow(ctx, updateCommandResultSQL, task, status, result, "", data, sn, commandResultPredecessors(status, stage), "0", status == "acknowledged", commandResultTerminal(status)).Scan(&count)
		if err != nil {
			t.Fatal(err)
		}
		return count
	}
	if n := apply("FORGED-SN", "acknowledged", "OK"); n != 0 {
		t.Fatal("wrong SN changed command")
	}
	for _, stage := range []string{"acknowledged", "executing", "submitted"} {
		if n := apply("SN001", stage, "OK"); n != 1 {
			t.Fatalf("stage %s updated %d rows", stage, n)
		}
		if stage == "acknowledged" {
			if n := apply("SN001", "failed", "IDEMPOTENCY_CONFLICT"); n != 0 {
				t.Fatal("conflict terminated original acknowledged command")
			}
		}
	}
	var status string
	var completed *time.Time
	var data map[string]interface{}
	if err = conn.QueryRow(ctx, `SELECT status,completed_at,response_data FROM device_commands WHERE task_id=$1::uuid`, task).Scan(&status, &completed, &data); err != nil {
		t.Fatal(err)
	}
	if status != "submitted" || completed == nil || data["desired_revision"] != float64(42) || data["reported_revision"] != nil || data["applied_args"] != nil {
		t.Fatalf("false or missing submission result: %s %v %#v", status, completed, data)
	}
	for _, stage := range []string{"acknowledged", "executing", "submitted", "failed"} {
		if n := apply("SN001", stage, "OK"); n != 0 {
			t.Fatalf("duplicate/regression stage %s replaced submitted", stage)
		}
	}
	if n := apply("SN001", "applied", "OK"); n != 1 {
		t.Fatal("confirmed application did not advance submitted")
	}
	if n := apply("SN001", "completed", "OK"); n != 0 {
		t.Fatal("duplicate final response changed result")
	}
	var logStatus string
	if err = conn.QueryRow(ctx, `SELECT status FROM device_cmd_logs WHERE task_id=$1`, task).Scan(&logStatus); err != nil {
		t.Fatal(err)
	}
	if logStatus != "success" {
		t.Fatalf("log did not advance: %s", logStatus)
	}
	// Historical commands may have only a log row and a non-UUID task ID.
	task = "legacy-log-only"
	if _, err = conn.Exec(ctx, `INSERT INTO device_cmd_logs(task_id,device_sn,status)VALUES($1,'SN001','sent')`, task); err != nil {
		t.Fatal(err)
	}
	for _, stage := range []string{"acknowledged", "submitted"} {
		if n := apply("SN001", stage, "OK"); n != 1 {
			t.Fatalf("log-only %s did not advance", stage)
		}
	}
	if err = conn.QueryRow(ctx, `SELECT status FROM device_cmd_logs WHERE task_id=$1`, task).Scan(&logStatus); err != nil {
		t.Fatal(err)
	}
	if logStatus != "submitted" {
		t.Fatalf("log-only task result: %s", logStatus)
	}
}
