package repository

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

type commandParameterSchema struct {
	Args  []commandArgumentSpec `json:"args"`
	Rules []string              `json:"rules"`
}

type commandArgumentSpec struct {
	Key      string        `json:"key"`
	Type     string        `json:"type"`
	Required *bool         `json:"required,omitempty"`
	Min      *float64      `json:"min,omitempty"`
	Max      *float64      `json:"max,omitempty"`
	Enum     []interface{} `json:"enum,omitempty"`
}

func validateAndBuildCommandArgs(raw []byte, params map[string]interface{}) ([]interface{}, error) {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var schema commandParameterSchema
	if err := decoder.Decode(&schema); err != nil {
		return nil, fmt.Errorf("invalid parameter schema: %w", err)
	}

	known := make(map[string]struct{}, len(schema.Args))
	args := make([]interface{}, 0, len(schema.Args))
	for _, spec := range schema.Args {
		if spec.Key == "" {
			return nil, fmt.Errorf("parameter schema contains an empty key")
		}
		known[spec.Key] = struct{}{}
		value, exists := params[spec.Key]
		required := spec.Required == nil || *spec.Required
		if !exists {
			if required {
				return nil, fmt.Errorf("missing command argument: %s", spec.Key)
			}
			args = append(args, nil)
			continue
		}
		if err := validateCommandArgument(spec, value); err != nil {
			return nil, err
		}
		args = append(args, value)
	}
	for key := range params {
		if _, ok := known[key]; !ok {
			return nil, fmt.Errorf("unknown command argument: %s", key)
		}
	}
	for _, rule := range schema.Rules {
		if err := validateCommandRule(rule, params); err != nil {
			return nil, err
		}
	}
	return args, nil
}

func validateCommandArgument(spec commandArgumentSpec, value interface{}) error {
	switch strings.ToLower(spec.Type) {
	case "", "any":
	case "integer", "int":
		number, ok := commandNumber(value)
		if !ok || math.Trunc(number) != number {
			return fmt.Errorf("command argument %s must be an integer", spec.Key)
		}
	case "number", "float", "double":
		if _, ok := commandNumber(value); !ok {
			return fmt.Errorf("command argument %s must be a number", spec.Key)
		}
	case "boolean", "bool":
		if _, ok := value.(bool); !ok {
			return fmt.Errorf("command argument %s must be a boolean", spec.Key)
		}
	case "string":
		if _, ok := value.(string); !ok {
			return fmt.Errorf("command argument %s must be a string", spec.Key)
		}
	default:
		return fmt.Errorf("command argument %s has unsupported schema type %s", spec.Key, spec.Type)
	}

	if spec.Min != nil || spec.Max != nil {
		number, ok := commandNumber(value)
		if !ok {
			return fmt.Errorf("command argument %s must be numeric for range validation", spec.Key)
		}
		if spec.Min != nil && number < *spec.Min {
			return fmt.Errorf("command argument %s is below minimum %v", spec.Key, *spec.Min)
		}
		if spec.Max != nil && number > *spec.Max {
			return fmt.Errorf("command argument %s exceeds maximum %v", spec.Key, *spec.Max)
		}
	}
	if len(spec.Enum) > 0 {
		matched := false
		for _, allowed := range spec.Enum {
			if commandValuesEqual(value, allowed) {
				matched = true
				break
			}
		}
		if !matched {
			return fmt.Errorf("command argument %s is not an allowed value", spec.Key)
		}
	}
	return nil
}

func commandNumber(value interface{}) (float64, bool) {
	switch v := value.(type) {
	case json.Number:
		n, err := v.Float64()
		return n, err == nil
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case int:
		return float64(v), true
	case int32:
		return float64(v), true
	case int64:
		return float64(v), true
	case uint:
		return float64(v), true
	case uint32:
		return float64(v), true
	case uint64:
		return float64(v), true
	default:
		return 0, false
	}
}

func commandValuesEqual(left, right interface{}) bool {
	if l, ok := commandNumber(left); ok {
		if r, ok := commandNumber(right); ok {
			return l == r
		}
	}
	return fmt.Sprint(left) == fmt.Sprint(right)
}

var commandRulePattern = regexp.MustCompile(`^([a-zA-Z][a-zA-Z0-9_]*)(?:-([a-zA-Z][a-zA-Z0-9_]*))?\s*(<=|>=|<|>|==|!=)\s*([a-zA-Z][a-zA-Z0-9_]*|-?[0-9]+(?:\.[0-9]+)?)$`)

func validateCommandRule(rule string, params map[string]interface{}) error {
	normalized := strings.ReplaceAll(strings.TrimSpace(rule), " ", "")
	parts := commandRulePattern.FindStringSubmatch(normalized)
	if parts == nil {
		return fmt.Errorf("unsupported command validation rule: %s", rule)
	}
	left, ok := commandNumericOperand(parts[1], params)
	if !ok {
		return fmt.Errorf("rule %s references a missing or non-numeric argument", rule)
	}
	if parts[2] != "" {
		rightPart, valid := commandNumericOperand(parts[2], params)
		if !valid {
			return fmt.Errorf("rule %s references a missing or non-numeric argument", rule)
		}
		left -= rightPart
	}
	right, ok := commandNumericOperand(parts[4], params)
	if !ok {
		return fmt.Errorf("rule %s has an invalid right operand", rule)
	}
	valid := false
	switch parts[3] {
	case "<":
		valid = left < right
	case "<=":
		valid = left <= right
	case ">":
		valid = left > right
	case ">=":
		valid = left >= right
	case "==":
		valid = left == right
	case "!=":
		valid = left != right
	}
	if !valid {
		return fmt.Errorf("command validation rule failed: %s", rule)
	}
	return nil
}

func commandNumericOperand(operand string, params map[string]interface{}) (float64, bool) {
	if value, ok := params[operand]; ok {
		return commandNumber(value)
	}
	number, err := strconv.ParseFloat(operand, 64)
	return number, err == nil
}
