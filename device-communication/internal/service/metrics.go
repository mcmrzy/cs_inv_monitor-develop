package service

import (
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// IngestMetrics tracks ingestion pipeline counters using atomic operations
// for lock-free concurrent access.  The fields are exposed via the Snapshot
// method for log-based observability or external metrics collection.
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

// PrometheusFormat returns IngestMetrics in Prometheus exposition format.
func (m *IngestMetrics) PrometheusFormat() string {
	var sb strings.Builder
	snapshot := m.Snapshot()
	
	sb.WriteString("# HELP ingest_processed_total Total messages processed by ingestion pipeline\n")
	sb.WriteString("# TYPE ingest_processed_total counter\n")
	sb.WriteString(fmt.Sprintf("ingest_processed_total %d\n", snapshot.Processed))
	
	sb.WriteString("# HELP ingest_retries_total Total retry attempts across all consumers\n")
	sb.WriteString("# TYPE ingest_retries_total counter\n")
	sb.WriteString(fmt.Sprintf("ingest_retries_total %d\n", snapshot.Retries))
	
	sb.WriteString("# HELP ingest_dlq_total Total messages sent to DLQ\n")
	sb.WriteString("# TYPE ingest_dlq_total counter\n")
	sb.WriteString(fmt.Sprintf("ingest_dlq_total %d\n", snapshot.DLQSent))
	
	sb.WriteString("# HELP ingest_permanent_errors_total Total permanent errors isolated\n")
	sb.WriteString("# TYPE ingest_permanent_errors_total counter\n")
	sb.WriteString(fmt.Sprintf("ingest_permanent_errors_total %d\n", snapshot.PermanentErrors))
	
	// Per-consumer counters (using consumer label)
	for name, counters := range snapshot.PerConsumer {
		sb.WriteString(fmt.Sprintf("# HELP ingest_processed_total_by_consumer Total messages processed per consumer\n"))
		sb.WriteString("# TYPE ingest_processed_total_by_consumer counter\n")
		sb.WriteString(fmt.Sprintf("ingest_processed_total{consumer=\"%s\"} %d\n", name, counters.Processed))
		
		sb.WriteString(fmt.Sprintf("# HELP ingest_retries_total_by_consumer Total retries per consumer\n"))
		sb.WriteString("# TYPE ingest_retries_total_by_consumer counter\n")
		sb.WriteString(fmt.Sprintf("ingest_retries_total{consumer=\"%s\"} %d\n", name, counters.Retries))
		
		sb.WriteString(fmt.Sprintf("# HELP ingest_dlq_total_by_consumer Total DLQ messages per consumer\n"))
		sb.WriteString("# TYPE ingest_dlq_total_by_consumer counter\n")
		sb.WriteString(fmt.Sprintf("ingest_dlq_total{consumer=\"%s\"} %d\n", name, counters.DLQSent))
	}
	
	return sb.String()
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
	// Collect all consumer names from all three maps
	consumerNames := make(map[string]struct{})
	m.consumerProcessed.Range(func(k, _ any) bool { consumerNames[k.(string)] = struct{}{}; return true })
	m.consumerRetries.Range(func(k, _ any) bool { consumerNames[k.(string)] = struct{}{}; return true })
	m.consumerDLQSent.Range(func(k, _ any) bool { consumerNames[k.(string)] = struct{}{}; return true })
	perConsumer := make(map[string]ConsumerCounters)
	for name := range consumerNames {
		perConsumer[name] = ConsumerCounters{
			Processed: m.loadCounter(&m.consumerProcessed, name),
			Retries:   m.loadCounter(&m.consumerRetries, name),
			DLQSent:   m.loadCounter(&m.consumerDLQSent, name),
		}
	}
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
