package handler

import (
	"encoding/json"
	"regexp"
	"strconv"

	"inv-api-server/internal/model"

	"github.com/gin-gonic/gin"
)

// SN 格式正则：大写字母+数字，长度 8-32
var snRegex = regexp.MustCompile(`^[A-Z0-9]{8,32}$`)

func parseID(s string) int64 {
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0
	}
	return id
}

func parseInt(s string) int {
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return v
}

func getQueryInt(c *gin.Context, key string, defaultValue int) int {
	s := c.Query(key)
	if s == "" {
		return defaultValue
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return defaultValue
	}
	return v
}

// getPageSize 统一解析分页大小参数，优先使用 page_size，向后兼容 pageSize。
func getPageSize(c *gin.Context, defaultValue int) int {
	s := c.Query("page_size")
	if s == "" {
		s = c.Query("pageSize") // 向后兼容 camelCase
	}
	if s == "" {
		return defaultValue
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return defaultValue
	}
	return v
}

func getQueryInt64(c *gin.Context, key string, defaultValue int64) int64 {
	s := c.Query(key)
	if s == "" {
		return defaultValue
	}
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return defaultValue
	}
	return v
}

// parsePagination 统一分页参数解析，返回 page 和 pageSize。
// 默认 page=1, pageSize=20，最大 pageSize=100。
func parsePagination(c *gin.Context) (page, pageSize int) {
	page = getQueryInt(c, "page", 1)
	if page < 1 {
		page = 1
	}
	pageSize = getPageSize(c, 20)
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	return
}

// validateSN 校验设备 SN 格式（大写字母+数字，长度 8-32）
func validateSN(sn string) bool {
	return snRegex.MatchString(sn)
}

// enrichDeviceWithRealtime enriches a Device struct with realtime data from Redis.
// This shared helper eliminates duplicated enrichment logic between device list
// and station detail handlers.
func enrichDeviceWithRealtime(device *model.Device, rtData map[string]interface{}) {
	if rtData == nil {
		return
	}

	// 使用 Redis 在线状态修正设备状态：离线时快速标记
	if online, ok := rtData["online"].(bool); ok {
		if !online && device.Status != 0 {
			device.Status = 0
		}
	}

	// 从嵌套的 info 对象读取设备信息
	var info map[string]interface{}
	if v, ok := rtData["info"].(map[string]interface{}); ok {
		info = v
		if innerData, ok := v["data"].(map[string]interface{}); ok {
			info = innerData
		}
	}
	if info != nil {
		if v, ok := info["model"]; ok && v != nil {
			if s, ok := v.(string); ok && s != "" && device.Model == "" {
				device.Model = s
			}
		}
		if v, ok := info["manufacturer"]; ok && v != nil {
			if s, ok := v.(string); ok && s != "" && device.Manufacturer == "" {
				device.Manufacturer = s
			}
		}
		if v, ok := info["firmware_arm"]; ok && v != nil {
			if s, ok := v.(string); ok && s != "" && device.FirmwareArm == "" {
				device.FirmwareArm = s
			}
		}
		if v, ok := info["rated_power"]; ok && v != nil {
			if f, ok := toFloat64(v); ok && f > 0 && device.RatedPower == 0 {
				device.RatedPower = f
			}
		}
	}

	// 从嵌套的 energy 对象读取日发电量
	var energyData map[string]interface{}
	if v, ok := rtData["energy"].(map[string]interface{}); ok {
		energyData = v
		if innerData, ok := v["data"].(map[string]interface{}); ok {
			energyData = innerData
		}
	}
	if energyData != nil {
		if v, ok := energyData["daily_pv"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.DailyEnergy = f
			}
		}
	}

	// 从嵌套的 ac 对象读取当前功率
	var acData map[string]interface{}
	if v, ok := rtData["ac"].(map[string]interface{}); ok {
		acData = v
		if innerData, ok := v["data"].(map[string]interface{}); ok {
			acData = innerData
		}
	}
	if acData != nil {
		if v, ok := acData["power"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.CurrentPower = f
			}
		}
	}

	// 兼容旧的扁平格式
	if device.CurrentPower == 0 {
		if v, ok := rtData["power"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.CurrentPower = f
			}
		} else if v, ok := rtData["ac_power"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.CurrentPower = f
			}
		} else if v, ok := rtData["total_active_power"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.CurrentPower = f
			}
		}
	}

	// 兼容扁平格式的 daily_energy
	if device.DailyEnergy == 0 {
		if v, ok := rtData["daily_energy"]; ok && v != nil {
			if f, ok := toFloat64(v); ok {
				device.DailyEnergy = f
			}
		}
	}
}

// toFloat64 attempts to convert an interface{} to float64.
// Defined here to avoid import cycles when sharing enrichment logic.
func toFloat64(v interface{}) (float64, bool) {
	switch val := v.(type) {
	case float64:
		return val, true
	case float32:
		return float64(val), true
	case int:
		return float64(val), true
	case int64:
		return float64(val), true
	case json.Number:
		f, err := val.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}
