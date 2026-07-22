package service

import (
	"testing"

	"inv-device-server/internal/model"

	"github.com/stretchr/testify/assert"
)

func TestJSONAdapter_ParseTopic(t *testing.T) {
	adapter := NewJSONAdapter()

	tests := []struct {
		name     string
		payload  []byte
		expected map[string]interface{}
		isNil    bool
	}{
		{"normal object", []byte(`{"voltage":220,"power":3500}`), map[string]interface{}{"voltage": float64(220), "power": float64(3500)}, false},
		{"nested object", []byte(`{"ac":{"voltage":220}}`), map[string]interface{}{"ac": map[string]interface{}{"voltage": float64(220)}}, false},
		{"invalid json", []byte(`not json`), nil, true},
		{"empty payload", []byte{}, nil, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := adapter.ParseTopic("data/ac", tt.payload)
			if tt.isNil {
				assert.Nil(t, got)
			} else {
				assert.Equal(t, tt.expected, got)
			}
		})
	}
}

func TestModbusAdapter_ParseTopic(t *testing.T) {
	fields := map[string]*model.DeviceModelField{
		"voltage": {FieldKey: "voltage", FieldType: "float"},
	}
	adapter := NewModbusAdapter(fields)

	tests := []struct {
		name     string
		payload  []byte
		expected map[string]interface{}
		isNil    bool
	}{
		{
			"numeric values",
			[]byte(`{"voltage":220,"current":10}`),
			map[string]interface{}{"voltage": float64(220), "current": float64(10)},
			false,
		},
		{
			"hex string",
			[]byte(`{"fault":"0x0A"}`),
			map[string]interface{}{"fault": float64(10)},
			false,
		},
		{
			"decimal string",
			[]byte(`{"temp":"25.5"}`),
			map[string]interface{}{"temp": float64(25.5)},
			false,
		},
		{
			"non-numeric string stays string",
			[]byte(`{"state":"normal"}`),
			map[string]interface{}{"state": "normal"},
			false,
		},
		{
			"invalid hex",
			[]byte(`{"fault":"0xZZ"}`),
			map[string]interface{}{"fault": "0xZZ"},
			false,
		},
		{
			"invalid json",
			[]byte(`not json`),
			nil,
			true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := adapter.ParseTopic("data/ac", tt.payload)
			if tt.isNil {
				assert.Nil(t, got)
			} else {
				assert.Equal(t, tt.expected, got)
			}
		})
	}
}

func TestCustomAdapter_ParseTopic(t *testing.T) {
	tests := []struct {
		name     string
		config   string
		payload  []byte
		expected map[string]interface{}
	}{
		{
			"field mapping",
			`{"field_mapping":{"raw_voltage":"voltage","raw_current":"current"}}`,
			[]byte(`{"raw_voltage":220,"raw_current":10,"extra":1}`),
			map[string]interface{}{"voltage": float64(220), "current": float64(10)},
		},
		{
			"empty mapping returns raw",
			`{}`,
			[]byte(`{"voltage":220}`),
			map[string]interface{}{"voltage": float64(220)},
		},
		{
			"no config returns raw",
			"",
			[]byte(`{"voltage":220}`),
			map[string]interface{}{"voltage": float64(220)},
		},
		{
			"mapping with missing keys falls back to raw",
			`{"field_mapping":{"missing":"x"}}`,
			[]byte(`{"voltage":220}`),
			map[string]interface{}{"voltage": float64(220)},
		},
		{
			"invalid json payload",
			`{"field_mapping":{"a":"b"}}`,
			[]byte(`not json`),
			nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			adapter := NewCustomAdapter(tt.config)
			got := adapter.ParseTopic("data/ac", tt.payload)
			assert.Equal(t, tt.expected, got)
		})
	}
}

func TestMatchTopic(t *testing.T) {
	tests := []struct {
		name    string
		pattern string
		topic   string
		want    bool
	}{
		{"exact match", "data/ac", "data/ac", true},
		{"exact mismatch", "data/ac", "data/pv", false},
		{"wildcard single level", "data/*", "data/ac", true},
		{"wildcard matches nested", "data/*", "data/ac/voltage", true},
		{"plus single segment", "data/+", "data/ac", true},
		{"plus wrong segment count", "data/+", "data/ac/voltage", false},
		{"plus in middle", "cs_inv/+/data", "cs_inv/SN001/data", true},
		{"plus in middle mismatch", "cs_inv/+/data", "cs_inv/SN001/ota", false},
		{"empty pattern matches all", "", "anything", true},
		{"star matches all", "*", "anything", true},
		{"mixed plus", "cs_inv/+/data/+", "cs_inv/SN001/data/voltage", true},
		{"mixed plus mismatch", "cs_inv/+/data/+", "cs_inv/SN001/data/voltage/extra", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := matchTopic(tt.pattern, tt.topic)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetAdapterForModel(t *testing.T) {
	tests := []struct {
		name      string
		parseType string
		wantType  string
	}{
		{"modbus", "modbus", "*service.ModbusAdapter"},
		{"custom", "custom", "*service.CustomAdapter"},
		{"json", "json", "*service.JSONAdapter"},
		{"empty", "", "*service.JSONAdapter"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			meta := &model.ModelMetadata{
				Protocols: []*model.DeviceModelProtocol{
					{ParseType: tt.parseType, ParseConfig: `{}`},
				},
			}
			adapter := GetAdapterForModel(meta)
			assert.NotNil(t, adapter)
		})
	}

	// nil 保护
	assert.IsType(t, &JSONAdapter{}, GetAdapterForModel(nil))
	assert.IsType(t, &JSONAdapter{}, GetAdapterForModel(&model.ModelMetadata{}))
}

func TestGetAdapterForTopic(t *testing.T) {
	meta := &model.ModelMetadata{
		Protocols: []*model.DeviceModelProtocol{
			{TopicPattern: "data/ac", ParseType: "modbus"},
			{TopicPattern: "data/pv", ParseType: "custom", ParseConfig: `{}`},
		},
	}

	assert.IsType(t, &ModbusAdapter{}, GetAdapterForTopic(meta, "data/ac"))
	assert.IsType(t, &CustomAdapter{}, GetAdapterForTopic(meta, "data/pv"))
	assert.IsType(t, &JSONAdapter{}, GetAdapterForTopic(meta, "data/other"))
	assert.IsType(t, &JSONAdapter{}, GetAdapterForTopic(nil, "data/ac"))
}
