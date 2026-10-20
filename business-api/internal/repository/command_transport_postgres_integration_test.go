//go:build integration

package repository

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestCommandTransportCannotRegressDeviceResult(t *testing.T) {
	ctx := context.Background()
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://testuser:testpass@localhost:15432/postgres?sslmode=disable"
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.MaxConns = 1 // temporary tables and production transactions share one local connection.
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	_, err = pool.Exec(ctx, `CREATE TEMP TABLE device_cmd_logs(task_id varchar(50) PRIMARY KEY,status varchar(20),result text);
	CREATE TEMP TABLE device_commands(task_id uuid PRIMARY KEY,status varchar(20),result_message text,queued_at timestamptz,sent_at timestamptz,completed_at timestamptz);`)
	if err != nil {
		t.Fatal(err)
	}
	task := "00112233-4455-6677-8899-aabbccddeeff"
	if _, err = pool.Exec(ctx, `INSERT INTO device_cmd_logs VALUES($1,'submitted','OK')`, task); err != nil {
		t.Fatal(err)
	}
	if _, err = pool.Exec(ctx, `INSERT INTO device_commands(task_id,status,result_message)VALUES($1::uuid,'submitted','submitted')`, task); err != nil {
		t.Fatal(err)
	}
	repo := NewDeviceRepository(pool, nil)
	for _, status := range []string{"sent", "queued", "failed"} {
		if err = repo.UpdateCommandLogStatus(ctx, task, status, "late HTTP response"); err != nil {
			t.Fatal(err)
		}
	}
	var logStatus, commandStatus string
	if err = pool.QueryRow(ctx, `SELECT status FROM device_cmd_logs WHERE task_id=$1`, task).Scan(&logStatus); err != nil {
		t.Fatal(err)
	}
	if err = pool.QueryRow(ctx, `SELECT status FROM device_commands WHERE task_id=$1::uuid`, task).Scan(&commandStatus); err != nil {
		t.Fatal(err)
	}
	if logStatus != "submitted" || commandStatus != "submitted" {
		t.Fatalf("transport response regressed final device evidence: %s / %s", logStatus, commandStatus)
	}
}
