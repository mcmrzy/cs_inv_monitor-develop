package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/internal/repository"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// DynamicLimitChecker 动态限值校验引擎
// 计算 BMS CCL/DCL、温度降额等因素下的有效充放电电流上限
type DynamicLimitChecker struct {
	cache *redis.Client
	db    *pgxpool.Pool
}

func NewDynamicLimitChecker(cache *redis.Client, db *pgxpool.Pool) *DynamicLimitChecker {
	return &DynamicLimitChecker{cache: cache, db: db}
}

// realtimeData 从 Redis realtime:latest:{sn} 和 realtime:last_valid:{sn} 中读取展平的实时数据
func (c *DynamicLimitChecker) realtimeData(ctx context.Context, sn string) map[string]interface{} {
	if c.cache == nil {
		return nil
	}
	result := make(map[string]interface{})

	// 优先读取有效数据缓存
	for _, key := range []string{"realtime:last_valid:" + sn, "realtime:latest:" + sn} {
		cached, err := c.cache.Get(ctx, key).Result()
		if err != nil || cached == "" {
			continue
		}
		var m map[string]interface{}
		if json.Unmarshal([]byte(cached), &m) != nil {
			continue
		}
		for k, v := range m {
			// 跳过元数据字段
			if k == "_sn" || k == "_updated_at" || k == "_timestamp" || k == "_msg_type" {
				continue
			}
			// 展平嵌套格式 {"data": {...}, "timestamp": ...}
			if nested, ok := v.(map[string]interface{}); ok {
				if innerData, exists := nested["data"].(map[string]interface{}); exists {
					for dk, dv := range innerData {
						if _, present := result[dk]; !present {
							result[dk] = dv
						}
					}
				} else {
					for dk, dv := range nested {
						if _, present := result[dk]; !present {
							result[dk] = dv
						}
					}
				}
			} else {
				if _, present := result[k]; !present {
					result[k] = v
				}
			}
		}
	}

	// 补充字段级缓存
	hashKey := "realtime:fields:" + sn
	fields, err := c.cache.HGetAll(ctx, hashKey).Result()
	if err == nil {
		for fieldName, valStr := range fields {
			var fieldData map[string]interface{}
			if json.Unmarshal([]byte(valStr), &fieldData) == nil {
				if v, exists := fieldData["v"]; exists {
					if _, present := result[fieldName]; !present {
						result[fieldName] = v
					}
				}
			}
		}
	}

	return result
}

// dbRealtimeField 从 device_latest_state 表读取单个字段值（作为 Redis 不可用时的降级路径）
func (c *DynamicLimitChecker) dbRealtimeField(ctx context.Context, sn, column string) (interface{}, error) {
	// 使用 to_jsonb 动态提取，避免硬编码每列
	var raw []byte
	err := c.db.QueryRow(ctx,
		fmt.Sprintf(`SELECT to_jsonb(s)->>'%s' FROM device_latest_state s WHERE device_sn=$1`, column),
		sn).Scan(&raw)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if raw == nil {
		return nil, nil
	}
	return string(raw), nil
}

// getFloatField 从实时数据 map 中提取 float64 字段，支持多种类型
func getFloatField(data map[string]interface{}, keys ...string) (float64, bool) {
	for _, key := range keys {
		if v, ok := data[key]; ok && v != nil {
			switch n := v.(type) {
			case float64:
				return n, true
			case int64:
				return float64(n), true
			case int:
				return float64(n), true
			case json.Number:
				if f, err := n.Float64(); err == nil {
					return f, true
				}
			case string:
				// 尝试解析字符串数字
				var f float64
				if _, err := fmt.Sscanf(n, "%f", &f); err == nil {
					return f, true
				}
			}
		}
	}
	return 0, false
}

// getIntField 从实时数据 map 中提取 int64 字段
func getIntField(data map[string]interface{}, keys ...string) (int64, bool) {
	for _, key := range keys {
		if v, ok := data[key]; ok && v != nil {
			switch n := v.(type) {
			case float64:
				return int64(n), true
			case int64:
				return n, true
			case int:
				return int64(n), true
			case json.Number:
				if i, err := n.Int64(); err == nil {
					return i, true
				}
			}
		}
	}
	return 0, false
}

