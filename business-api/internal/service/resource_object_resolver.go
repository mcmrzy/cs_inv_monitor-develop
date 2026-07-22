package service

import (
	"context"

	"inv-api-server/internal/model"
)

type ResourceCoverageRepository interface {
	ResourceCoveredByGrant(context.Context, model.ActorContext, model.PermissionGrant, model.ObjectRef) (bool, error)
}

type ResourceObjectResolver struct {
	resourceType string
	repository   ResourceCoverageRepository
}

func NewResourceObjectResolver(resourceType string, repository ResourceCoverageRepository) *ResourceObjectResolver {
	return &ResourceObjectResolver{resourceType: resourceType, repository: repository}
}

func (r *ResourceObjectResolver) ResourceType() string { return r.resourceType }

func (r *ResourceObjectResolver) Covers(ctx context.Context, actor model.ActorContext, grant model.PermissionGrant, object model.ObjectRef) (bool, error) {
	if r == nil || r.repository == nil || object.ResourceType != r.resourceType || object.ResourceID == "" {
		return false, nil
	}
	return r.repository.ResourceCoveredByGrant(ctx, actor, grant, object)
}
