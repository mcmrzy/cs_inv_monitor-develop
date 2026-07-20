package model

import "encoding/json"

type ScopeKind string

const (
	ScopeSelf                       ScopeKind = "self"
	ScopeOrganization               ScopeKind = "organization"
	ScopeOrganizationAndDescendants ScopeKind = "organization_and_descendants"
	ScopeAssignedResources          ScopeKind = "assigned_resources"
	ScopeExplicitResources          ScopeKind = "explicit_resources"
)

func (s ScopeKind) Valid() bool {
	switch s {
	case ScopeSelf, ScopeOrganization, ScopeOrganizationAndDescendants, ScopeAssignedResources, ScopeExplicitResources:
		return true
	default:
		return false
	}
}

type DenyReason string

const (
	DenyInvalidRequest       DenyReason = "invalid_request"
	DenyContextInactive      DenyReason = "context_inactive"
	DenyUnknownPermission    DenyReason = "unknown_permission"
	DenyPermissionNotGranted DenyReason = "permission_not_granted"
	DenyUnsupportedScope     DenyReason = "unsupported_scope"
	DenyResolverUnavailable  DenyReason = "resolver_unavailable"
	DenyObjectOutOfScope     DenyReason = "object_out_of_scope"
)

type ActorContext struct {
	UserID            int64 `json:"user_id"`
	RootTenantID      int64 `json:"root_tenant_id"`
	OrganizationID    int64 `json:"organization_id"`
	MembershipID      int64 `json:"membership_id"`
	MembershipVersion int64 `json:"membership_version"`
}

func (a ActorContext) Valid() bool {
	return a.UserID > 0 && a.RootTenantID > 0 && a.OrganizationID > 0 && a.MembershipID > 0 && a.MembershipVersion > 0
}

type ObjectRef struct {
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
}

type AuthorizationRequest struct {
	PermissionCode string     `json:"permission_code"`
	Object         *ObjectRef `json:"object,omitempty"`
}

type PermissionGrant struct {
	ID               int64           `json:"id"`
	RoleAssignmentID int64           `json:"role_assignment_id"`
	RoleCode         string          `json:"role_code"`
	PermissionCode   string          `json:"permission_code"`
	Scope            ScopeKind       `json:"data_scope"`
	ScopeDefinition  json.RawMessage `json:"scope_definition"`
}

type AuthorizationDecision struct {
	Allowed                 bool       `json:"allowed"`
	Reason                  DenyReason `json:"reason,omitempty"`
	MatchedGrantID          int64      `json:"matched_grant_id,omitempty"`
	MatchedRoleAssignmentID int64      `json:"matched_role_assignment_id,omitempty"`
}

type ScopePlan struct {
	Actor          ActorContext      `json:"-"`
	PermissionCode string            `json:"-"`
	ResourceType   string            `json:"-"`
	Grants         []PermissionGrant `json:"-"`
	DenyReason     DenyReason        `json:"-"`
}
