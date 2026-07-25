package handler

import (
	"strings"
	"testing"
)

func TestNotificationDataScopeByRole(t *testing.T) {
	if got := notificationDataScope("n", true, 1); got != "1=1" {
		t.Fatalf("super administrator scope = %q", got)
	}
	got := notificationDataScope("n", false, 3)
	if !strings.Contains(got, "n.user_id = $3") || !strings.Contains(got, "v_user_device_access") {
		t.Fatalf("non-admin notification scope is incomplete: %s", got)
	}
}

func TestNotificationMutationScopeNeverUsesSharedDeviceAccess(t *testing.T) {
	if got := notificationMutationScope("n", true, 1); got != "1=1" {
		t.Fatalf("super administrator mutation scope = %q", got)
	}
	got := notificationMutationScope("n", false, 3)
	if got != "n.user_id = $3" {
		t.Fatalf("non-admin must only mutate its own notifications, got %s", got)
	}
	if strings.Contains(got, "v_user_device_access") {
		t.Fatalf("non-admin mutation scope must not inherit shared device visibility")
	}
}

func TestAlertRuleDataScopeSeparatesBranches(t *testing.T) {
	for _, role := range []int{1, 2, 3} {
		got := alertRuleDataScope("r", role, 2)
		if !strings.Contains(got, "v_user_hierarchy") || !strings.Contains(got, "ancestor_id = $2") {
			t.Fatalf("role %d must be restricted to descendants: %s", role, got)
		}
	}
	for _, role := range []int{4, 5} {
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