// batteryConfig 从数据库读取设备电池配置和关联的电池模板
type batteryConfigResult struct {
	CapacityAh         int
	ParallelStrings    int16
	ChargeEnvelope     map[string]interface{}
	DischargeEnvelope  map[string]interface{}
	TemperatureDerating map[string]interface{}
	InstallerLimits    map[string]interface{}
}

func (c *DynamicLimitChecker) batteryConfig(ctx context.Context, sn string) (*batteryConfigResult, error) {
	var cfg batteryConfigResult
	var chargeEnv, dischargeEnv, tempDerating, installerLimits []byte
	var profileID int64

	err := c.db.QueryRow(ctx, `
		SELECT bc.profile_id, bc.capacity_ah, bc.parallel_strings,
		       bc.installer_limits,
		       bp.charge_envelope, bp.discharge_envelope, bp.temperature_derating
		FROM device_battery_config bc
		JOIN battery_profiles bp ON bp.id = bc.profile_id
		WHERE bc.device_sn = $1`, sn).Scan(
		&profileID, &cfg.CapacityAh, &cfg.ParallelStrings,
		&installerLimits, &chargeEnv, &dischargeEnv, &tempDerating)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	if chargeEnv != nil {
		json.Unmarshal(chargeEnv, &cfg.ChargeEnvelope)
	}
	if dischargeEnv != nil {
		json.Unmarshal(dischargeEnv, &cfg.DischargeEnvelope)
	}
	if tempDerating != nil {
		json.Unmarshal(tempDerating, &cfg.TemperatureDerating)
	}
	if installerLimits != nil {
		json.Unmarshal(installerLimits, &cfg.InstallerLimits)
	}
	return &cfg, nil
}

