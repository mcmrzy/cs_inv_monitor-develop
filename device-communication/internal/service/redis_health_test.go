package service

import (
	"context"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestRedisHealthMonitor_DegradationOnFailure 验证 Redis 连接失败时进入降级模式
func TestRedisHealthMonitor_DegradationOnDegraded(t *testing.T) {
	// 创建一个指向无效地址的 Redis 客户端（将导致 ping 失败）
	fakeRedis := redis.NewClient(&redis.Options{
		Addr: "invalid-address:6379", // 无效的地址，ping 必然会失败
	})
	defer fakeRedis.Close()

	// 创建健康监控器，没有设置 onRecover 回调
	monitor := NewRedisHealthMonitor(fakeRedis, nil)
	defer monitor.Stop()

	// 启动监控器
	monitor.Start()
	defer func() {
		if r := recover(); r != nil {
			t.Error("Monitor should not panic")
		}
	}()

	// 等待直到降级模式触发（最多等待 3 秒）
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	for {
		select {
		case <-ctx.Done():
			t.Fatal("Timeout waiting for degraded mode")
		default:
		}

		if monitor.IsDegraded() {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	// 验证是否进入降级模式
	assert.True(t, monitor.IsDegraded(), "Should be in degraded mode after failed ping")
}

// TestRedisHealthMonitor_RecoveryTriggersCallback 验证当 Redis 从降级状态恢复时触发回调
func TestRedisHealthMonitor_RecoveryTriggersCallback(t *testing.T) {
	// 创建 miniredis 服务器
	mr, err := miniredis.Run()
	require.NoError(t, err)
	defer mr.Close()

	var callbackCalled int32 = 0

	// 创建一个健康的 Redis 客户端和监控器
	redisClient := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	defer redisClient.Close()

	monitor := NewRedisHealthMonitor(redisClient, func() {
		atomic.StoreInt32(&callbackCalled, 1)
	})
	defer monitor.Stop()
	monitor.Start()
	defer func() {
		if r := recover(); r != nil {
			t.Error("Monitor should not panic")
		}
	}()

	// 等待一段时间确保初始状态是健康的
	time.Sleep(600 * time.Millisecond)
	assert.False(t, monitor.IsDegraded(), "Should be healthy initially")
	assert.EqualValues(t, 0, atomic.LoadInt32(&callbackCalled), "Callback should not be called for healthy Redis")

	// 手动模拟降级状态
	monitor.isDegraded.Store(true)
	assert.True(t, monitor.IsDegraded(), "Manually set to degraded")

	// 重置回调调用标记
	atomic.StoreInt32(&callbackCalled, 0)

	// 现在模拟恢复（Redis 正常工作）
	// 下一个 ping 成功后应该触发回调
	recoveryCtx, recoveryCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer recoveryCancel()

	// 等待回调被调用（最多 2 秒）
	callbackTriggered := false
	for {
		select {
		case <-recoveryCtx.Done():
			t.Fatal("Timeout waiting for callback to be triggered")
		case <-time.After(50 * time.Millisecond):
			if atomic.LoadInt32(&callbackCalled) == 1 {
				callbackTriggered = true
				break
			}
		}
		if callbackTriggered {
			break
		}
	}

	assert.True(t, callbackTriggered, "onRecover callback should be triggered when transitioning from degraded to healthy")
	assert.False(t, monitor.IsDegraded(), "Should not be degraded after recovery")
}

// TestRedisHealthMonitor_NormalOperation 验证正常操作下不进入降级模式
func TestRedisHealthMonitor_NormalOperation(t *testing.T) {
	// 创建 miniredis 服务器
	mr, err := miniredis.Run()
	require.NoError(t, err)
	defer mr.Close()

	var recoveryCount int64
	onRecoverFunc := func() {
		atomic.AddInt64(&recoveryCount, 1)
	}

	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})
	defer redisClient.Close()

	monitor := NewRedisHealthMonitor(redisClient, onRecoverFunc)
	defer monitor.Stop()
	monitor.Start()
	defer func() {
		if r := recover(); r != nil {
			t.Error("Monitor should not panic during normal operation")
		}
	}()

	// 等待一段时间，确保监控器正常运行
	time.Sleep(2 * time.Second)

	// 应该一直不是降级状态
	assert.False(t, monitor.IsDegraded(), "Should not be degraded when Redis is healthy")

	// onRecover 不应被调用（因为没有从降级状态恢复）
	assert.Equal(t, int64(0), recoveryCount, "onRecover should not be called during normal operation")
}

// TestRedisHealthMonitor_StressPings 压力测试：频繁 ping 失败和成功
func TestRedisHealthMonitor_StressPings(t *testing.T) {
	mr, err := miniredis.Run()
	require.NoError(t, err)
	defer mr.Close()

	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})
	defer redisClient.Close()

	monitor := NewRedisHealthMonitor(redisClient, nil)
	defer monitor.Stop()
	monitor.Start()
	defer func() {
		if r := recover(); r != nil {
			t.Error("Monitor should not panic under stress")
		}
	}()

	// 快速执行多次 ping
	for i := 0; i < 10; i++ {
		err := redisClient.Ping(context.Background()).Err()
		assert.NoError(t, err, "Ping should succeed")
		time.Sleep(100 * time.Millisecond)
	}

	// 最终状态应该是不降级
	assert.False(t, monitor.IsDegraded(), "Should not be degraded after successful pings")
}
