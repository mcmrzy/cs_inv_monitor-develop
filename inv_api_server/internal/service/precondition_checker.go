package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// PreconditionChecker 前置条件检查器
// 负责命令的 cooldown 跟踪、TTL 覆盖跟踪、requires_stopped 和 requires_bms_online 检查
type PreconditionChecker struct {
	cache *redis.Client
}

func NewPreconditionChecker(cache *redis.Client) *PreconditionChecker {
	return &PreconditionChecker{cache: cache}
}

// CheckCooldown 检查命令是否在冷却期内
// Redis key: device:cmd_cooldown:{sn}:{command_code}
func (p *PreconditionChecker) CheckCooldown(ctx context.Context, sn, commandCode string) error {
	if p.cache == nil {
		return nil
	}
	key := fmt.Sprintf("device:cmd_cooldown:%s:%s", sn, commandCode)
	exists, err := p.cache.Exists(ctx, key).Result()
	if err != nil {
		logger.Warn("Failed to check cooldown", zap.String("sn", sn), zap.String("cmd", commandCode), zap.Error(err))
		return nil // 降级：不阻塞命令
	}
	if exists > 0 {
		ttl, _ := p.cache.TTL(ctx, key).Result()
		return NewCommandError(ErrDeviceBusy,
			fmt.Sprintf("命令 %s 处于冷却期，剩余 %d 秒", commandCode, int(ttl.Seconds())),
			429)
	}
	return nil
}

// RecordCooldown 记录命令冷却期
func (p *PreconditionChecker) RecordCooldown(ctx context.Context, sn, commandCode string, cooldownSeconds int) {
	if p.cache == nil || cooldownSeconds <= 0 {
		return
	}
	key := fmt.Sprintf("device:cmd_cooldown:%s:%s", sn, commandCode)
	if err := p.cache.Set(ctx, key, "1", time.Duration(cooldownSeconds)*time.Second).Err(); err != nil {
		logger.Warn("Failed to record cooldown", zap.String("sn", sn), zap.String("cmd", commandCode), zap.Error(err))
	}
}

// CheckOverride 检查调试授权/覆盖窗口是否仍然有效
// Redis key: device:override:{sn}:{domain}
func (p *PreconditionChecker) CheckOverride(ctx context.Context, sn, domain string) error {
	if p.cache == nil {
		return NewCommandError(ErrAuthorizationExpired,
			fmt.Sprintf("需要有效的调试授权窗口（域: %s），但缓存不可用", domain),
			403)
	}
	key := fmt.Sprintf("device:override:%s:%s", sn, domain)
	exists, err := p.cache.Exists(ctx, key).Result()
	if err != nil {
		return NewCommandError(ErrAuthorizationExpired,
			fmt.Sprintf("检查调试授权失败: %v", err),
			403)
	}
	if exists == 0 {
		return NewCommandError(ErrAuthorizationExpired,
			fmt.Sprintf("调试授权窗口已过期或未激活（域: %s）", domain),
			403)
	}
	return nil
}

// RecordOverride 记录调试授权覆盖窗口
func (p *PreconditionChecker) RecordOverride(ctx context.Context, sn, domain string, ttlSeconds int) {
	if p.cache == nil || ttlSeconds <= 0 {
		return
	}
	key := fmt.Sprintf("device:override:%s:%s", sn, domain)
	if err := p.cache.Set(ctx, key, "1", time.Duration(ttlSeconds)*time.Second).Err(); err != nil {
		logger.Warn("Failed to record override", zap.String("sn", sn), zap.String("domain", domain), zap.Error(err))
	}
}

// CheckStopped 检查设备是否处于停机状态（用于 requires_stopped 前置条件）
// 从 Redis realtime:latest:{sn} 读取 work_state
func (p *PreconditionChecker) CheckStopped(ctx context.Context, sn string) error {
	workState, found := p.readWorkState(ctx, sn)
	if !found {
		// 无法读取 work_state，降级为放行（fail-open）
		// 因为命令执行后设备会自然拒绝不适合当前状态的操作
		return nil
	}
	// work_state == 0 通常表示停机/待机
	if workState != 0 {
		return NewCommandError(ErrRequiresStopped,
			fmt.Sprintf("需要设备处于停机状态，当前工作状态: %d", workState),
			409)
	}
	return nil
}

// CheckBmsOnline 检查 BMS 是否在线（用于 requires_bms_online 前置条件）
// 从 Redis realtime 检查 BMS 数据是否存在且不过期
func (p *PreconditionChecker) CheckBmsOnline(ctx context.Context, sn string) error {
	if p.cache == nil {
		return NewCommandError(ErrBMSOffline, "缓存不可用，无法确认 BMS 在线状态", 503)
	}

	// 读取实时数据并检查 BMS 相关字段
	rt := p.readRealtimeFlat(ctx, sn)
	if rt == nil {
		return NewCommandError(ErrBMSOffline, "无法读取设备实时数据", 503)
	}

	// BMS 在线的标志：存在 battery_soc 或 max_charge_current 等字段
	bmsFields := []string{"battery_soc", "max_charge_current", "max_discharge_current", "battery_voltage"}
	bmsDataFound := false
	for _, field := range bmsFields {
		if v, ok := rt[field]; ok && v != nil {
			bmsDataFound = true
			break
		}
	}

	if !bmsDataFound {
		return NewCommandError(ErrBMSOffline, "BMS 数据不存在，BMS 可能离线", 503)
	}

	// 检查数据新鲜度：_updated_at 不应超过 2 分钟
	if updatedAt, ok := rt["_updated_at"].(string); ok {
		if t, err := time.Parse(time.RFC3339, updatedAt); err == nil {
			age := time.Since(t).Seconds()
			if age > 120 {
				return NewCommandError(ErrBMSOffline,
					fmt.Sprintf("BMS 数据已过期（%.0f秒前）", age),
					503)
			}
		}
	}

	return nil
}

