//go:build integration

package repository

import (
	"context"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestBindingRevisionActualMigration(t *testing.T) {
	dsn := os.Getenv("BINDING_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("dedicated BINDING_TEST_DATABASE_URL is not configured")
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer admin.Close(ctx)
	schema := fmt.Sprintf("binding_test_%d", time.Now().UnixNano())
	ident := pgx.Identifier{schema}.Sanitize()
	if _, err = admin.Exec(ctx, "CREATE SCHEMA "+ident); err != nil {
		t.Fatal(err)
	}
	defer admin.Exec(ctx, "DROP SCHEMA "+ident+" CASCADE")
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = schema
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	_, err = pool.Exec(ctx, `CREATE TABLE devices(sn VARCHAR(64) PRIMARY KEY,user_id BIGINT NOT NULL DEFAULT 0,deleted_at TIMESTAMPTZ,updated_at TIMESTAMPTZ);
 INSERT INTO devices(sn) VALUES('H1ZZX0013900001P')`)
	if err != nil {
		t.Fatal(err)
	}
	_, file, _, _ := runtime.Caller(0)
	sql, err := os.ReadFile(filepath.Join(filepath.Dir(file), "../../..", "database/migrations/130_device_binding_revision.up.sql"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err = pool.Exec(ctx, string(sql)); err != nil {
		t.Fatal(err)
	}
	repo := NewDeviceRepository(pool)
	check := func(state, revision string) {
		t.Helper()
		s, r, e := repo.BindingSnapshot(ctx, "H1ZZX0013900001P")
		if e != nil || s != state || r != revision {
			t.Fatalf("got %s %s %v want %s %s", s, r, e, state, revision)
		}
	}
	exec := func(sql string) {
		t.Helper()
		if _, e := pool.Exec(ctx, sql); e != nil {
			t.Fatal(e)
		}
	}
	check("UNBOUND", "1")
	exec(`UPDATE devices SET user_id=100`)
	check("BOUND", "2")
	exec(`UPDATE devices SET user_id=100,updated_at=NOW()`)
	check("BOUND", "2")
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = tx.Exec(ctx, `UPDATE devices SET user_id=0`); err != nil {
		t.Fatal(err)
	}
	tx.Rollback(ctx)
	check("BOUND", "2")
	exec(`UPDATE devices SET user_id=200`)
	check("BOUND", "3") // station/transfer raw updates covered
	exec(`UPDATE devices SET deleted_at=NOW()`)
	check("UNKNOWN", "4")
	exec(`DELETE FROM devices`)
	check("UNKNOWN", "5")
	exec(`INSERT INTO devices(sn) VALUES('H1ZZX0013900001P')`)
	check("UNBOUND", "6")
	s, rev, err := repo.BindingSnapshot(ctx, "H1ZZX00139000000")
	if err != nil || s != "UNKNOWN" || rev != "0" {
		t.Fatal("missing SN not UNKNOWN0")
	}
}
