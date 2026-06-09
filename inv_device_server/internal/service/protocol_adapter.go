package service

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"inv-device-server/internal/model"
	"inv-device-server/pkg/logger"

	"go.uber.org/zap"
)

type ProtocolAdapter interface {
	ParseTopic(topic string, payload []byte) map[string]interface{}
}

type JSONAdapter struct{}

func NewJSONAdapter() *JSONAdapter {
	return &JSONAdapter{}
}

func (a *JSONAdapter) ParseTopic(topic string, payload []byte) map[string]interface{} {
	var result map[string]interface{}
	if err := json.Unmarshal(payload, &result); err != nil {
		logger.Warn("JSONAdapter: failed to parse payload",
			zap.String("topic", topic), zap.Error(err))
		return nil
	}
	return result
}

type ModbusAdapter struct {
	fields map[string]*model.DeviceModelField
}

func NewModbusAdapter(fields map[string]*model.DeviceModelField) *ModbusAdapter {
	return &ModbusAdapter{fields: fields}
}

func (a *ModbusAdapter) ParseTopic(topic string, payload []byte) map[string]interface{} {
	var raw map[string]interface{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		logger.Warn("ModbusAdapter: failed to parse payload",
			zap.String("topic", topic), zap.Error(err))
		return nil
	}

	result := make(map[string]interface{})
	for key, val := range raw {
		switch v := val.(type) {
		case float64:
			result[key] = v
		case string:
			if f, err := strconv.ParseFloat(v, 64); err == nil {
				result[key] = f
			} else if strings.HasPrefix(v, "0x") || strings.HasPrefix(v, "0X") {
				if h, err := strconv.ParseInt(v[2:], 16, 64); err == nil {
					result[key] = float64(h)
				} else {
					result[key] = v
				}
			} else {
				result[key] = v
			}
		default:
			result[key] = v
		}
	}
	return result
}

type CustomAdapter struct {
	parseConfig map[string]interface{}
}

func NewCustomAdapter(configJSON string) *CustomAdapter {
	cfg := make(map[string]interface{})
	if configJSON != "" {
		json.Unmarshal([]byte(configJSON), &cfg)
	}
	return &CustomAdapter{parseConfig: cfg}
}

func (a *CustomAdapter) ParseTopic(topic string, payload []byte) map[string]interface{} {
	var raw map[string]interface{}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil
	}

	if mapping, ok := a.parseConfig["field_mapping"].(map[string]interface{}); ok {
		result := make(map[string]interface{})
		for srcKey, dstKey := range mapping {
			if dstStr, ok := dstKey.(string); ok {
				if val, exists := raw[srcKey]; exists {
					result[dstStr] = val
				}
			}
		}
		if len(result) > 0 {
			return result
		}
	}

	return raw
}

func GetAdapterForModel(meta *model.ModelMetadata) ProtocolAdapter {
	if meta == nil || len(meta.Protocols) == 0 {
		return NewJSONAdapter()
	}

	proto := meta.Protocols[0]
	switch proto.ParseType {
	case "modbus":
		return NewModbusAdapter(meta.Fields)
	case "custom":
		return NewCustomAdapter(proto.ParseConfig)
	default:
		return NewJSONAdapter()
	}
}

func GetAdapterForTopic(meta *model.ModelMetadata, topic string) ProtocolAdapter {
	if meta == nil || len(meta.Protocols) == 0 {
		return NewJSONAdapter()
	}

	for _, proto := range meta.Protocols {
		if matchTopic(proto.TopicPattern, topic) {
			switch proto.ParseType {
			case "modbus":
				return NewModbusAdapter(meta.Fields)
			case "custom":
				return NewCustomAdapter(proto.ParseConfig)
			default:
				return NewJSONAdapter()
			}
		}
	}

	return NewJSONAdapter()
}

func matchTopic(pattern, topic string) bool {
	if pattern == "" || pattern == "*" {
		return true
	}

	if pattern == topic {
		return true
	}

	if strings.HasSuffix(pattern, "/*") {
		prefix := strings.TrimSuffix(pattern, "/*")
		return strings.HasPrefix(topic, prefix)
	}

	if strings.HasSuffix(pattern, "/+") {
		prefix := strings.TrimSuffix(pattern, "/+")
		if !strings.HasPrefix(topic, prefix) {
			return false
		}
		rest := topic[len(prefix):]
		return !strings.Contains(rest[1:], "/")
	}

	if strings.Contains(pattern, "+") {
		pParts := strings.Split(pattern, "/")
		tParts := strings.Split(topic, "/")
		if len(pParts) != len(tParts) {
			return false
		}
		for i, pp := range pParts {
			if pp == "+" || pp == "#" {
				continue
			}
			if pp != tParts[i] {
				return false
			}
		}
		return true
	}

	_ = fmt.Sprintf("pattern=%s topic=%s", pattern, topic)
	return false
}
