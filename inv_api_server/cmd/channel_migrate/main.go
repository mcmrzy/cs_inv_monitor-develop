package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"inv-api-server/internal/config"
	"inv-api-server/internal/migration"
)

const (
	exitInternal       = 1
	exitOK             = 0
	exitUsage          = 2
	exitConfig         = 3
	exitPreflightBlock = 4
	exitDatabase       = 5
	exitBackfill       = 6
	exitShadowDiff     = 7
	exitReserved       = 8
)

type commandOptions struct {
	configPath  string
	mappingPath string
	runID       string
	batchSize   int
	apply       bool
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(run(ctx, os.Args[1:], os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "usage: channel_migrate <preflight|backfill-organizations|shadow-report|backfill-assets|validate-constraints> [flags]")
		return exitUsage
	}
	command := args[0]
	if command == "backfill-assets" || command == "validate-constraints" {
		fmt.Fprintf(stderr, "%s is reserved for Task 9; no asset or constraint mutation was performed\n", command)
		return exitReserved
	}
	if command != "preflight" && command != "backfill-organizations" && command != "shadow-report" {
		fmt.Fprintf(stderr, "unknown command %q\n", command)
		return exitUsage
	}

	options, err := parseOptions(command, args[1:], stderr)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return exitUsage
	}
	mappingConfig, mappingDigest, err := migration.LoadChannelMappingConfig(options.mappingPath)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return exitConfig
	}
	cfg, err := config.Load(options.configPath)
	if err != nil {
		fmt.Fprintf(stderr, "load API config: %v\n", err)
		return exitConfig
	}
	if err := validateDatabaseConfig(cfg.Database); err != nil {
		fmt.Fprintln(stderr, err)
		return exitConfig
	}
	db, err := connectDatabase(ctx, cfg.Database)
	if err != nil {
		fmt.Fprintf(stderr, "connect database: %v\n", err)
		return exitDatabase
	}
	defer db.Close()
	if err := migration.RequireChannelBackfillSchema(ctx, db); err != nil {
		fmt.Fprintln(stderr, err)
		return exitDatabase
	}
	if err := migration.RequireAppliedVersions(ctx, db, 64, 65, 66); err != nil {
		fmt.Fprintln(stderr, err)
		return exitDatabase
	}

	if command == "shadow-report" {
		runID, err := uuid.Parse(options.runID)
		if err != nil {
			fmt.Fprintln(stderr, "shadow-report requires a valid --run-id")
			return exitUsage
		}
		var storedDigest string
		if err := db.QueryRow(ctx, `SELECT mapping_digest FROM channel_migration_runs WHERE id=$1`, runID).Scan(&storedDigest); err != nil {
			fmt.Fprintf(stderr, "load migration run: %v\n", err)
			return exitDatabase
		}
		if storedDigest != mappingDigest {
			fmt.Fprintln(stderr, "mapping digest differs from the migration run; refusing an incomparable shadow report")
			return exitConfig
		}
		report, err := migration.LoadChannelShadowReport(ctx, db, runID)
		if err != nil {
			fmt.Fprintf(stderr, "load shadow report: %v\n", err)
			return exitDatabase
		}
		if err := writeJSON(stdout, map[string]any{"status": "ok", "mapping_digest": mappingDigest, "report": report}); err != nil {
			fmt.Fprintln(stderr, err)
			return exitInternal
		}
		if report.PendingItems > 0 || report.UnresolvedQuarantine > 0 || report.ShadowDiffs > 0 || report.PlannedOrganizations != report.SucceededOrganizations {
			return exitShadowDiff
		}
		return exitOK
	}

	users, ownership, err := migration.LoadLegacyChannelSnapshot(ctx, db)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return exitDatabase
	}
	report := migration.AnalyzeLegacyUsers(users, mappingConfig.Roles, ownership)
	if command == "preflight" {
		if err := writeJSON(stdout, map[string]any{
			"status": "preflight", "mapping_digest": mappingDigest,
			"planned_organizations": len(report.Operations),
			"quarantine":            report.Quarantine, "ownership_quarantine": report.OwnershipQuarantine,
		}); err != nil {
			fmt.Fprintln(stderr, err)
			return exitInternal
		}
		if len(report.Quarantine)+len(report.OwnershipQuarantine) > 0 {
			return exitPreflightBlock
		}
		return exitOK
	}
	if !options.apply {
		fmt.Fprintln(stderr, "backfill-organizations requires explicit --apply")
		return exitUsage
	}
	requestedRunID := uuid.Nil
	if options.runID != "" {
		requestedRunID, err = uuid.Parse(options.runID)
		if err != nil {
			fmt.Fprintln(stderr, "--run-id must be a UUID")
			return exitUsage
		}
	}
	store := migration.NewPostgresOrganizationBackfillStore(db, requestedRunID, "channel-migrate-cli")
	watermark := int64(0)
	if len(users) > 0 {
		watermark = users[len(users)-1].ID
	}
	runID, err := store.Prepare(ctx, mappingDigest, report, watermark)
	if err != nil {
		fmt.Fprintf(stderr, "persist preflight: %v\n", err)
		return exitBackfill
	}
	result, err := migration.ExecuteOrganizationBackfill(ctx, store, mappingDigest, report.Operations, options.batchSize)
	if err != nil {
		_ = store.Fail(context.WithoutCancel(ctx), err)
		fmt.Fprintf(stderr, "backfill organizations: %v\n", err)
		return exitBackfill
	}
	if err := store.Complete(ctx, result); err != nil {
		_ = store.Fail(context.WithoutCancel(ctx), err)
		fmt.Fprintf(stderr, "complete backfill run: %v\n", err)
		return exitBackfill
	}
	if err := writeJSON(stdout, map[string]any{
		"status": "completed", "run_id": runID, "mapping_digest": mappingDigest,
		"result": result, "quarantine_count": len(report.Quarantine) + len(report.OwnershipQuarantine),
	}); err != nil {
		fmt.Fprintln(stderr, err)
		return exitInternal
	}
	if len(report.Quarantine)+len(report.OwnershipQuarantine) > 0 {
		return exitPreflightBlock
	}
	return exitOK
}

