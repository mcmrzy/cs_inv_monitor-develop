package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"

	"github.com/redis/go-redis/v9"
	"golang.org/x/sync/singleflight"
)

type ModelService struct {
	modelRepo *repository.ModelRepository
	rdb       *redis.Client
	sf        singleflight.Group
}

func NewModelService(modelRepo *repository.ModelRepository) *ModelService {
	return &ModelService{modelRepo: modelRepo}
}

// NewModelServiceWithCache creates a ModelService with Redis caching for high-frequency reads.
// Device models are high-frequency, low-change data ideal for caching.
func NewModelServiceWithCache(modelRepo *repository.ModelRepository, rdb *redis.Client) *ModelService {
	return &ModelService{modelRepo: modelRepo, rdb: rdb}
}

const (
	modelListCacheKey  = "cache:model:list"
	modelCacheKeyFmt  = "cache:model:%d"
	modelCacheTTL     = 10 * time.Minute
)

type CreateModelRequest struct {
	ModelCode    string  `json:"model_code" binding:"required"`
	ModelName    string  `json:"model_name" binding:"required"`
	Manufacturer string  `json:"manufacturer"`
	Category     string  `json:"category"`
	RatedPowerKw float64 `json:"rated_power_kw"`
	Description  string  `json:"description"`
}

type UpdateModelRequest struct {
	ModelName    *string  `json:"model_name"`
	Manufacturer *string  `json:"manufacturer"`
	Category     *string  `json:"category"`
	RatedPowerKw *float64 `json:"rated_power_kw"`
	Description  *string  `json:"description"`
}

type CreateFieldRequest struct {
	FieldKey  string  `json:"field_key" binding:"required"`
	FieldName string  `json:"field_name" binding:"required"`
	FieldType string  `json:"field_type" binding:"required"`
	Unit      string  `json:"unit"`
	Sort      int     `json:"sort"`
	IsShow    *bool   `json:"is_show"`
	IsControl *bool   `json:"is_control"`
	ParseRule *string `json:"parse_rule"`
	GroupName string  `json:"group_name"`
}

type UpdateFieldRequest struct {
	FieldName *string `json:"field_name"`
	FieldType *string `json:"field_type"`
	Unit      *string `json:"unit"`
	Sort      *int    `json:"sort"`
	IsShow    *bool   `json:"is_show"`
	IsControl *bool   `json:"is_control"`
	ParseRule *string `json:"parse_rule"`
	GroupName *string `json:"group_name"`
}

type BatchUpdateFieldsRequest struct {
	Fields []repository.BatchFieldItem `json:"fields" binding:"required"`
}

type CreateProtocolRequest struct {
	TopicPattern string                 `json:"topic_pattern" binding:"required"`
	ParseType    string                 `json:"parse_type" binding:"required"`
	ParseConfig  map[string]interface{} `json:"parse_config"`
	IsActive     *bool                  `json:"is_active"`
}

type UpdateProtocolRequest struct {
	TopicPattern *string                `json:"topic_pattern"`
	ParseType    *string                `json:"parse_type"`
	ParseConfig  map[string]interface{} `json:"parse_config"`
	IsActive     *bool                  `json:"is_active"`
}

func (s *ModelService) ListModels(ctx context.Context) ([]model.DeviceModel, error) {
	// Try cache first
	if s.rdb != nil {
		if cached, err := s.rdb.Get(ctx, modelListCacheKey).Result(); err == nil {
			var models []model.DeviceModel
			if json.Unmarshal([]byte(cached), &models) == nil {
				return models, nil
			}
		}
	}

	// singleflight: prevent cache stampede when multiple requests miss simultaneously
	val, err, _ := s.sf.Do(modelListCacheKey, func() (interface{}, error) {
		models, err := s.modelRepo.ListModels(ctx)
		if err != nil {
			return nil, err
		}
		// Write to cache with jittered TTL to prevent synchronized expiry
		if s.rdb != nil {
			data, _ := json.Marshal(models)
			ttl := modelCacheTTL + time.Duration(jitterSeconds(60))*time.Second
			s.rdb.Set(ctx, modelListCacheKey, data, ttl)
		}
		return models, nil
	})
	if err != nil {
		return nil, err
	}
	return val.([]model.DeviceModel), nil
}

