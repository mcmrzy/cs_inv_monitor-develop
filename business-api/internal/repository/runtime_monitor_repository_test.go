package repository

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"inv-api-server/internal/model"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"
)

func TestRuntimeErrorsBoundedAndExpire(t *testing.T) {
	s := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	r := NewRuntimeMonitorRepository(nil, rdb)
	ctx := context.Background()
	for i := 0; i < RuntimeErrorCapacity+2; i++ {
		require.NoError(t, r.Record(ctx, model.RuntimeErrorEvent{RequestID: fmt.Sprint(i), OccurredAt: time.Now().UTC()}))
	}
	events, err := r.Recent(ctx)
	require.NoError(t, err)
	require.Len(t, events, RuntimeErrorCapacity)
	require.Equal(t, fmt.Sprint(RuntimeErrorCapacity+1), events[0].RequestID)
	require.Equal(t, "2", events[len(events)-1].RequestID)
	s.FastForward(25 * time.Hour)
	events, err = r.Recent(ctx)
	require.NoError(t, err)
	require.Empty(t, events)
}

func TestRuntimeErrorStoreDoesNotWaitForUnresponsiveRedis(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	t.Cleanup(func() { _ = listener.Close() })
	stop := make(chan struct{})
	defer close(stop)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		<-stop // Accept TCP but never answer the Redis handshake.
	}()
	shared := redis.NewClient(&redis.Options{Addr: listener.Addr().String(), MaxRetries: -1, ReadTimeout: 2 * time.Second})
	defer shared.Close()
	rdb := NewRuntimeMonitorRedis(shared)
	t.Cleanup(func() { _ = rdb.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	started := time.Now()
	err = NewRuntimeMonitorRepository(nil, rdb).Record(ctx, model.RuntimeErrorEvent{OccurredAt: started})
	require.Error(t, err)
	require.Less(t, time.Since(started), 500*time.Millisecond)
}

func TestRuntimeErrorRetentionDuringContinuousWrites(t *testing.T) {
	s := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: s.Addr()})
	defer rdb.Close()
	r := NewRuntimeMonitorRepository(nil, rdb)
	now := time.Now()
	// A still-live key with an aged event models a stream of continuing writes.
	old := fmt.Sprintf(`{"request_id":"old","occurred_at":%q}`, now.Add(-25*time.Hour).Format(time.RFC3339Nano))
	require.NoError(t, rdb.ZAdd(context.Background(), runtimeErrorsKey, redis.Z{Score: float64(now.Add(-25 * time.Hour).UnixMicro()), Member: old}).Err())
	require.NoError(t, r.Record(context.Background(), model.RuntimeErrorEvent{RequestID: "new", OccurredAt: now}))
	require.EqualValues(t, 1, rdb.ZCard(context.Background(), runtimeErrorsKey).Val())
	events, err := r.Recent(context.Background())
	require.NoError(t, err)
	require.Len(t, events, 1)
	require.Equal(t, "new", events[0].RequestID)
}

func TestRuntimeErrorStoreDeadlineSpansHandshakeAndCommand(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer listener.Close()
	var commands atomic.Int32
	done := make(chan struct{})
	go func() {
		defer close(done)
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		_ = conn.SetDeadline(time.Now().Add(time.Second))
		reader := bufio.NewReader(conn)
		for {
			header, err := reader.ReadString('\n')
			if err != nil {
				return
			}
			n, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(header, "*")))
			if err != nil {
				return
			}
			for i := 0; i < n; i++ {
				sizeLine, err := reader.ReadString('\n')
				if err != nil {
					return
				}
				size, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(sizeLine, "$")))
				if err != nil {
					return
				}
				if _, err := io.CopyN(io.Discard, reader, int64(size+2)); err != nil {
					return
				}
			}
			stage := commands.Add(1)
			time.Sleep(80 * time.Millisecond) // Each stage is below the socket timeout.
			reply := "+OK\r\n"
			if stage == 1 {
				reply = "-ERR unknown command 'hello'\r\n"
			}
			if _, err := io.WriteString(conn, reply); err != nil {
				return
			}
		}
	}()
	shared := redis.NewClient(&redis.Options{Addr: listener.Addr().String(), DB: 1, Protocol: 2, DisableIdentity: true})
	defer shared.Close()
	rdb := NewRuntimeMonitorRedis(shared)
	defer rdb.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	started := time.Now()
	err = NewRuntimeMonitorRepository(nil, rdb).Record(ctx, model.RuntimeErrorEvent{OccurredAt: started})
	elapsed := time.Since(started)
	require.Error(t, err)
	require.GreaterOrEqual(t, commands.Load(), int32(3))
	require.Less(t, elapsed, 300*time.Millisecond)
	<-done
}

func TestRuntimeSchemaChecksActualColumnsAndTypes(t *testing.T) {
	actual := map[string]string{"device_latest_state.updated_at": "timestamp with time zone"}
	checks := runtimeSchemaChecks(actual)
	for _, c := range checks {
		if c.Column == "ac_input_power" || c.Column == "ac_charge_power" {
			require.Equal(t, "missing", c.Status)
		}
		actual[c.Table+"."+c.Column] = c.ExpectedType
	}
	for _, c := range runtimeSchemaChecks(actual) {
		require.Equal(t, "ok", c.Status)
	}
	actual["device_latest_state.ac_input_power"] = "text"
	for _, c := range runtimeSchemaChecks(actual) {
		if c.Table == "device_latest_state" && c.Column == "ac_input_power" {
			require.Equal(t, "type_mismatch", c.Status)
		}
	}
}
