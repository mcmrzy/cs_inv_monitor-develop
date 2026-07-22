package service

import (
	"context"
	"strings"

	"inv-api-server/internal/model"
)

type AuthorizationRepository interface {
	ValidateContext(ctx context.Context, actor model.ActorContext) (bool, error)
	LoadPermissionGrants(ctx context.Context, actor model.ActorContext, permissionCode string) ([]model.PermissionGrant, error)
}

type ObjectResolver interface {
	ResourceType() string
	Covers(ctx context.Context, actor model.ActorContext, grant model.PermissionGrant, object model.ObjectRef) (bool, error)
}

type PermissionRegistry interface {
	Known(permissionCode string) bool
}

type staticPermissionRegistry map[string]struct{}

func (r staticPermissionRegistry) Known(permissionCode string) bool {
	_, ok := r[permissionCode]
	return ok
}

var channelPermissionRegistry = staticPermissionRegistry{
	"organization:view": {}, "organization:manage": {},
	"member:view": {}, "member:manage": {},
	"invitation:create": {}, "invitation:revoke": {},
	"device:view": {}, "device:control": {}, "device:unbind": {}, "device:transfer": {},
	"station:view": {}, "station:manage": {}, "asset:claim": {}, "asset:transfer": {},
}

type AuthorizationService struct {
	repository AuthorizationRepository
	registry   PermissionRegistry
	resolvers  map[string]ObjectResolver
}

func NewAuthorizationService(repository AuthorizationRepository, resolvers ...ObjectResolver) *AuthorizationService {
	service := &AuthorizationService{
		repository: repository,
		registry:   channelPermissionRegistry,
		resolvers:  make(map[string]ObjectResolver),
	}
	for _, resolver := range resolvers {
		if resolver != nil && resolver.ResourceType() != "" {
			service.resolvers[resolver.ResourceType()] = resolver
		}
	}
	return service
}

func (s *AuthorizationService) Authorize(ctx context.Context, actor model.ActorContext, request model.AuthorizationRequest) (model.AuthorizationDecision, error) {
	decision := model.AuthorizationDecision{Reason: model.DenyInvalidRequest}
	if !actor.Valid() || request.Object == nil || request.Object.ResourceType == "" || request.Object.ResourceID == "" {
		return decision, nil
	}
	if !s.registry.Known(request.PermissionCode) {
		decision.Reason = model.DenyUnknownPermission
		return decision, nil
	}
	permissionResource, _, ok := strings.Cut(request.PermissionCode, ":")
	if !ok || permissionResource != request.Object.ResourceType {
		return decision, nil
	}
	active, err := s.repository.ValidateContext(ctx, actor)
	if err != nil {
		return decision, err
	}
	if !active {
		decision.Reason = model.DenyContextInactive
		return decision, nil
	}
	grants, err := s.repository.LoadPermissionGrants(ctx, actor, request.PermissionCode)
	if err != nil {
		return decision, err
	}
	matching := make([]model.PermissionGrant, 0, len(grants))
	unsupportedScope := false
	for _, grant := range grants {
		if grant.PermissionCode != request.PermissionCode {
			continue
		}
		if !grant.Scope.Valid() {
			unsupportedScope = true
			continue
		}
		matching = append(matching, grant)
	}
	if len(matching) == 0 {
		if unsupportedScope {
			decision.Reason = model.DenyUnsupportedScope
		} else {
			decision.Reason = model.DenyPermissionNotGranted
		}
		return decision, nil
	}
	resolver := s.resolvers[request.Object.ResourceType]
	if resolver == nil {
		decision.Reason = model.DenyResolverUnavailable
		return decision, nil
	}
	for _, grant := range matching {
		covered, err := resolver.Covers(ctx, actor, grant, *request.Object)
		if err != nil {
			return decision, err
		}
		if covered {
			return model.AuthorizationDecision{
				Allowed: true, MatchedGrantID: grant.ID,
				MatchedRoleAssignmentID: grant.RoleAssignmentID,
			}, nil
		}
	}
	decision.Reason = model.DenyObjectOutOfScope
	return decision, nil
}

func (s *AuthorizationService) BuildScope(ctx context.Context, actor model.ActorContext, permissionCode, resourceType string) (model.ScopePlan, error) {
	plan := model.ScopePlan{Actor: actor, PermissionCode: permissionCode, ResourceType: resourceType, DenyReason: model.DenyInvalidRequest}
	if !actor.Valid() || resourceType == "" || !s.registry.Known(permissionCode) {
		if !s.registry.Known(permissionCode) {
			plan.DenyReason = model.DenyUnknownPermission
		}
		return plan, nil
	}
	prefix, _, ok := strings.Cut(permissionCode, ":")
	if !ok || prefix != resourceType {
		return plan, nil
	}
	active, err := s.repository.ValidateContext(ctx, actor)
	if err != nil {
		return plan, err
	}
	if !active {
		plan.DenyReason = model.DenyContextInactive
		return plan, nil
	}
	grants, err := s.repository.LoadPermissionGrants(ctx, actor, permissionCode)
	if err != nil {
		return plan, err
	}
	for _, grant := range grants {
		if grant.PermissionCode == permissionCode && grant.Scope.Valid() {
			plan.Grants = append(plan.Grants, grant)
		}
	}
	if len(plan.Grants) == 0 {
		plan.DenyReason = model.DenyPermissionNotGranted
		return plan, nil
	}
	plan.DenyReason = ""
	return plan, nil
}
