package repository

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidateAndBuildCommandArgs(t *testing.T) {
	raw := []byte(`{"args":[{"key":"watts","type":"integer","min":0,"max":6200}]}`)
	args, err := validateAndBuildCommandArgs(raw, map[string]interface{}{"watts": float64(3200)})
	require.NoError(t, err)
	assert.Equal(t, []interface{}{float64(3200)}, args)
}

func TestValidateAndBuildCommandArgsRejectsTypeRangeEnumAndUnknown(t *testing.T) {
	rangeSchema := []byte(`{"args":[{"key":"watts","type":"integer","min":0,"max":6200}]}`)
	_, err := validateAndBuildCommandArgs(rangeSchema, map[string]interface{}{"watts": 6201})
	assert.ErrorContains(t, err, "maximum")
	_, err = validateAndBuildCommandArgs(rangeSchema, map[string]interface{}{"watts": 1.5})
	assert.ErrorContains(t, err, "integer")
	_, err = validateAndBuildCommandArgs(rangeSchema, map[string]interface{}{"watts": 10, "extra": true})
	assert.ErrorContains(t, err, "unknown")

	enumSchema := []byte(`{"args":[{"key":"phase","type":"integer","enum":[1,2,3]}]}`)
	_, err = validateAndBuildCommandArgs(enumSchema, map[string]interface{}{"phase": 4})
	assert.ErrorContains(t, err, "allowed")
}

func TestValidateAndBuildCommandArgsRules(t *testing.T) {
	raw := []byte(`{"args":[{"key":"low_x10","type":"integer"},{"key":"high_x10","type":"integer"}],"rules":["low_x10 < high_x10","high_x10-low_x10 >= 50"]}`)
	_, err := validateAndBuildCommandArgs(raw, map[string]interface{}{"low_x10": 300, "high_x10": 800})
	require.NoError(t, err)
	_, err = validateAndBuildCommandArgs(raw, map[string]interface{}{"low_x10": 780, "high_x10": 800})
	assert.ErrorContains(t, err, "rule failed")
}
