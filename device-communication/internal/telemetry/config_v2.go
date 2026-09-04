package telemetry

import (
	"encoding/json"
	"fmt"
	"time"
)

// ParseReportedConfigV2 解析 V2.1 config 语义键值对（见 docs/CS-L10-6K2_MQTT_上报协议设计_V2.1.md 9.1）：
//
//	{"v":2,"t":<unix>,"data":{"rev":<CtrlParamAlterTime>,"params":{"<command_code>":<工程单位数值>,...}}}
//
// params 为 42 键语义键值对（键名与 device_model_commands.command_code 同源），
// 值为工程单位（浮点或整数）；未读取到/不可用的参数键可省略。
// 纯解析层不涉及 schema 校验（schema 校验在 repository/service 层，见 SaveReportedConfigV2）。
func ParseReportedConfigV2(payload []byte) (*ReportedConfig, error) {
	var raw struct {
		Version uint16 `json:"v"`
		Time    int64  `json:"t"`
		Data    struct {
			Revision uint64                     `json:"rev"`
			Params   map[string]json.RawMessage `json:"params"`
		} `json:"data"`
	}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidHeartbeat, err)
	}
	if raw.Version != 2 {
		return nil, fmt.Errorf("%w: config version %d", ErrUnsupportedVersion, raw.Version)
	}
	if raw.Time <= 0 {
		return nil, fmt.Errorf("%w: config timestamp is required", ErrInvalidHeartbeat)
	}
	if raw.Data.Revision <= 0 {
		return nil, fmt.Errorf("%w: config rev (CtrlParamAlterTime) is required", ErrInvalidHeartbeat)
	}
	values := make(map[string]any, len(raw.Data.Params))
	for key, rawValue := range raw.Data.Params {
		var num float64
		if err := json.Unmarshal(rawValue, &num); err != nil {
			return nil, fmt.Errorf("%w: param %s must be numeric", ErrInvalidHeartbeat, key)
		}
		values[key] = num
	}
	return &ReportedConfig{
		ProtocolVersion: 2,
		EventTime:       time.Unix(raw.Time, 0).UTC(),
		Revision:        raw.Data.Revision,
		Values:          values,
	}, nil
}
