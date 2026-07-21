package service

import (
	"context"
	"strconv"

	"inv-api-server/internal/model"
)

type OrganizationRelationshipRepository interface {
	OrganizationCoveredByGrant(ctx context.Context, actor model.ActorContext, grant model.PermissionGrant, targetOrganizationID int64) (bool, error)
}

type OrganizationObjectResolver struct {
	repository OrganizationRelationshipRepository
}

func NewOrganizationObjectResolver(repository OrganizationRelationshipRepository) *OrganizationObjectResolver {
	return &OrganizationObjectResolver{repository: repository}
}

func (r *OrganizationObjectResolver) ResourceType() string { return "organization" }

func (r *OrganizationObjectResolver) Covers(ctx context.Context, actor model.ActorContext, grant model.PermissionGrant, object model.ObjectRef) (bool, error) {
	if object.ResourceType != r.ResourceType() || r.repository == nil {
		return false, nil
	}
	targetID, err := strconv.ParseInt(object.ResourceID, 10, 64)
	if err != nil || targetID <= 0 {
		return false, nil
	}
	return r.repository.OrganizationCoveredByGrant(ctx, actor, grant, targetID)
}