func parseOptions(command string, args []string, stderr io.Writer) (commandOptions, error) {
	options := commandOptions{configPath: "config.yaml", batchSize: 500}
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.StringVar(&options.configPath, "config", options.configPath, "API YAML configuration")
	flags.StringVar(&options.mappingPath, "mapping", "", "explicit legacy-role mapping JSON")
	flags.StringVar(&options.runID, "run-id", "", "migration run UUID")
	flags.IntVar(&options.batchSize, "batch-size", options.batchSize, "single-worker batch size (1..5000)")
	flags.BoolVar(&options.apply, "apply", false, "confirm organization backfill writes")
	if err := flags.Parse(args); err != nil {
		return options, err
	}
	if options.mappingPath == "" {
		return options, fmt.Errorf("--mapping is required; numeric legacy roles are never inferred")
	}
	if options.batchSize < 1 || options.batchSize > 5000 {
		return options, fmt.Errorf("--batch-size must be between 1 and 5000")
	}
	return options, nil
}

func validateDatabaseConfig(cfg config.DatabaseConfig) error {
	if strings.TrimSpace(cfg.Host) == "" || cfg.Port < 1 || cfg.Port > 65535 || strings.TrimSpace(cfg.User) == "" || strings.TrimSpace(cfg.Database) == "" {
		return fmt.Errorf("database host, port, user, and database are required")
	}
	normalizedPassword := strings.ToUpper(strings.TrimSpace(cfg.Password))
	if normalizedPassword == "" || strings.HasPrefix(normalizedPassword, "CHANGE_ME") {
		return fmt.Errorf("database password must be explicitly configured and must not use CHANGE_ME")
	}
	allowedSSL := map[string]bool{"disable": true, "allow": true, "prefer": true, "require": true, "verify-ca": true, "verify-full": true}
	if !allowedSSL[cfg.SSLMode] {
		return fmt.Errorf("unsupported database ssl_mode %q", cfg.SSLMode)
	}
	return nil
}

func connectDatabase(ctx context.Context, cfg config.DatabaseConfig) (*pgxpool.Pool, error) {
	poolConfig, err := pgxpool.ParseConfig("sslmode=" + cfg.SSLMode)
	if err != nil {
		return nil, err
	}
	poolConfig.ConnConfig.Host = cfg.Host
	poolConfig.ConnConfig.Port = uint16(cfg.Port)
	poolConfig.ConnConfig.User = cfg.User
	poolConfig.ConnConfig.Password = cfg.Password
	poolConfig.ConnConfig.Database = cfg.Database
	poolConfig.MaxConns = 4
	poolConfig.MinConns = 0
	poolConfig.MaxConnLifetime = 10 * time.Minute
	poolConfig.ConnConfig.RuntimeParams["application_name"] = "channel_migrate"
	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, err
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, err
	}
	return pool, nil
}

func writeJSON(writer io.Writer, value any) error {
	encoder := json.NewEncoder(writer)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(value); err != nil {
		return fmt.Errorf("write JSON report: %w", err)
	}
	return nil
}
