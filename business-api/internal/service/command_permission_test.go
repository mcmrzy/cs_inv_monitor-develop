package service

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSplitCommandPermissionCode(t *testing.T) {
	tests := []struct {
		name, code, resource, action string
		valid                        bool
	}{
		{"canonical", "devices:control", "devices", "control", true},
		{"legacy underscore", "device_control_basic", "device_control", "basic", true},
		{"missing separator", "devicescontrol", "", "", false},
		{"empty action", "devices:", "", "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resource, action, ok := splitCommandPermissionCode(tt.code)
			assert.Equal(t, tt.valid, ok)
			assert.Equal(t, tt.resource, resource)
			assert.Equal(t, tt.action, action)
		})
	}
}
