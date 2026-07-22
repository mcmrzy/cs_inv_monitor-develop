package handler

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNormalizeAlertRuleUsesJSONArrayDefaults(t *testing.T) {
	disabled := false
	req := alertRuleRequest{Enabled: &disabled}
	normalizeAlertRule(&req)

	conditions, err := json.Marshal(req.Conditions)
	require.NoError(t, err)
	assert.JSONEq(t, `[]`, string(conditions))
	assert.Equal(t, []string{"app"}, req.NotificationChannels)
	assert.False(t, *req.Enabled)
}
