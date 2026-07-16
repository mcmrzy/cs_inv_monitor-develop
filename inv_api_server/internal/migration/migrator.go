// Package migration provides automatic database schema migration functionality.
//
// It reads SQL files from a migrations directory, tracks applied migrations
// in a schema_migrations table, and executes pending migrations in order
// before the API server starts accepting requests.
//
// Design:
//   - Baseline: schema.sql runs as "version 0" on fresh databases
//   - Numbered files (001_*.sql, 002_*.sql, ...) run in ascending order
//   - Each migration is tracked by version number extracted from filename
//   - .down.sql files are excluded (rollback scripts, not for auto-migration)
//   - Failed migrations stop startup and are never recorded as applied
package migration

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"inv-api-server/pkg/logger"
)

// Run executes all pending database migrations.
//
// Parameters:
//   - db: active connection pool to the target database
//   - dir: filesystem path to the directory containing numbered migration .sql files
//   - schemaFile: path to the baseline schema.sql (empty string to skip baseline)
//
// The function is safe to call on every startup — already-applied migrations
// are detected via the schema_migrations table and skipped.
func Run(ctx context.Context, db *pgxpool.Pool, dir, schemaFile string) error {
	// 1. Ensure the tracking table exists (idempotent).
	if _, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version    BIGINT PRIMARY KEY,
		name       VARCHAR(255) NOT NULL,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`); err != nil {
		return fmt.Errorf("create schema_migrations table: %w", err)
	}

	appliedCount := 0
	skippedCount := 0

	// 2. Run the baseline schema.sql as version 0 (only once, on first run).
	if schemaFile != "" {
		baselineApplied, err := isApplied(ctx, db, 0)
		if err != nil {
			return err
		}
		if baselineApplied {
			skippedCount++
		} else if _, err := os.Stat(schemaFile); err == nil {
			logger.Info("[Migration] Running baseline schema.sql ...")
			if err := execSQLFile(ctx, db, schemaFile); err != nil {
				logger.Warn("[Migration] Baseline schema.sql had errors (expected if DB already has schema)",
					zap.Error(err))
			}
			if err := record(ctx, db, 0, "baseline_schema"); err != nil {
				return fmt.Errorf("record baseline migration: %w", err)
			}
			appliedCount++
			logger.Info("[Migration] Baseline schema.sql applied")
		} else {
			logger.Warn("[Migration] schema.sql not found, skipping baseline",
				zap.String("path", schemaFile))
		}
	}

	// 3. Collect numbered migration files (exclude *.down.sql).
	files, err := listMigrations(dir)
	if err != nil {
		return fmt.Errorf("list migration files: %w", err)
	}

	if len(files) == 0 {
		logger.Info("[Migration] No migration files found", zap.String("dir", dir))
	}

	// 4. Execute each pending migration in version order.
	for _, file := range files {
		name := filepath.Base(file)
		version, ok := extractVersion(name)
		if !ok {
			logger.Warn("[Migration] Skipping file with unparseable version", zap.String("file", name))
			continue
		}

		already, err := isApplied(ctx, db, version)
		if err != nil {
			return fmt.Errorf("check migration %d: %w", version, err)
		}
		if already {
			skippedCount++
			continue
		}

		logger.Info("[Migration] Running migration",
			zap.Int64("version", version),
			zap.String("file", name))

		if err := execSQLFile(ctx, db, file); err != nil {
			return fmt.Errorf("execute migration %d (%s): %w", version, name, err)
		}

		if err := record(ctx, db, version, name); err != nil {
			return fmt.Errorf("record migration %d: %w", version, err)
		}
		appliedCount++
		logger.Info("[Migration] Migration applied",
			zap.Int64("version", version),
			zap.String("file", name))
	}

	logger.Info("[Migration] Complete",
		zap.Int("applied", appliedCount),
		zap.Int("skipped", skippedCount),
		zap.Int("total", appliedCount+skippedCount))

	return nil
}

// isApplied checks whether migration version has been recorded.
func isApplied(ctx context.Context, db *pgxpool.Pool, version int64) (bool, error) {
	var exists bool
	err := db.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)", version,
	).Scan(&exists)
	return exists, err
}

// record inserts a migration record. Uses ON CONFLICT for safety.
func record(ctx context.Context, db *pgxpool.Pool, version int64, name string) error {
	_, err := db.Exec(ctx,
		"INSERT INTO schema_migrations (version, name) VALUES ($1, $2) ON CONFLICT DO NOTHING",
		version, name)
	return err
}

// execSQLFile reads a .sql file and executes its full contents in a single call.
// PostgreSQL's simple-protocol multi-statement execution handles files with
// multiple semicolon-separated statements, including BEGIN/COMMIT blocks.
func execSQLFile(ctx context.Context, db *pgxpool.Pool, path string) error {
	sql, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}
	if _, err := db.Exec(ctx, string(sql)); err != nil {
		return fmt.Errorf("execute %s: %w", filepath.Base(path), err)
	}
	return nil
}

// listMigrations returns sorted .sql file paths from dir, excluding *.down.sql.
func listMigrations(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // directory doesn't exist — no migrations
		}
		return nil, err
	}
	var files []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.HasSuffix(name, ".sql") {
			continue
		}
		if strings.HasSuffix(name, ".down.sql") {
			continue
		}
		files = append(files, filepath.Join(dir, name))
	}
	sort.Strings(files)
	return files, nil
}

// extractVersion parses the leading numeric prefix of a filename.
// e.g. "001_init_schema.up.sql" → (1, true)
//      "006_refactor_ota.sql"   → (6, true)
//      "schema.sql"             → (0, false)  — handled separately
func extractVersion(filename string) (int64, bool) {
	i := 0
	for i < len(filename) && filename[i] >= '0' && filename[i] <= '9' {
		i++
	}
	if i == 0 {
		return 0, false
	}
	n, err := strconv.ParseInt(filename[:i], 10, 64)
	if err != nil {
		return 0, false
	}
	return n, true
}