// CheckActiveFault 检查设备是否有活动故障
func (p *PreconditionChecker) CheckActiveFault(ctx context.Context, sn string) error {
	rt := p.readRealtimeFlat(ctx, sn)
	if rt == nil {
		return nil // 降级：无法读取实时数据时不阻塞
	}

	// 检查 fault_code
	if faultCode, ok := getIntField(rt, "fault_code"); ok && faultCode != 0 {
		return NewCommandError(ErrActiveFault,
			fmt.Sprintf("设备存在活动故障（故障码: %d）", faultCode),
			409)
	}

	// 检查 BMS 故障码
	if bmsFault, ok := getIntField(rt, "bms_fault_code"); ok && bmsFault != 0 {
		return NewCommandError(ErrActiveFault,
			fmt.Sprintf("BMS 存在活动故障（故障码: %d）", bmsFault),
			409)
	}

	return nil
}

// CheckDeviceOnline 检查设备是否在线
func (p *PreconditionChecker) CheckDeviceOnline(ctx context.Context, sn string) error {
	if p.cache == nil {
		return nil // 降级
	}
	exists := p.cache.Exists(ctx, "device:heartbeat:"+sn).Val()
	if exists == 0 {
		return NewCommandError(ErrDeviceOffline,
			fmt.Sprintf("设备 %s 离线", sn),
			503)
	}
	return nil
}

// CheckRiskConfirmation 检查风险确认和调试授权
func (p *PreconditionChecker) CheckRiskConfirmation(ctx context.Context, sn string, caps repository.CommandCapability) error {
	// 高风险命令需要物理确认
	if caps.ConfirmationMode != nil {
		mode := *caps.ConfirmationMode
		switch mode {
		case "physical":
			// 物理确认需要设备端按键，无法在 API 侧校验
			// 但要求调试授权窗口存在
			if caps.ConfigDomain != nil {
				if err := p.CheckOverride(ctx, sn, *caps.ConfigDomain); err != nil {
					return err
				}
			}
			return NewCommandError(ErrPhysicalConfirmationRequired,
				"此命令需要设备端物理确认", 428)
		case "debug":
			// 调试模式：需要授权窗口
			if caps.ConfigDomain != nil {
				if err := p.CheckOverride(ctx, sn, *caps.ConfigDomain); err != nil {
					return err
				}
			}
		}
	}

	// TTL 检查：如果命令有 TTL 配置，检查是否有有效的覆盖窗口
	if caps.TtlSeconds != nil && *caps.TtlSeconds > 0 && caps.ConfigDomain != nil {
		if err := p.CheckOverride(ctx, sn, *caps.ConfigDomain); err != nil {
			return err
		}
	}

	return nil
}

// CheckPrerequisites 综合前置条件检查（步骤5和步骤8）
func (p *PreconditionChecker) CheckPrerequisites(ctx context.Context, sn, commandCode string, caps repository.CommandCapability) error {
	// 步骤5: 设备在线检查
	if caps.RequiresOnline {
		if err := p.CheckDeviceOnline(ctx, sn); err != nil {
			return err
		}
	}

	// 步骤5: requires_stopped 检查
	if caps.RequiresStopped != nil && *caps.RequiresStopped {
		if err := p.CheckStopped(ctx, sn); err != nil {
			return err
		}
	}

	// 步骤5: 活动故障检查
	if err := p.CheckActiveFault(ctx, sn); err != nil {
		return err
	}

	// 步骤5: requires_bms_online 检查
	if caps.RequiresBmsOnline != nil && *caps.RequiresBmsOnline {
		if err := p.CheckBmsOnline(ctx, sn); err != nil {
			return err
		}
	}

	// 步骤8: 风险确认、调试授权窗口
	if err := p.CheckRiskConfirmation(ctx, sn, caps); err != nil {
		return err
	}

	// 步骤8: 冷却时间检查
	if caps.CooldownSeconds != nil && *caps.CooldownSeconds > 0 {
		if err := p.CheckCooldown(ctx, sn, commandCode); err != nil {
			return err
		}
	}

	return nil
}

// readRealtimeFlat 从 Redis 读取展平的实时数据
func (p *PreconditionChecker) readRealtimeFlat(ctx context.Context, sn string) map[string]interface{} {
	if p.cache == nil {
		return nil
	}
	result := make(map[string]interface{})

	// 优先读取有效数据缓存
	for _, key := range []string{"realtime:last_valid:" + sn, "realtime:latest:" + sn} {
		cached, err := p.cache.Get(ctx, key).Result()
		if err != nil || cached == "" {
			continue
		}
		var m map[string]interface{}
		if json.Unmarshal([]byte(cached), &m) != nil {
			continue
		}
		for k, v := range m {
			// 跳过元数据字段
			if k == "_sn" || k == "_msg_type" || k == "_timestamp" {
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
	fields, err := p.cache.HGetAll(ctx, hashKey).Result()
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

// readWorkState 从实时数据读取 work_state
func (p *PreconditionChecker) readWorkState(ctx context.Context, sn string) (int64, bool) {
	rt := p.readRealtimeFlat(ctx, sn)
	if rt == nil {
		return 0, false
	}
	return getIntField(rt, "work_state")
}
