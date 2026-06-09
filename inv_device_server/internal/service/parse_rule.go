package service

import (
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"
)

type ParseRuleEngine struct{}

func NewParseRuleEngine() *ParseRuleEngine {
	return &ParseRuleEngine{}
}

func (e *ParseRuleEngine) Apply(rule string, value interface{}) interface{} {
	if rule == "" {
		return value
	}

	fv := toFloat64(value)
	if math.IsNaN(fv) {
		return value
	}

	result := e.evalRule(rule, fv)
	return result
}

func (e *ParseRuleEngine) evalRule(rule string, x float64) float64 {
	rule = strings.TrimSpace(rule)

	if strings.HasPrefix(rule, "x") {
		rule = rule[1:]
		if rule == "" {
			return x
		}
	}

	var result float64
	var op byte = '+'
	result = x

	i := 0
	for i < len(rule) {
		ch := rule[i]
		if ch == '+' || ch == '-' || ch == '*' || ch == '/' {
			op = ch
			i++
			continue
		}

		j := i
		for j < len(rule) && rule[j] != '+' && rule[j] != '-' && rule[j] != '*' && rule[j] != '/' {
			j++
		}
		numStr := strings.TrimSpace(rule[i:j])
		if numStr == "" {
			i = j
			continue
		}
		num, err := strconv.ParseFloat(numStr, 64)
		if err != nil {
			i = j
			continue
		}

		switch op {
		case '+':
			result = result + num
		case '-':
			result = result - num
		case '*':
			result = result * num
		case '/':
			if num != 0 {
				result = result / num
			}
		}
		i = j
	}

	return result
}

func toFloat64(v interface{}) float64 {
	switch val := v.(type) {
	case float64:
		return val
	case float32:
		return float64(val)
	case int:
		return float64(val)
	case int32:
		return float64(val)
	case int64:
		return float64(val)
	case uint32:
		return float64(val)
	case uint64:
		return float64(val)
	case string:
		f, err := strconv.ParseFloat(val, 64)
		if err != nil {
			return math.NaN()
		}
		return f
	case json.Number:
		f, _ := val.Float64()
		return f
	default:
		return math.NaN()
	}
}

func CastByFieldType(fieldType string, value interface{}) interface{} {
	switch fieldType {
	case "int":
		return int(toFloat64(value))
	case "float":
		return toFloat64(value)
	case "bool":
		fv := toFloat64(value)
		return fv != 0
	case "string":
		return fmt.Sprintf("%v", value)
	default:
		return value
	}
}
