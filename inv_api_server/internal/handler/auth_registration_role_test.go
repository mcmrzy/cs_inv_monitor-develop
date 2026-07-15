package handler

import "testing"

func TestDefaultSelfRegisteredRoleIsTerminalUser(t *testing.T) {
	if defaultSelfRegisteredRole != 5 {
		t.Fatalf("self-registered users must use terminal role 5, got %d", defaultSelfRegisteredRole)
	}
}
