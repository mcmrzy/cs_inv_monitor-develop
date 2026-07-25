package service

// Legacy role constants — retained for backward compatibility with data-scope
// SQL helpers (workOrderDataScope, alertRuleDataScope) that still use integer
// roles.  These will be removed in Phase 8 after all data-scope functions are
// migrated to permission_code + data_scope.
const (
	RoleSuperAdmin   = 0
	RoleGeneralAgent = 1
	RoleAgent        = 2
	RoleDealer       = 3
	RoleInstaller    = 4
	RoleEndUser      = 5
)

// Deprecated: Use is_system_admin + permission_code checks instead.
func IsValidRole(role int) bool {
	return role >= RoleSuperAdmin && role <= RoleEndUser
}

// Deprecated: Use organization-based hierarchy checks instead.
func CanManageRole(actorRole, targetRole int) bool {
	return IsValidRole(actorRole) && IsValidRole(targetRole) && actorRole < targetRole
}

// Deprecated: Use organization-based hierarchy checks instead.
func CanAssignRole(actorRole, newRole int) bool {
	return CanManageRole(actorRole, newRole)
}

// Deprecated: Use organization-based hierarchy checks instead.
func CanBeParent(parentRole, childRole int) bool {
	return CanManageRole(parentRole, childRole)
}

// Deprecated: Use organization-based hierarchy checks instead.
// CanCreateManagedUser validates both authority and ownership placement.
func CanCreateManagedUser(actorRole, childRole, parentRole int, parentActive, parentInScope bool) bool {
	if !parentActive || !CanAssignRole(actorRole, childRole) || !CanBeParent(parentRole, childRole) {
		return false
	}
	return actorRole == RoleSuperAdmin || parentInScope
}

// Deprecated: Use authorization_repository.ResourceCoveredByGrant() instead.
// CanAccessDeviceByBusinessScope is the executable specification mirrored by
// v_user_device_access. It is intentionally pure so the cross-role matrix can be regression tested.
func CanAccessDeviceByBusinessScope(
	actorRole int,
	ownerSelf, ownerInTree, installerInTree, installerAssignedSelf, explicitInTree, explicitSelf bool,
) bool {
	switch {
	case actorRole == RoleSuperAdmin:
		return true
	case actorRole >= RoleGeneralAgent && actorRole <= RoleDealer:
		return ownerInTree || installerInTree || explicitInTree
	case actorRole == RoleInstaller:
		return ownerSelf || installerAssignedSelf || explicitSelf
	case actorRole == RoleEndUser:
		return ownerSelf
	default:
		return false
	}
}
