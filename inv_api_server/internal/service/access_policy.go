package service

const (
	RoleSuperAdmin   = 0
	RoleGeneralAgent = 1
	RoleAgent        = 2
	RoleDealer       = 3
	RoleInstaller    = 4
	RoleEndUser      = 5
)

func IsValidRole(role int) bool {
	return role >= RoleSuperAdmin && role <= RoleEndUser
}

// CanManageRole 只允许上级角色管理权限更低的角色，禁止同级互管和向上越权。
func CanManageRole(actorRole, targetRole int) bool {
	return IsValidRole(actorRole) && IsValidRole(targetRole) && actorRole < targetRole
}

func CanAssignRole(actorRole, newRole int) bool {
	return CanManageRole(actorRole, newRole)
}

func CanBeParent(parentRole, childRole int) bool {
	return CanManageRole(parentRole, childRole)
}

// CanCreateManagedUser validates both authority and ownership placement.
// parentInScope must include the actor themselves and is ignored only for super administrators.
func CanCreateManagedUser(actorRole, childRole, parentRole int, parentActive, parentInScope bool) bool {
	if !parentActive || !CanAssignRole(actorRole, childRole) || !CanBeParent(parentRole, childRole) {
		return false
	}
	return actorRole == RoleSuperAdmin || parentInScope
}

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