func (s *ModelService) GetModel(ctx context.Context, id int64) (*model.DeviceModel, error) {
	cacheKey := fmt.Sprintf(modelCacheKeyFmt, id)

	// Try cache first
	if s.rdb != nil {
		if cached, err := s.rdb.Get(ctx, cacheKey).Result(); err == nil {
			var m model.DeviceModel
			if json.Unmarshal([]byte(cached), &m) == nil {
				return &m, nil
			}
		}
	}

	// singleflight: prevent cache stampede for the same model ID
	val, err, _ := s.sf.Do(cacheKey, func() (interface{}, error) {
		m, err := s.modelRepo.GetModelByID(ctx, id)
		if err != nil || m == nil {
			return m, err
		}
		if s.rdb != nil {
			data, _ := json.Marshal(m)
			ttl := modelCacheTTL + time.Duration(jitterSeconds(60))*time.Second
			s.rdb.Set(ctx, cacheKey, data, ttl)
		}
		return m, nil
	})
	if err != nil {
		return nil, err
	}
	if val == nil {
		return nil, nil
	}
	return val.(*model.DeviceModel), nil
}

// InvalidateModelCache clears cached model data. Call after Create/Update/Delete operations.
func (s *ModelService) InvalidateModelCache(ctx context.Context, modelID int64) {
	if s.rdb == nil {
		return
	}
	keys := []string{modelListCacheKey, fmt.Sprintf(modelCacheKeyFmt, modelID)}
	s.rdb.Del(ctx, keys...)
}

func (s *ModelService) CreateModel(ctx context.Context, req *CreateModelRequest) (*model.DeviceModel, error) {
	existing, _ := s.modelRepo.GetModelByCode(ctx, req.ModelCode)
	if existing != nil {
		return nil, fmt.Errorf("型号编码 %s 已存在", req.ModelCode)
	}

	m := &model.DeviceModel{
		ModelCode:    req.ModelCode,
		ModelName:    req.ModelName,
		Manufacturer: req.Manufacturer,
		Category:     req.Category,
		RatedPowerKw: req.RatedPowerKw,
		Description:  req.Description,
	}

	if err := s.modelRepo.CreateModel(ctx, m); err != nil {
		return nil, err
	}

	s.InvalidateModelCache(ctx, m.ID)
	return m, nil
}

func (s *ModelService) UpdateModel(ctx context.Context, id int64, req *UpdateModelRequest) error {
	err := s.modelRepo.UpdateModel(ctx, id, req.ModelName, req.Manufacturer, req.Category, req.RatedPowerKw, req.Description)
	if err == nil {
		s.InvalidateModelCache(ctx, id)
	}
	return err
}

func (s *ModelService) DeleteModel(ctx context.Context, id int64) error {
	err := s.modelRepo.RetireModel(ctx, id)
	if err == nil {
		s.InvalidateModelCache(ctx, id)
	}
	return err
}

func (s *ModelService) ListFieldCatalog(ctx context.Context) ([]map[string]any, error) {
	return s.modelRepo.ListFieldCatalog(ctx)
}

func (s *ModelService) ListFieldCapabilities(ctx context.Context, modelID int64) ([]map[string]any, error) {
	return s.modelRepo.ListFieldCapabilities(ctx, modelID)
}

func (s *ModelService) ListModelCommandsV2(ctx context.Context, modelID int64) ([]map[string]any, error) {
	return s.modelRepo.ListModelCommandsV2(ctx, modelID)
}

func (s *ModelService) GetProtocolSchema(ctx context.Context, modelID int64) (map[string]any, error) {
	return s.modelRepo.GetProtocolSchema(ctx, modelID)
}

func (s *ModelService) UpdateFieldCapability(ctx context.Context, modelID int64, fieldKey string, req repository.FieldCapabilityUpdate) error {
	return s.modelRepo.UpdateFieldCapability(ctx, modelID, fieldKey, req)
}

func (s *ModelService) UpdateCommandCapability(ctx context.Context, modelID int64, commandCode string, req repository.CommandCapabilityUpdate) error {
	return s.modelRepo.UpdateCommandCapability(ctx, modelID, commandCode, req)
}

