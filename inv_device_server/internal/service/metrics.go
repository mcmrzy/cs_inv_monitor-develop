package service

import (
	"sync"
	"sync/atomic"
	"time"
)

// IngestMetrics tracks ingestion pipeline counters using atomic operations
// for lock-free concurrent access.  The fields are exposed via the Snapshot
// method for Prometheus/Grafana scraping or log-based observability.
type IngestMetrics struct {
	// Total messages processed (successful + failed).
	processed atomic.Int64
	// Total retry attempts across all messages.
	retries atomic.Int64
	// Total messages sent to the DLQ after exhausting retries.
	dlqSent atomic.Int64
	// Total permanent errors isolated (not retried, sent to ingest_errors).
	permanentErrors atomic.Int64
	// Total processing time in nanoseconds (for average latency calculation).
	totalLatencyNs atomic.Int64
	// Per-consumer counters.
	consumerRetries   sync.Map // map[string]*atomic.Int64
	consumerDLQSent   sync.Map // map[string]*atomic.Int64
	consumerProcessed sync.Map // map[string]*atomic.Int64
}

// NewIngestMetrics creates a zero-value metrics tracker.
func NewIngestMetrics() *IngestMetrics {
	return &IngestMetrics{}
}

// IncProcessed increments the total processed counter for the given consumer.
func (m *IngestMetrics) IncProcessed(consumer string) {
	m.processed.Add(1)
	m.getOrCreateCounter(&m.consumerProcessed, consumer).Add(1)
}

// IncRetry increments the retry counter for the given consumer.
func (m *IngestMetrics) IncRetry(consumer string) {
	m.retries.Add(1)
	m.getOrCreateCounter(&m.consumerRetries, consumer).Add(1)
}

// IncDLQ increments the DLQ-sent counter for the given consumer.
func (m *IngestMetrics) IncDLQ(consumer string) {
	m.dlqSent.Add(1)
	m.getOrCreateCounter(&m.consumerDLQSent, consumer).Add(1)
}

// IncPermanentError increments the permanent-error counter.
func (m *IngestMetrics) IncPermanentError() {
	m.permanentErrors.Add(1)
}

// RecordLatency records the processing duration for a single message.
func (m *IngestMetrics) RecordLatency(d time.Duration) {
	m.totalLatencyNs.Add(int64(d))
}

// MetricsSnapshot is a point-in-time view of all counters.
type MetricsSnapshot struct {
	Processed       int64                       `json:"processed"`
	Retries         int64                       `json:"retries"`
	DLQSent         int64                       `json:"dlq_sent"`
	PermanentErrors int64                       `json:"permanent_errors"`
	AvgLatencyMs    float64                     `json:"avg_latency_ms"`
	PerConsumer     map[string]ConsumerCounters `json:"per_consumer"`
}

// ConsumerCounters holds per-consumer metrics.
type ConsumerCounters struct {
	Processed int64 `json:"processed"`
	Retries   int64 `json:"retries"`
	DLQSent   int64 `json:"dlq_sent"`
}

// Snapshot returns the current state of all counters.
func (m *IngestMetrics) Snapshot() MetricsSnapshot {
	processed := m.processed.Load()
	totalLatency := m.totalLatencyNs.Load()
	avgMs := 0.0
	if processed > 0 {
		avgMs = float64(totalLatency) / float64(processed) / float64(time.Millisecond)
	}
	perConsumer := make(map[string]ConsumerCounters)
	m.consumerProcessed.Range(func(k, v any) bool {
		name := k.(string)
		perConsumer[name] = ConsumerCounters{
			Processed: v.(*atomic.Int64).Load(),
			Retries:   m.loadCounter(&m.consumerRetries, name),
			DLQSent:   m.loadCounter(&m.consumerDLQSent, name),
		}
		return true
	})
	return MetricsSnapshot{
		Processed:       processed,
		Retries:         m.retries.Load(),
		DLQSent:         m.dlqSent.Load(),
		PermanentErrors: m.permanentErrors.Load(),
		AvgLatencyMs:    avgMs,
		PerConsumer:     perConsumer,
	}
}

// getOrCreateCounter returns the atomic counter for the given consumer name,
// creating it on first access.
func (m *IngestMetrics) getOrCreateCounter(sm *sync.Map, consumer string) *atomic.Int64 {
	if v, ok := sm.Load(consumer); ok {
		return v.(*atomic.Int64)
	}
	c := &atomic.Int64{}
	v, _ := sm.LoadOrStore(consumer, c)
	return v.(*atomic.Int64)
}

// loadCounter returns the value of a counter, or 0 if it doesn't exist.
func (m *IngestMetrics) loadCounter(sm *sync.Map, consumer string) int64 {
	v, ok := sm.Load(consumer)
	if !ok {
		return 0
	}
	return v.(*atomic.Int64).Load()
}
