package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

const RuntimeErrorCapacity = 1000
const RuntimeErrorRetention = 24 * time.Hour
const runtimeErrorsKey = "monitor:business-api:runtime-errors:v2"

// Atomically enforce both event age and capacity, including during continuous writes.
var recordRuntimeError = redis.NewScript(`
redis.call('ZADD', KEYS[1], ARGV[4], ARGV[1])
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[5])
redis.call('ZREMRANGEBYRANK', KEYS[1], 0, -ARGV[2] - 1)
redis.call('EXPIRE', KEYS[1], ARGV[3])
return 1`)

var readRuntimeErrors = redis.NewScript(`
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', ARGV[1])
return redis.call('ZREVRANGE', KEYS[1], 0, ARGV[2] - 1)`)

// A dedicated pool honors the end-to-end context deadline, including handshake
// and script fallback. It must be closed by the server lifecycle owner.
func NewRuntimeMonitorRedis(shared *redis.Client) *redis.Client {
	opts := *shared.Options()
	opts.ContextTimeoutEnabled = true
	opts.MaxRetries = -1
	opts.DialTimeout = 100 * time.Millisecond
	opts.ReadTimeout = 100 * time.Millisecond
	opts.WriteTimeout = 100 * time.Millisecond
	opts.PoolTimeout = 100 * time.Millisecond
	opts.PoolSize = 4
	opts.MinIdleConns = 0
	return redis.NewClient(&opts)
}

type RuntimeMonitorRepository struct {
	db  *pgxpool.Pool
	rdb *redis.Client
}

func NewRuntimeMonitorRepository(db *pgxpool.Pool, rdb *redis.Client) *RuntimeMonitorRepository {
	return &RuntimeMonitorRepository{db: db, rdb: rdb}
}

func (r *RuntimeMonitorRepository) Record(ctx context.Context, event model.RuntimeErrorEvent) error {
	if r.rdb == nil {
		return errors.New("runtime error store unavailable")
	}
	data, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode runtime error: %w", err)
	}
	return recordRuntimeError.Run(ctx, r.rdb, []string{runtimeErrorsKey}, string(data), RuntimeErrorCapacity, int(RuntimeErrorRetention.Seconds()), event.OccurredAt.UnixMicro(), time.Now().Add(-RuntimeErrorRetention).UnixMicro()).Err()
}

func (r *RuntimeMonitorRepository) Recent(ctx context.Context) ([]model.RuntimeErrorEvent, error) {
	if r.rdb == nil {
		return nil, errors.New("runtime error store unavailable")
	}
	rows, err := readRuntimeErrors.Run(ctx, r.rdb, []string{runtimeErrorsKey}, time.Now().Add(-RuntimeErrorRetention).UnixMicro(), RuntimeErrorCapacity).StringSlice()
	if err != nil {
		return nil, fmt.Errorf("read runtime errors: %w", err)
	}
	events := make([]model.RuntimeErrorEvent, 0, len(rows))
	for _, raw := range rows {
		var event model.RuntimeErrorEvent
		if err := json.Unmarshal([]byte(raw), &event); err != nil {
			return nil, fmt.Errorf("decode runtime error: %w", err)
		}
		events = append(events, event)
	}
	return events, nil
}

// These are read requirements, not migration numbers. A stamped migration does
// not establish that a production table actually has these columns.
func runtimeSchemaRequirements() []model.SchemaColumnCheck {
	checks := make([]model.SchemaColumnCheck, 0, 10)
	for _, column := range []string{"pv_total_power", "ac_active_power", "battery_power", "battery_soc", "ac_input_power", "ac_charge_power"} {
		checks = append(checks, model.SchemaColumnCheck{Table: "device_latest_state", Column: column, ExpectedType: "real"})
	}
	checks = append(checks, model.SchemaColumnCheck{Table: "device_latest_state", Column: "updated_at", ExpectedType: "timestamp with time zone"})
	for _, column := range []string{"ac_input_power", "ac_charge_power"} {
		checks = append(checks, model.SchemaColumnCheck{Table: "device_telemetry_3min", Column: column, ExpectedType: "real"})
	}
	return checks
}

func runtimeSchemaChecks(actual map[string]string) []model.SchemaColumnCheck {
	checks := runtimeSchemaRequirements()
	for i := range checks {
		c := &checks[i]
		c.ActualType = actual[c.Table+"."+c.Column]
		switch c.ActualType {
		case "":
			c.Status = "missing"
		case c.ExpectedType:
			c.Status = "ok"
		default:
			c.Status = "type_mismatch"
		}
	}
	return checks
}

func (r *RuntimeMonitorRepository) SchemaColumns(ctx context.Context) ([]model.SchemaColumnCheck, error) {
	if r.db == nil {
		return nil, errors.New("schema inspection unavailable")
	}
	rows, err := r.db.Query(ctx, `SELECT table_name,column_name,data_type FROM information_schema.columns
		WHERE table_schema='public' AND table_name IN ('device_latest_state','device_telemetry_3min')`)
	if err != nil {
		return nil, fmt.Errorf("inspect runtime schema: %w", err)
	}
	defer rows.Close()
	actual := make(map[string]string)
	for rows.Next() {
		var table, column, dataType string
		if err := rows.Scan(&table, &column, &dataType); err != nil {
			return nil, err
		}
		actual[table+"."+column] = dataType
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return runtimeSchemaChecks(actual), nil
}
