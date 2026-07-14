package handler

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestApplicationVersionUsesEnvironment(t *testing.T) {
	t.Setenv("APP_VERSION", "test-1.2.3")
	assert.Equal(t, "test-1.2.3", applicationVersion())
}

func TestValidTenantLimit(t *testing.T) {
	negative, zero, maximum, excessive := -1, 0, 100000, 100001
	assert.True(t, validTenantLimit(nil))
	assert.False(t, validTenantLimit(&negative))
	assert.True(t, validTenantLimit(&zero))
	assert.True(t, validTenantLimit(&maximum))
	assert.False(t, validTenantLimit(&excessive))
}
