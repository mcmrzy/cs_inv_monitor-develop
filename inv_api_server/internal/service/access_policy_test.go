package service

import "testing"

func TestRoleHierarchyBusinessMatrix(t *testing.T) {
	tests := []struct {
		name       string
		actorRole  int
		targetRole int
		want       bool
	}{
		{"超级管理员管理总代理", RoleSuperAdmin, RoleGeneralAgent, true},
		{"总代理管理经销商", RoleGeneralAgent, RoleDealer, true},
		{"经销商管理安装商", RoleDealer, RoleInstaller, true},
		{"安装商管理终端用户", RoleInstaller, RoleEndUser, true},
		{"同级代理商不能互管", RoleAgent, RoleAgent, false},
		{"安装商不能管理经销商", RoleInstaller, RoleDealer, false},
		{"终端用户不能管理下级", RoleEndUser, RoleEndUser, false},
		{"非法角色默认拒绝", -1, RoleEndUser, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := CanManageRole(tt.actorRole, tt.targetRole); got != tt.want {
				t.Fatalf("CanManageRole(%d, %d) = %v, want %v", tt.actorRole, tt.targetRole, got, tt.want)
			}
		})
	}
}

func TestCanBeParentRejectsInvalidDirection(t *testing.T) {
	if CanBeParent(RoleInstaller, RoleDealer) {
		t.Fatal("lower privilege user must not become parent of a higher privilege user")
	}
	if CanBeParent(RoleDealer, RoleDealer) {
		t.Fatal("same-level parent relationship must be rejected")
	}
}

func TestManagedUserCreationBusinessMatrix(t *testing.T) {
	tests := []struct {
		name          string
		actorRole     int
		childRole     int
		parentRole    int
		parentActive  bool
		parentInScope bool
		want          bool
	}{
		{"general agent creates agent below self", RoleGeneralAgent, RoleAgent, RoleGeneralAgent, true, true, true},
		{"agent creates installer below scoped dealer", RoleAgent, RoleInstaller, RoleDealer, true, true, true},
		{"installer creates end user", RoleInstaller, RoleEndUser, RoleInstaller, true, true, true},
		{"same level creation rejected", RoleAgent, RoleAgent, RoleAgent, true, true, false},
		{"upward creation rejected", RoleDealer, RoleAgent, RoleDealer, true, true, false},
		{"sibling branch parent rejected", RoleAgent, RoleEndUser, RoleInstaller, true, false, false},
		{"disabled parent rejected", RoleAgent, RoleEndUser, RoleInstaller, false, true, false},
		{"super administrator may use any valid parent", RoleSuperAdmin, RoleEndUser, RoleInstaller, true, false, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CanCreateManagedUser(tt.actorRole, tt.childRole, tt.parentRole, tt.parentActive, tt.parentInScope)
			if got != tt.want {
				t.Fatalf("CanCreateManagedUser() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestDeviceVisibilityBusinessMatrix(t *testing.T) {
	tests := []struct {
		name                                                                                 string
		role                                                                                 int
		ownerSelf, ownerInTree, installerInTree, installerSelf, explicitInTree, explicitSelf bool
		want                                                                                 bool
	}{
		{"agent sees descendant owner", RoleAgent, false, true, false, false, false, false, true},
		{"agent cannot see sibling branch", RoleAgent, false, false, false, false, false, false, false},
		{"dealer sees descendant installer assignment", RoleDealer, false, false, true, false, false, false, true},
		{"installer sees assigned device", RoleInstaller, false, false, false, true, false, false, true},
		{"installer sees self-owned device", RoleInstaller, true, false, false, false, false, false, true},
		{"installer sees explicitly authorized device", RoleInstaller, false, false, false, false, false, true, true},
		{"installer does not inherit end-user devices", RoleInstaller, false, true, false, false, false, false, false},
		{"end user sees own device", RoleEndUser, true, true, false, false, false, false, true},
		{"end user cannot use explicit share", RoleEndUser, false, false, false, false, false, true, false},
		{"super administrator sees all", RoleSuperAdmin, false, false, false, false, false, false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CanAccessDeviceByBusinessScope(tt.role, tt.ownerSelf, tt.ownerInTree,
				tt.installerInTree, tt.installerSelf, tt.explicitInTree, tt.explicitSelf)
			if got != tt.want {
				t.Fatalf("CanAccessDeviceByBusinessScope() = %v, want %v", got, tt.want)
			}
		})
	}
}
