package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"
)

type RuntimeMonitorStore interface {
	Record(context.Context, model.RuntimeErrorEvent) error
	Recent(context.Context) ([]model.RuntimeErrorEvent, error)
	SchemaColumns(context.Context) ([]model.SchemaColumnCheck, error)
}

type RuntimeMonitorService struct{ store RuntimeMonitorStore }

func NewRuntimeMonitorService(store RuntimeMonitorStore) *RuntimeMonitorService {
	return &RuntimeMonitorService{store: store}
}

func (s *RuntimeMonitorService) Record(ctx context.Context, event model.RuntimeErrorEvent) error {
	return s.store.Record(ctx, event)
}

func (s *RuntimeMonitorService) Snapshot(ctx context.Context) model.RuntimeMonitorSnapshot {
	now := time.Now().UTC()
	result := model.RuntimeMonitorSnapshot{
		CheckedAt: now, ErrorsStatus: "unknown", Capacity: repository.RuntimeErrorCapacity,
		RetentionHours: int(repository.RuntimeErrorRetention.Hours()), Groups: []model.RuntimeErrorGroup{},
		Schema: model.RuntimeSchemaHealth{Status: "unknown", Checks: []model.SchemaColumnCheck{}},
	}
	// Independent deadlines let schema diagnostics work even when Redis is down.
	readCtx, cancel := context.WithTimeout(ctx, time.Second)
	events, err := s.store.Recent(readCtx)
	cancel()
	if err == nil {
		result.ErrorsStatus = "ok"
		result.Limited = len(events) >= repository.RuntimeErrorCapacity
		count, recent := 0, 0
		groups := make(map[string]*model.RuntimeErrorGroup)
		for _, event := range events {
			if event.OccurredAt.Before(now.Add(-repository.RuntimeErrorRetention)) || event.OccurredAt.After(now) {
				continue
			}
			count++
			if !event.OccurredAt.Before(now.Add(-5 * time.Minute)) {
				recent++
			}
			identity, _ := json.Marshal([]any{event.Service, event.Method, event.Route, event.Status, event.HTTPStatus, event.Kind, event.SQLState, event.Summary})
			sum := sha256.Sum256(identity)
			key := hex.EncodeToString(sum[:])
			group := groups[key]
			if group == nil {
				group = &model.RuntimeErrorGroup{RuntimeErrorEvent: event, Fingerprint: key, FirstSeen: event.OccurredAt, LastSeen: event.OccurredAt}
				groups[key] = group
			}
			group.Count++
			if event.OccurredAt.Before(group.FirstSeen) {
				group.FirstSeen = event.OccurredAt
			}
			if !event.OccurredAt.Before(group.LastSeen) {
				group.LastSeen = event.OccurredAt
				group.RuntimeErrorEvent = event
			}
		}
		result.Errors5m, result.EventsRetained = &recent, &count
		for _, g := range groups {
			result.Groups = append(result.Groups, *g)
		}
		sort.Slice(result.Groups, func(i, j int) bool {
			if result.Groups[i].LastSeen.Equal(result.Groups[j].LastSeen) {
				return result.Groups[i].Fingerprint < result.Groups[j].Fingerprint
			}
			return result.Groups[i].LastSeen.After(result.Groups[j].LastSeen)
		})
	} else {
		logger.Warn("Runtime error history unavailable")
	}

	schemaCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	checks, err := s.store.SchemaColumns(schemaCtx)
	cancel()
	if err == nil && len(checks) > 0 {
		result.Schema.Checks = checks
		result.Schema.Status = "ok"
		for _, check := range checks {
			if check.Status != "ok" {
				result.Schema.Status = "degraded"
			}
		}
	} else {
		logger.Warn("Runtime schema inspection unavailable")
	}
	return result
}
