package handler

import (
	"strings"
	"testing"

	"inv-api-server/internal/service"
)

func TestNotificationDataScopeByRole(t *testing.T) {
	if got := notificationDataScope("n", service.RoleSuperAdmin, 1); got != "1=1" {
		t.Fatalf("super administrator scope = %q", got)
	}
	for _, role := range []int{service.RoleGeneralAgent, service.RoleAgent, service.RoleDealer, service.RoleInstaller, service.RoleEndUser} {
		got := notificationDataScope("n", role, 3)
		if !strings.Contains(got, "n.user_id = $3") || !strings.Contains(got, "v_user_device_access") {
			t.Fatalf("role %d notification scope is incomplete: %s", role, got)
		}
	}
}

func TestNotificationMutationScopeNeverUsesSharedDeviceAccess(t *testing.T) {
	if got := notificationMutationScope("n", service.RoleSuperAdmin, 1); got != "1=1" {
		t.Fatalf("super administrator mutation scope = %q", got)
	}
	for _, role := range []int{service.RoleGeneralAgent, service.RoleAgent, service.RoleDealer, service.RoleInstaller, service.RoleEndUser} {
		got := notificationMutationScope("n", role, 3)
		if got != "n.user_id = $3" {
			t.Fatalf("role %d must only mutate its own notifications, got %s", role, got)
		}
		if strings.Contains(got, "v_user_device_access") {
			t.Fatalf("role %d mutation scope must not inherit shared device visibility", role)
		}
	}
}

func TestAlertRuleDataScopeSeparatesBranches(t *testing.T) {
	for _, role := range []int{service.RoleGeneralAgent, service.RoleAgent, service.RoleDealer} {
		got := alertRuleDataScope("r", role, 2)
		if !strings.Contains(got, "v_user_hierarchy") || !strings.Contains(got, "ancestor_id = $2") {
			t.Fatalf("role %d must be restricted to descendants: %s", role, got)
		}
	}
	for _, role := range []int{service.RoleInstaller, service.RoleEndUser} {
		if got := alertRuleDataScope("r", role, 2); got != "r.created_by = $2" {
			t.Fatalf("role %d must only see own rules: %s", role, got)
		}
	}
}

func TestValidateAlertRuleValues(t *testing.T) {
	conditions := []map[string]interface{}{{"field": "temperature", "operator": ">", "value": 80}}
	if err := validateAlertRuleValues("high temperature", 3, conditions, nil, nil); err != nil {
		t.Fatalf("valid rule rejected: %v", err)
	}
	device := "INV00001"
	station := int64(1)
	if err := validateAlertRuleValues("conflicting scope", 2, conditions, &device, &station); err == nil {
		t.Fatal("rule targeting both a device and station must be rejected")
	}
	if err := validateAlertRuleValues("bad level", 4, conditions, nil, nil); err == nil {
		t.Fatal("invalid alert level must be rejected")
	}
}
