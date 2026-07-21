//go:build integration

package integration

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// EnvConfig holds integration test environment configuration.
type EnvConfig struct {
	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string

	RedisHost     string
	RedisPort     string
	RedisPassword string

	MQTTBroker string
	MQTTPort   string

	APIBaseURL string
}

// LoadConfig reads configuration from environment variables with sensible defaults
// matching deploy/docker-compose.test.yml.
func LoadConfig() EnvConfig {
	return EnvConfig{
		DBHost:     getEnvOrDefault("TEST_DB_HOST", "localhost"),
		DBPort:     getEnvOrDefault("TEST_DB_PORT", "15432"),
		DBUser:     getEnvOrDefault("TEST_DB_USER", "testuser"),
		DBPassword: getEnvOrDefault("TEST_DB_PASSWORD", "testpass"),
		DBName:     getEnvOrDefault("TEST_DB_NAME", "inv_test"),

		RedisHost:     getEnvOrDefault("TEST_REDIS_HOST", "localhost"),
		RedisPort:     getEnvOrDefault("TEST_REDIS_PORT", "16379"),
		RedisPassword: getEnvOrDefault("TEST_REDIS_PASSWORD", "testredispass"),

		MQTTBroker: getEnvOrDefault("TEST_MQTT_BROKER", "localhost"),
		MQTTPort:   getEnvOrDefault("TEST_MQTT_PORT", "11883"),

		APIBaseURL: getEnvOrDefault("TEST_API_BASE_URL", "http://localhost:18888"),
	}
}

func getEnvOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// ConnectDB creates a pgxpool connection to the test database.
func ConnectDB(t *testing.T, cfg EnvConfig) *pgxpool.Pool {
	t.Helper()
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		cfg.DBUser, cfg.DBPassword, cfg.DBHost, cfg.DBPort, cfg.DBName)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("failed to create DB pool: %v", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		t.Fatalf("failed to ping DB: %v", err)
	}

	return pool
}

// ConnectRedis creates a Redis client connection.
func ConnectRedis(t *testing.T, cfg EnvConfig) *redis.Client {
	t.Helper()
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", cfg.RedisHost, cfg.RedisPort),
		Password: cfg.RedisPassword,
		DB:       0,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := rdb.Ping(ctx).Err(); err != nil {
		rdb.Close()
		t.Fatalf("failed to ping Redis: %v", err)
	}

	return rdb
}

// CleanupTable truncates a table for test isolation.
func CleanupTable(t *testing.T, pool *pgxpool.Pool, table string) {
	t.Helper()
	ctx := context.Background()
	_, err := pool.Exec(ctx, fmt.Sprintf("TRUNCATE TABLE %s CASCADE", table))
	if err != nil {
		t.Fatalf("failed to truncate table %s: %v", table, err)
	}
}

// requireService checks if a TCP service is reachable. CI sets
// TEST_REQUIRE_SERVICES=true so missing dependencies fail instead of producing
// a false-green result through skipped tests.
// host can be a plain hostname (e.g. "localhost") or a full URL (e.g. "http://localhost:8888").
// When host is a URL, the port parameter is ignored and the URL's own port is used.
func requireService(t *testing.T, host, port, name string) {
	t.Helper()
	var addr string
	if u, err := url.Parse(host); err == nil && u.Host != "" {
		// host is a URL like "http://localhost:8888"
		addr = u.Host
	} else {
		addr = fmt.Sprintf("%s:%s", host, port)
	}
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		if strings.EqualFold(os.Getenv("TEST_REQUIRE_SERVICES"), "true") {
			t.Fatalf("required service %s not available at %s: %v", name, addr, err)
		}
		t.Skipf("service %s not available at %s, skipping: %v", name, addr, err)
	}
	conn.Close()
}
