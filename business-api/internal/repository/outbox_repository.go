package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type OutboxEvent struct {
	EventID            uuid.UUID
	RootTenantID       int64
	AggregateType      string
	AggregateID        string
	EventType          string
	EventSchemaVersion string
	Envelope           json.RawMessage
}

type OutboxRepository struct{}

func NewOutboxRepository() *OutboxRepository { return &OutboxRepository{} }

// Enqueue requires the caller's existing transaction so the business mutation
// and its event are committed or rolled back together.
func (r *OutboxRepository) Enqueue(ctx context.Context, tx pgx.Tx, event OutboxEvent) error {
	if tx == nil || event.EventID == uuid.Nil || event.RootTenantID <= 0 ||
		event.AggregateType == "" || event.AggregateID == "" || event.EventType == "" ||
		event.EventSchemaVersion == "" || len(event.Envelope) == 0 || !json.Valid(event.Envelope) {
		return fmt.Errorf("invalid transactional outbox event")
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO transactional_outbox(
			event_id,root_tenant_id,aggregate_type,aggregate_id,event_type,event_schema_version,envelope
		) VALUES($1,$2,$3,$4,$5,$6,$7)
	`, event.EventID, event.RootTenantID, event.AggregateType, event.AggregateID,
		event.EventType, event.EventSchemaVersion, event.Envelope)
	return err
}