// ratedPower 从 device_models 表读取额定功率（kW）
func (c *DynamicLimitChecker) ratedPower(ctx context.Context, sn string) (float64, error) {
	var ratedPowerKW float64
	err := c.db.QueryRow(ctx, `
		SELECT COALESCE(dm.rated_power_kw, 0)
		FROM devices d JOIN device_models dm ON dm.id = d.model_id
		WHERE d.sn = $1 AND d.deleted_at IS NULL`, sn).Scan(&ratedPowerKW)
	if err == pgx.ErrNoRows {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	return ratedPowerKW, nil
}

// GetEffectiveChargeCurrent 计算有效充电电流上限
// I_effective = min(逆变器额定, BMS CCL, 电池容量×C倍率, 安装商上限, 温度降额)
func (c *DynamicLimitChecker) GetEffectiveChargeCurrent(ctx context.Context, sn string) (float64, error) {
	// 1. 从实时数据读取 BMS CCL (max_charge_current)
	rt := c.realtimeData(ctx, sn)
	var bmsCCL float64
	bmsCCLFound := false
	if rt != nil {
		bmsCCL, bmsCCLFound = getFloatField(rt, "max_charge_current")
	}
	if !bmsCCLFound {
		// 降级到 DB
		raw, err := c.dbRealtimeField(ctx, sn, "max_charge_current")
		if err != nil {
			return 0, err
		}
		if s, ok := raw.(string); ok {
			var f float64
			if _, err := fmt.Sscanf(s, "%f", &f); err == nil {
				bmsCCL = f
				bmsCCLFound = true
			}
		}
	}

	// 2. 从 device_battery_config 读取容量和 charge_envelope
	bc, err := c.batteryConfig(ctx, sn)
	if err != nil {
		return 0, fmt.Errorf("query battery config: %w", err)
	}

	// 3. 读取逆变器额定功率计算额定充电电流
	ratedKW, err := c.ratedPower(ctx, sn)
	if err != nil {
		return 0, fmt.Errorf("query rated power: %w", err)
	}
	// 额定充电电流 ≈ 额定功率(W) / 电池标称电压(V)，简化为 ratedKW * 1000 / 48
	inverterRatedCurrent := ratedKW * 1000 / 48

	// 收集所有上限，取最小值
	var limits []float64

	if inverterRatedCurrent > 0 {
		limits = append(limits, inverterRatedCurrent)
	}
	if bmsCCLFound && bmsCCL > 0 {
		limits = append(limits, bmsCCL)
	}

	// 4. 电池容量 × C 倍率
	if bc != nil {
		totalCapacityAh := float64(bc.CapacityAh) * float64(bc.ParallelStrings)
		if totalCapacityAh <= 0 {
			totalCapacityAh = float64(bc.CapacityAh)
		}
		if totalCapacityAh > 0 {
			// 从 charge_envelope 读取 C 倍率，默认 0.3C
			cRate := 0.3
			if bc.ChargeEnvelope != nil {
				if f, ok := getFloatField(bc.ChargeEnvelope, "c_rate"); ok && f > 0 {
					cRate = f
				}
				// 也可以直接使用 charge_envelope 中的 max_current 字段
				if mc, ok := getFloatField(bc.ChargeEnvelope, "max_current"); ok && mc > 0 {
					limits = append(limits, mc)
				}
			}
			limits = append(limits, totalCapacityAh*cRate)
		}

		// 5. 安装商上限
		if bc.InstallerLimits != nil {
			if mc, ok := getFloatField(bc.InstallerLimits, "max_charge_current"); ok && mc > 0 {
				limits = append(limits, mc)
			}
		}

		// 6. 温度降额
		if rt != nil {
			if battTemp, ok := getFloatField(rt, "battery_temperature", "battery_temp_max"); ok {
				deratingFactor := c.calculateDeratingFactor(bc.TemperatureDerating, battTemp)
				if deratingFactor < 1.0 && len(limits) > 0 {
					// 对当前所有限值施加温度降额系数
					for i := range limits {
						limits[i] *= deratingFactor
					}
				}
			}
		}
	}

	if len(limits) == 0 {
		return 0, nil
	}

	// 返回最小值
	effective := limits[0]
	for _, l := range limits[1:] {
		if l < effective {
			effective = l
		}
	}
	return effective, nil
}

// GetEffectiveDischargeCurrent 计算有效放电电流上限
func (c *DynamicLimitChecker) GetEffectiveDischargeCurrent(ctx context.Context, sn string) (float64, error) {
	rt := c.realtimeData(ctx, sn)
	var bmsDCL float64
	bmsDCLFound := false
	if rt != nil {
		bmsDCL, bmsDCLFound = getFloatField(rt, "max_discharge_current")
	}
	if !bmsDCLFound {
		raw, err := c.dbRealtimeField(ctx, sn, "max_discharge_current")
		if err != nil {
			return 0, err
		}
		if s, ok := raw.(string); ok {
			var f float64
			if _, err := fmt.Sscanf(s, "%f", &f); err == nil {
				bmsDCL = f
				bmsDCLFound = true
			}
		}
	}

	bc, err := c.batteryConfig(ctx, sn)
	if err != nil {
		return 0, fmt.Errorf("query battery config: %w", err)
	}

	ratedKW, err := c.ratedPower(ctx, sn)
	if err != nil {
		return 0, fmt.Errorf("query rated power: %w", err)
	}
	inverterRatedCurrent := ratedKW * 1000 / 48

	var limits []float64

	if inverterRatedCurrent > 0 {
		limits = append(limits, inverterRatedCurrent)
	}
	if bmsDCLFound && bmsDCL > 0 {
		limits = append(limits, bmsDCL)
	}

	if bc != nil {
		totalCapacityAh := float64(bc.CapacityAh) * float64(bc.ParallelStrings)
		if totalCapacityAh <= 0 {
			totalCapacityAh = float64(bc.CapacityAh)
		}
		if totalCapacityAh > 0 {
			cRate := 1.0 // 放电默认 1C
			if bc.DischargeEnvelope != nil {
				if f, ok := getFloatField(bc.DischargeEnvelope, "c_rate"); ok {
					cRate = f
				}
				if mc, ok := getFloatField(bc.DischargeEnvelope, "max_current"); ok && mc > 0 {
					limits = append(limits, mc)
				}
			}
			limits = append(limits, totalCapacityAh*cRate)
		}

		if bc.InstallerLimits != nil {
			if mc, ok := getFloatField(bc.InstallerLimits, "max_discharge_current"); ok && mc > 0 {
				limits = append(limits, mc)
			}
		}

		if rt != nil {
			if battTemp, ok := getFloatField(rt, "battery_temperature", "battery_temp_max"); ok {
				deratingFactor := c.calculateDeratingFactor(bc.TemperatureDerating, battTemp)
				if deratingFactor < 1.0 && len(limits) > 0 {
					for i := range limits {
						limits[i] *= deratingFactor
					}
				}
			}
		}
	}

	if len(limits) == 0 {
		return 0, nil
	}

	effective := limits[0]
	for _, l := range limits[1:] {
		if l < effective {
			effective = l
		}
	}
	return effective, nil
}

// calculateDeratingFactor 根据温度降额曲线计算降额系数
// 支持的 JSON 格式：
//   {"curve": [{"temp": -10, "factor": 0}, {"temp": 25, "factor": 1.0}, ...]}
//   {"-10": 0, "0": 0.5, "25": 1.0, ...}  (温度→系数映射)
//   {"low_temp_threshold": 0, "high_temp_threshold": 45, "low_factor": 0, "high_factor": 0.5}
func (c *DynamicLimitChecker) calculateDeratingFactor(derating map[string]interface{}, temp float64) float64 {
	if derating == nil || len(derating) == 0 {
		return 1.0 // 无降额曲线，不降额
	}

	// 格式1: curve 数组
	if curve, ok := derating["curve"].([]interface{}); ok && len(curve) > 0 {
		return interpolateCurve(curve, temp)
	}

	// 格式2: 温度→系数映射
	type tempFactor struct {
		temp   float64
		factor float64
	}
	var points []tempFactor
	for k, v := range derating {
		// 跳过非温度键
		var keyTemp float64
		if _, err := fmt.Sscanf(k, "%f", &keyTemp); err != nil {
			continue
		}
		if f, ok := getFloatField(map[string]interface{}{"_": v}, "_"); ok {
			points = append(points, tempFactor{keyTemp, f})
		}
	}
	if len(points) > 0 {
		// 排序
		for i := 0; i < len(points); i++ {
			for j := i + 1; j < len(points); j++ {
				if points[j].temp < points[i].temp {
					points[i], points[j] = points[j], points[i]
				}
			}
		}
		// 线性插值
		if temp <= points[0].temp {
			return points[0].factor
		}
		if temp >= points[len(points)-1].temp {
			return points[len(points)-1].factor
		}
		for i := 0; i < len(points)-1; i++ {
			if temp >= points[i].temp && temp <= points[i+1].temp {
				if points[i+1].temp == points[i].temp {
					return points[i].factor
				}
				ratio := (temp - points[i].temp) / (points[i+1].temp - points[i].temp)
				return points[i].factor + ratio*(points[i+1].factor-points[i].factor)
			}
		}
	}

	// 格式3: 阈值模式
	lowThreshold, lowOK := getFloatField(derating, "low_temp_threshold", "low_threshold")
	highThreshold, highOK := getFloatField(derating, "high_temp_threshold", "high_threshold")
	if lowOK && highOK {
		lowFactor, _ := getFloatField(derating, "low_factor", "low_temp_factor")
		highFactor, _ := getFloatField(derating, "high_factor", "high_temp_factor")
		normalFactor := 1.0
		if f, ok := getFloatField(derating, "normal_factor"); ok {
			normalFactor = f
		}
		if temp <= lowThreshold {
			return lowFactor
		}
		if temp >= highThreshold {
			return highFactor
		}
		return normalFactor
	}

	return 1.0
}

// interpolateCurve 在 curve 数组中进行线性插值
func interpolateCurve(curve []interface{}, temp float64) float64 {
	type point struct {
		temp   float64
		factor float64
	}
	var points []point
	for _, item := range curve {
		if m, ok := item.(map[string]interface{}); ok {
			t, okT := getFloatField(m, "temp", "temperature")
			f, okF := getFloatField(m, "factor", "ratio", "limit")
			if okT && okF {
				points = append(points, point{t, f})
			}
		}
	}
	if len(points) == 0 {
		return 1.0
	}
	// 排序
	for i := 0; i < len(points); i++ {
		for j := i + 1; j < len(points); j++ {
			if points[j].temp < points[i].temp {
				points[i], points[j] = points[j], points[i]
			}
		}
	}
	if temp <= points[0].temp {
		return points[0].factor
	}
	if temp >= points[len(points)-1].temp {
		return points[len(points)-1].factor
	}
	for i := 0; i < len(points)-1; i++ {
		if temp >= points[i].temp && temp <= points[i+1].temp {
			if points[i+1].temp == points[i].temp {
				return points[i].factor
			}
			ratio := (temp - points[i].temp) / (points[i+1].temp - points[i].temp)
			return points[i].factor + ratio*(points[i+1].factor-points[i].factor)
		}
	}
	return 1.0
}

// CheckPrerequisites 检查命令前置条件（步骤5中的部分检查）
// 这个方法委托给 PreconditionChecker，保留在 DynamicLimitChecker 上以兼容接口定义
func (c *DynamicLimitChecker) CheckPrerequisites(ctx context.Context, sn, commandCode string, caps repository.CommandCapability) error {
	// 1. requires_stopped → 检查设备是否停机（从 realtime 读取 work_state）
	if caps.RequiresStopped != nil && *caps.RequiresStopped {
		rt := c.realtimeData(ctx, sn)
		if rt != nil {
			if workState, ok := getIntField(rt, "work_state"); ok {
				// work_state == 0 通常表示停机/待机状态
				if workState != 0 {
					return NewCommandError(ErrRequiresStopped,
						fmt.Sprintf("命令 %s 需要设备处于停机状态，当前工作状态: %d", commandCode, workState),
						409)
				}
			}
		}
	}

	// 2. requires_bms_online → 检查 BMS 通信状态
	if caps.RequiresBmsOnline != nil && *caps.RequiresBmsOnline {
		rt := c.realtimeData(ctx, sn)
		bmsOnline := false
		if rt != nil {
			// 检查 batt topic 是否有数据
			if _, ok := getFloatField(rt, "battery_soc"); ok {
				bmsOnline = true
			}
			if _, ok := getFloatField(rt, "max_charge_current"); ok {
				bmsOnline = true
			}
		}
		if !bmsOnline {
			// 降级到 DB 检查
			raw, err := c.dbRealtimeField(ctx, sn, "battery_soc")
			if err == nil && raw != nil {
				bmsOnline = true
			}
		}
		if !bmsOnline {
			return NewCommandError(ErrBMSOffline,
				fmt.Sprintf("命令 %s 需要 BMS 在线，但无法读取 BMS 数据", commandCode),
				503)
		}
	}

	// 3. cooldown 检查由 PreconditionChecker 处理
	return nil
}

// realtimDataAge 返回实时数据的新鲜度（秒），如果无法确定返回 -1
func (c *DynamicLimitChecker) realtimeDataAge(ctx context.Context, sn string) float64 {
	if c.cache == nil {
		return -1
	}
	// 检查设备心跳是否存在
	exists := c.cache.Exists(ctx, "device:heartbeat:"+sn).Val()
	if exists > 0 {
		return 0 // 在线
	}
	// 尝试从 _updated_at 推算
	cached, err := c.cache.Get(ctx, "realtime:latest:"+sn).Result()
	if err != nil {
		return -1
	}
	var m map[string]interface{}
	if json.Unmarshal([]byte(cached), &m) != nil {
		return -1
	}
	if updatedAt, ok := m["_updated_at"].(string); ok {
		if t, err := time.Parse(time.RFC3339, updatedAt); err == nil {
			return time.Since(t).Seconds()
		}
	}
	return -1
}
