package service

import (
	"encoding/json"
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseRuleEngine_Apply(t *testing.T) {
	engine := NewParseRuleEngine()

	tests := []struct {
		name     string
		rule     string
		value    interface{}
		expected float64
	}{
		{"empty rule returns value", "", 100.0, 100.0},
		{"identity x", "x", 50.0, 50.0},
		{"multiply by 10", "x*10", 23.5, 235.0},
		{"divide by 100", "x/100", 1500.0, 15.0},
		{"add offset", "x+25", 75.0, 100.0},
		{"subtract offset", "x-10", 110.0, 100.0},
		{"combined scale", "x*10+5", 12.0, 125.0},
		{"scale with decimal", "x*0.1", 220.0, 22.0},
		{"int input", "x*2", 10, 20.0},
		{"string numeric input", "x/10", "120", 12.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := engine.Apply(tt.rule, tt.value)
			f, ok := got.(float64)
			require.True(t, ok, "expected float64 result, got %T", got)
			assert.InDelta(t, tt.expected, f, 1e-9)
		})
	}
}

func TestParseRuleEngine_ApplyNonNumeric(t *testing.T) {
	engine := NewParseRuleEngine()

	tests := []struct {
		name     string
		rule     string
		value    interface{}
		expected interface{}
	}{
		{"non-numeric string unchanged", "x*10", "hello", "hello"},
		{"nil value unchanged", "x+1", nil, nil},
		{"bool unchanged", "x*2", true, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := engine.Apply(tt.rule, tt.value)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestParseRuleEngine_Concurrent(t *testing.T) {
	engine := NewParseRuleEngine()

	// 并发安全测试：多个 goroutine 同时应用不同规则
	for i := 0; i < 100; i++ {
		t.Run("concurrent", func(t *testing.T) {
			t.Parallel()
			got := engine.Apply("x*2+1", 10.0)
			assert.InDelta(t, 21.0, got.(float64), 1e-9)
		})
	}
}

func TestToFloat64(t *testing.T) {
	tests := []struct {
		name     string
		value    interface{}
		expected float64
		isNaN    bool
	}{
		{"float64", 3.14, 3.14, false},
		{"float32", float32(2.5), 2.5, false},
		{"int", 42, 42.0, false},
		{"int32", int32(100), 100.0, false},
		{"int64", int64(999), 999.0, false},
		{"uint32", uint32(50), 50.0, false},
		{"uint64", uint64(123), 123.0, false},
		{"string number", "77.5", 77.5, false},
		{"json number", json.Number("55.5"), 55.5, false},
		{"invalid string", "abc", 0, true},
		{"bool", true, 0, true},
		{"nil", nil, 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := toFloat64(tt.value)
			if tt.isNaN {
				assert.True(t, math.IsNaN(got))
			} else {
				assert.InDelta(t, tt.expected, got, 1e-9)
			}
		})
	}
}

func TestCastByFieldType(t *testing.T) {
	tests := []struct {
		name     string
		fieldType string
		value    interface{}
		expected interface{}
	}{
		{"int from float", "int", 12.7, 12},
		{"int from string", "int", "33", 33},
		{"float", "float", 12, 12.0},
		{"bool true", "bool", 1.0, true},
		{"bool false", "bool", 0.0, false},
		{"string", "string", 123, "123"},
		{"unknown returns value", "unknown", "x", "x"},
		{"empty type returns value", "", "x", "x"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CastByFieldType(tt.fieldType, tt.value)
			assert.Equal(t, tt.expected, got)
		})
	}
}
