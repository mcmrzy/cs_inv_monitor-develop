package service

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestIngestMetrics_IncProcessed(t *testing.T) {
	m := NewIngestMetrics()
	m.IncProcessed("parser")
	m.IncProcessed("parser")
	m.IncProcessed("alert")

	snap := m.Snapshot()
	assert.Equal(t, int64(3), snap.Processed)
	assert.Equal(t, int64(2), snap.PerConsumer["parser"].Processed)
	assert.Equal(t, int64(1), snap.PerConsumer["alert"].Processed)
}

func TestIngestMetrics_IncRetry(t *testing.T) {
	m := NewIngestMetrics()
	m.IncRetry("parser")
	m.IncRetry("parser")

	snap := m.Snapshot()
	assert.Equal(t, int64(2), snap.Retries)
	assert.Equal(t, int64(2), snap.PerConsumer["parser"].Retries)
}

func TestIngestMetrics_IncDLQ(t *testing.T) {
	m := NewIngestMetrics()
	m.IncDLQ("parser")
	m.IncDLQ("alert")
	m.IncDLQ("alert")

	snap := m.Snapshot()
	assert.Equal(t, int64(3), snap.DLQSent)
	assert.Equal(t, int64(1), snap.PerConsumer["parser"].DLQSent)
	assert.Equal(t, int64(2), snap.PerConsumer["alert"].DLQSent)
}

func TestIngestMetrics_IncPermanentError(t *testing.T) {
	m := NewIngestMetrics()
	m.IncPermanentError()
	m.IncPermanentError()

	snap := m.Snapshot()
	assert.Equal(t, int64(2), snap.PermanentErrors)
}

func TestIngestMetrics_RecordLatency(t *testing.T) {
	m := NewIngestMetrics()
	m.IncProcessed("parser")
	m.RecordLatency(100 * time.Millisecond)

	snap := m.Snapshot()
	// Average should be approximately 100ms
	assert.InDelta(t, 100.0, snap.AvgLatencyMs, 1.0)
}

func TestIngestMetrics_Snapshot_Empty(t *testing.T) {
	m := NewIngestMetrics()
	snap := m.Snapshot()

	assert.Equal(t, int64(0), snap.Processed)
	assert.Equal(t, int64(0), snap.Retries)
	assert.Equal(t, int64(0), snap.DLQSent)
	assert.Equal(t, int64(0), snap.PermanentErrors)
	assert.Equal(t, 0.0, snap.AvgLatencyMs)
	assert.Empty(t, snap.PerConsumer)
}

func TestIngestMetrics_PrometheusFormat_Empty(t *testing.T) {
	m := NewIngestMetrics()
	output := m.PrometheusFormat()

	// Should contain total counters with zero values
	assert.Contains(t, output, "ingest_processed_total 0")
	assert.Contains(t, output, "ingest_retries_total 0")
	assert.Contains(t, output, "ingest_dlq_total 0")
	assert.Contains(t, output, "ingest_permanent_errors_total 0")
}

func TestIngestMetrics_PrometheusFormat_WithValues(t *testing.T) {
	m := NewIngestMetrics()
	m.IncProcessed("parser")
	m.IncProcessed("parser")
	m.IncRetry("parser")
	m.IncDLQ("alert")
	m.IncPermanentError()

	output := m.PrometheusFormat()

	// Verify total counters
	assert.Contains(t, output, "ingest_processed_total 2")
	assert.Contains(t, output, "ingest_retries_total 1")
	assert.Contains(t, output, "ingest_dlq_total 1")
	assert.Contains(t, output, "ingest_permanent_errors_total 1")

	// Verify per-consumer labels (format: consumer="name")
	assert.Contains(t, output, `ingest_processed_total{consumer="parser"} 2`)
	assert.Contains(t, output, `ingest_retries_total{consumer="parser"} 1`)
	assert.Contains(t, output, `ingest_dlq_total{consumer="alert"} 1`)
}

func TestIngestMetrics_PrometheusFormat_ContainsHelpAndType(t *testing.T) {
	m := NewIngestMetrics()
	output := m.PrometheusFormat()

	// Prometheus exposition format requires HELP and TYPE
	lines := strings.Split(output, "\n")
	helpCount := 0
	typeCount := 0
	for _, line := range lines {
		if strings.HasPrefix(line, "# HELP ") {
			helpCount++
		}
		if strings.HasPrefix(line, "# TYPE ") {
			typeCount++
		}
	}
	assert.GreaterOrEqual(t, helpCount, 4, "should have at least 4 HELP lines")
	assert.GreaterOrEqual(t, typeCount, 4, "should have at least 4 TYPE lines")
}