func (s *ModelService) UpsertFieldCatalog(ctx context.Context, req repository.FieldCatalogInput, operatorID int64) error { return s.modelRepo.UpsertFieldCatalog(ctx,req,operatorID) }
func (s *ModelService) BatchUpdateFieldCapabilities(ctx context.Context, modelID, operatorID int64, items []repository.FieldCapabilityPatch) error { return s.modelRepo.BatchUpdateFieldCapabilities(ctx,modelID,operatorID,items) }
func (s *ModelService) UpsertModelCommand(ctx context.Context, modelID, operatorID int64, req repository.ModelCommandInput) error { return s.modelRepo.UpsertModelCommand(ctx,modelID,operatorID,req) }
func (s *ModelService) ListProtocolVersions(ctx context.Context)([]map[string]any,error){return s.modelRepo.ListProtocolVersions(ctx)}
func (s *ModelService) CreateProtocolVersion(ctx context.Context,operatorID int64,req repository.ProtocolVersionInput)(int64,error){return s.modelRepo.CreateProtocolVersion(ctx,operatorID,req)}
func (s *ModelService) ReleaseProtocolVersion(ctx context.Context,id,operatorID int64)error{return s.modelRepo.ReleaseProtocolVersion(ctx,id,operatorID)}
func (s *ModelService) BindProtocolVersion(ctx context.Context,modelID,protocolID,operatorID int64)error{return s.modelRepo.BindProtocolVersion(ctx,modelID,protocolID,operatorID)}
func (s *ModelService) GetMigrationReport(ctx context.Context,modelID int64)(map[string]any,error){return s.modelRepo.GetMigrationReport(ctx,modelID)}
func (s *ModelService) ValidateModelRegistry(ctx context.Context,modelID int64)([]string,error){return s.modelRepo.ValidateModelRegistry(ctx,modelID)}
func (s *ModelService) ActivateModel(ctx context.Context,modelID,operatorID int64)error{return s.modelRepo.ActivateModel(ctx,modelID,operatorID)}
func (s *ModelService) GetModelDataPreview(ctx context.Context,modelID int64)(map[string]any,error){return s.modelRepo.GetModelDataPreview(ctx,modelID)}

func (s *ModelService) GetModelFields(ctx context.Context, modelID int64) ([]model.DeviceModelField, error) {
	return s.modelRepo.GetFieldsByModelID(ctx, modelID)
}

func (s *ModelService) CreateField(ctx context.Context, modelID int64, req *CreateFieldRequest) (*model.DeviceModelField, error) {
	isShow := true
	if req.IsShow != nil {
		isShow = *req.IsShow
	}
	isControl := false
	if req.IsControl != nil {
		isControl = *req.IsControl
	}

	f := &model.DeviceModelField{
		ModelID:   int32(modelID),
		FieldKey:  req.FieldKey,
		FieldName: req.FieldName,
		FieldType: req.FieldType,
		Unit:      req.Unit,
		Sort:      req.Sort,
		IsShow:    isShow,
		IsControl: isControl,
		ParseRule: req.ParseRule,
		GroupName: req.GroupName,
	}

	if err := s.modelRepo.CreateField(ctx, f); err != nil {
		return nil, err
	}

	return f, nil
}

func (s *ModelService) UpdateField(ctx context.Context, fieldID int64, req *UpdateFieldRequest) error {
	return s.modelRepo.UpdateField(ctx, fieldID, req.FieldName, req.FieldType,
		req.Unit, req.Sort, req.IsShow, req.IsControl, req.ParseRule, req.GroupName)
}

func (s *ModelService) DeleteField(ctx context.Context, fieldID int64) error {
	return s.modelRepo.DeleteField(ctx, fieldID)
}

func (s *ModelService) BatchUpdateFields(ctx context.Context, modelID int64, req *BatchUpdateFieldsRequest) error {
	return s.modelRepo.BatchUpsertFields(ctx, modelID, req.Fields)
}

func (s *ModelService) GetFieldsByModelCode(ctx context.Context, code string) ([]model.DeviceModelField, error) {
	m, err := s.modelRepo.GetModelByCode(ctx, code)
	if err != nil {
		return nil, fmt.Errorf("型号 %s 不存在", code)
	}

	return s.modelRepo.GetFieldsByModelID(ctx, m.ID)
}

// ==================== Protocol CRUD ====================

func (s *ModelService) GetProtocols(ctx context.Context, modelID int64) ([]model.DeviceModelProtocol, error) {
	return s.modelRepo.GetProtocolsByModelID(ctx, modelID)
}

func (s *ModelService) CreateProtocol(ctx context.Context, modelID int64, req *CreateProtocolRequest) (*model.DeviceModelProtocol, error) {
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	p := &model.DeviceModelProtocol{
		ModelID:      int32(modelID),
		TopicPattern: req.TopicPattern,
		ParseType:    req.ParseType,
		ParseConfig:  req.ParseConfig,
		IsActive:     isActive,
	}

	if err := s.modelRepo.CreateProtocol(ctx, p); err != nil {
		return nil, err
	}
	return p, nil
}

func (s *ModelService) UpdateProtocol(ctx context.Context, protocolID int64, req *UpdateProtocolRequest) error {
	return s.modelRepo.UpdateProtocol(ctx, protocolID, req.TopicPattern, req.ParseType, req.ParseConfig, req.IsActive)
}

func (s *ModelService) DeleteProtocol(ctx context.Context, protocolID int64) error {
	return s.modelRepo.DeleteProtocol(ctx, protocolID)
}
