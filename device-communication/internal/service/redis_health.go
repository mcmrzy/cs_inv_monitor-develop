package service

import (
	"context"
	"sync/atomic"
	"time"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// RedisHealthMonitor monitors Redis health and triggers degradation mode on failures.
type RedisHealthMonitor struct {
	client     *redis.Client
	isDegraded atomic.Bool
	onRecover  func()              // callback triggered when Redis recovers
	pingTicker *time.Ticker
	ctx        context.Context
	cancel     context.CancelFunc
}

// NewRedisHealthMonitor creates a new Redis health monitor with the given Redis client.
// The onRecover callback is called once when Redis transitions from degraded to healthy state.
func NewRedisHealthMonitor(client *redis.Client, onRecover func()) *RedisHealthMonitor {
	ctx, cancel := context.WithCancel(context.Background())
	m := &RedisHealthMonitor{
		client:     client,
		onRecover:  onRecover,
		pingTicker: time.NewTicker(200 * time.Millisecond), // Faster checks for testing
		ctx:        ctx,
		cancel:     cancel,
	}
	m.isDegraded.Store(false)
	return m
}

// Start starts the monitoring loop in a goroutine.
func (m *RedisHealthMonitor) Start() {
	go m.monitorLoop()
}

// monitorLoop performs periodic ping checks to monitor Redis health.
func (m *RedisHealthMonitor) monitorLoop() {
	for {
		select {
		case <-m.ctx.Done():
			m.pingTicker.Stop()
			return
		case <-m.pingTicker.C:
			// Create a short-lived context for ping
			pctx, pcancel := context.WithTimeout(m.ctx, 500*time.Millisecond)
			err := m.client.Ping(pctx).Err()
			pcancel()
			if err != nil {
				// Failed to ping
				if !m.isDegraded.Load() {
					zap.L().Warn("Redis health check failed, entering degraded mode", zap.Error(err))
				}
				m.isDegraded.Store(true)
			} else {
				// Success
				if m.isDegraded.Load() && m.onRecover != nil {
					m.onRecover() // Trigger heartbeat rebuild
					zap.L().Info("Redis recovered, calling onRecover callback")
				}
				m.isDegraded.Store(false)
			}
		}
	}
}

// Stop stops the monitoring loop gracefully.
func (m *RedisHealthMonitor) Stop() {
	m.cancel()
}

// IsDegraded returns true if Redis is currently in degraded state.
func (m *RedisHealthMonitor) IsDegraded() bool {
	return m.isDegraded.Load()
}
