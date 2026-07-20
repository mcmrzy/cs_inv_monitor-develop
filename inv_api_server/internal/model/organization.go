package model

import "time"

const (
	OrganizationStatusActive       = "active"
	OrganizationStatusDisabled     = "disabled"
	OrganizationStatusQuarantined  = "quarantined"
	OrganizationAPIStatusSuspended = "suspended"
)

func ProjectOrganizationStatus(persistenceStatus string) string {
	if persistenceStatus == OrganizationStatusQuarantined {
		return OrganizationAPIStatusSuspended
	}
	return persistenceStatus
}

func ProjectMembershipStatus(persistenceStatus string) string {
	if persistenceStatus == "revoked" {
		return "disabled"
	}
	return persistenceStatus
}

type Organization struct {
	ID           int64      `json:"id"`
	RootTenantID int64      `json:"root_tenant_id"`
	ParentID     *int64     `json:"parent_id,omitempty"`
	Type         string     `json:"type"`
	Code         string     `json:"code,omitempty"`
	Name         string     `json:"name"`
	Status       string     `json:"status"`
	Version      int64      `json:"version"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	DeletedAt    *time.Time `json:"-"`
}

type OrganizationMembership struct {
	ID             int64      `json:"id"`
	RootTenantID   int64      `json:"root_tenant_id"`
	OrganizationID int64      `json:"organization_id"`
	UserID         int64      `json:"user_id"`
	Status         string     `json:"status"`
	Version        int64      `json:"version"`
	ExpiresAt      *time.Time `json:"expires_at,omitempty"`
}

type MembershipRoleAssignment struct {
	ID             int64  `json:"id"`
	RootTenantID   int64  `json:"root_tenant_id"`
	OrganizationID int64  `json:"organization_id"`
	MembershipID   int64  `json:"membership_id"`
	RoleCode       string `json:"role_code"`
	Status         string `json:"status"`
	Version        int64  `json:"version"`
}
