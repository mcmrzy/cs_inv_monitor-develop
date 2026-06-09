package service

import (
	"context"
	"fmt"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
)

type ModelService struct {
	modelRepo *repository.ModelRepository
}

func NewModelService(modelRepo *repository.ModelRepository) *ModelService {
	return &ModelService{modelRepo: modelRepo}
}

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
}

type UpdateFieldRequest struct {
	FieldName  *string `json:"field_name"`
	FieldType  *string `json:"field_type"`
	Unit       *string `json:"unit"`
	Sort       *int    `json:"sort"`
	IsShow     *bool   `json:"is_show"`
	IsControl  *bool   `json:"is_control"`
	ParseRule  *string `json:"parse_rule"`
}

type BatchUpdateFieldsRequest struct {
	Fields []repository.BatchFieldItem `json:"fields" binding:"required"`
}

func (s *ModelService) ListModels(ctx context.Context) ([]model.DeviceModel, error) {
	return s.modelRepo.ListModels(ctx)
}

func (s *ModelService) GetModel(ctx context.Context, id int64) (*model.DeviceModel, error) {
	return s.modelRepo.GetModelByID(ctx, id)
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

	return m, nil
}

func (s *ModelService) UpdateModel(ctx context.Context, id int64, req *UpdateModelRequest) error {
	return s.modelRepo.UpdateModel(ctx, id, req.ModelName, req.Manufacturer, req.Category, req.RatedPowerKw, req.Description)
}

func (s *ModelService) DeleteModel(ctx context.Context, id int64) error {
	return s.modelRepo.DeleteModel(ctx, id)
}

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
	}

	if err := s.modelRepo.CreateField(ctx, f); err != nil {
		return nil, err
	}

	return f, nil
}

func (s *ModelService) UpdateField(ctx context.Context, fieldID int64, req *UpdateFieldRequest) error {
	return s.modelRepo.UpdateField(ctx, fieldID, req.FieldName, req.FieldType,
		req.Unit, req.Sort, req.IsShow, req.IsControl, req.ParseRule)
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
