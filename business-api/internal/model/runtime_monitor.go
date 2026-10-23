package model

import "time"

// RuntimeErrorEvent intentionally excludes request parameters, headers, bodies,
// actor identities and raw database errors. Route is a registered route template.
type RuntimeErrorEvent struct {
	RequestID  string    `json:"request_id"`
	Service    string    `json:"service"`
	Method     string    `json:"method"`
	Route      string    `json:"route"`
	Status     int       `json:"status"`
	HTTPStatus int       `json:"http_status"`
	DurationMS int64     `json:"duration_ms"`
	Kind       string    `json:"kind"`
	SQLState   string    `json:"sql_state,omitempty"`
	Summary    string    `json:"summary"`
	OccurredAt time.Time `json:"occurred_at"`
}

type RuntimeErrorGroup struct {
	RuntimeErrorEvent
	Fingerprint string    `json:"fingerprint"`
	Count       int       `json:"count"`
	FirstSeen   time.Time `json:"first_seen"`
	LastSeen    time.Time `json:"last_seen"`
}

type SchemaColumnCheck struct {
	Table        string `json:"table"`
	Column       string `json:"column"`
	ExpectedType string `json:"expected_type"`
	ActualType   string `json:"actual_type,omitempty"`
	Status       string `json:"status"` // ok, missing, type_mismatch
}

type RuntimeSchemaHealth struct {
	Status string              `json:"status"` // ok, degraded, unknown
	Checks []SchemaColumnCheck `json:"checks"`
}

type RuntimeMonitorSnapshot struct {
	CheckedAt      time.Time           `json:"checked_at"`
	ErrorsStatus   string              `json:"errors_status"`
	Errors5m       *int                `json:"errors_5m"`
	EventsRetained *int                `json:"events_retained"`
	Limited        bool                `json:"limited"`
	RetentionHours int                 `json:"retention_hours"`
	Capacity       int                 `json:"capacity"`
	Groups         []RuntimeErrorGroup `json:"groups"`
	Schema         RuntimeSchemaHealth `json:"schema"`
}
