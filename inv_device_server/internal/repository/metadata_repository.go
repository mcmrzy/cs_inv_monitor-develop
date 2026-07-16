package repository

import (
	"context"
	"fmt"
	"sync"
	"time"

	"inv-device-server/internal/model"
)

type MetadataRepository struct {
	db      *DeviceRepository
	cache   map[int32]*model.ModelMetadata
	cacheMu sync.RWMutex
}

func NewMetadataRepository(db *DeviceRepository) *MetadataRepository {
	return &MetadataRepository{
		db:    db,
		cache: make(map[int32]*model.ModelMetadata),
	}
}

func (r *MetadataRepository) LoadAllModels(ctx context.Context) error {
	models, err := r.db.GetAllActiveModels(ctx)
	if err != nil {
		return fmt.Errorf("load models: %w", err)
	}

	r.cacheMu.Lock()
	defer r.cacheMu.Unlock()

	r.cache = make(map[int32]*model.ModelMetadata, len(models))

	for _, m := range models {
		fields, err := r.db.GetModelFields(ctx, m.ID)
		if err != nil {
			return fmt.Errorf("load fields for model %s: %w", m.ModelCode, err)
		}

		protocols, err := r.db.GetModelProtocols(ctx, m.ID)
		if err != nil {
			protocols = nil
		}

		fieldMap := make(map[string]*model.DeviceModelField)
		var fieldOrder []*model.DeviceModelField
		for i := range fields {
			fieldMap[fields[i].FieldKey] = &fields[i]
			fieldOrder = append(fieldOrder, &fields[i])
		}

		var protoPtrs []*model.DeviceModelProtocol
		for i := range protocols {
			protoPtrs = append(protoPtrs, &protocols[i])
		}

		r.cache[m.ID] = &model.ModelMetadata{
			Model:      &m,
			Fields:     fieldMap,
			FieldOrder: fieldOrder,
			Protocols:  protoPtrs,
		}
	}

	return nil
}

func (r *MetadataRepository) GetMetadata(modelID int32) (*model.ModelMetadata, bool) {
	r.cacheMu.RLock()
	defer r.cacheMu.RUnlock()
	meta, ok := r.cache[modelID]
	return meta, ok
}

func (r *MetadataRepository) GetFieldsByModelID(modelID int32) []*model.DeviceModelField {
	meta, ok := r.GetMetadata(modelID)
	if !ok {
		return nil
	}
	return meta.FieldOrder
}

func (r *MetadataRepository) GetFieldByKey(modelID int32, fieldKey string) *model.DeviceModelField {
	meta, ok := r.GetMetadata(modelID)
	if !ok {
		return nil
	}
	return meta.Fields[fieldKey]
}

func (r *MetadataRepository) ParseMetricsByModel(modelID int32, rawData map[string]interface{}) []model.ParsedField {
	meta, ok := r.GetMetadata(modelID)
	if !ok {
		return nil
	}

	result := make([]model.ParsedField, 0)
	for _, field := range meta.FieldOrder {
		if !field.IsShow {
			continue
		}
		if val, exists := rawData[field.FieldKey]; exists {
			result = append(result, model.ParsedField{
				Key:   field.FieldKey,
				Name:  field.FieldName,
				Type:  field.FieldType,
				Unit:  field.Unit,
				Value: val,
			})
		}
	}
	return result
}

func (r *MetadataRepository) Refresh(ctx context.Context) error {
	return r.LoadAllModels(ctx)
}

func (r *MetadataRepository) StartAutoRefresh(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := r.Refresh(ctx); err != nil {
			}
		}
	}
}
