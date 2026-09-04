package service

import (
	"context"
	"encoding/json"
	"reflect"
	"sort"
	"time"

	"inv-device-server/internal/model"
	"inv-device-server/internal/repository"
	telemetryv2 "inv-device-server/internal/telemetry"
	"inv-device-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// DiagnosticEngine V2.1 诊断引擎（CS-L10-6K2）。
// 触发时机：V2 心跳 SaveTelemetryV2 成功、Redis realtime 写入后运行；
// 规则见 V2.1 文档 14.1-14.4，阈值参数化于 device_models.specifications.diagnostics。
// 独立写入：任何失败仅记日志，不阻塞心跳主链路（文档 12.3）。
type DiagnosticEngine struct {
	repo *repository.DeviceRepository
	rdb  *redis.Client
}

func NewDiagnosticEngine(repo *repository.DeviceRepository, rdb *redis.Client) *DiagnosticEngine {
	return &DiagnosticEngine{repo: repo, rdb: rdb}
}

// Run 执行诊断规则并持久化：
//  1. device_diagnostics 去重聚合（触发 upsert / 恢复 resolved）
//  2. 健康度写 device_latest_state.health_score + device_health_history
//  3. Redis realtime:latest 的 derived 组补 thermal_status/health_score/health_level，新增 diagnostics 组
func (e *DiagnosticEngine) Run(ctx context.Context, sn string, modelID int32, sample *telemetryv2.Sample) {
	specs := e.repo.GetModelDiagnosticSpecs(ctx, modelID)

	triggered := e.evaluateRules(ctx, sn, sample, specs)
	// 配置漂移（9.4）：desired 非空且 sync_status=drifted → CONFIG_DRIFT；恢复一致 → resolved
	e.checkConfigDrift(ctx, sn, &triggered)
	active, err := e.repo.ListActiveDiagnostics(ctx, sn)
	if err != nil {
		logger.Warn("List active diagnostics failed", zap.String("sn", sn), zap.Error(err))
		return
	}

	now := time.Now().UTC()
	activeByCode := make(map[string]model.DiagnosticEvent, len(active))
	for _, evt := range active {
		activeByCode[evt.RuleCode] = evt
	}
	triggeredByCode := make(map[string]bool, len(triggered))

	// 触发的事件：upsert（count+1 / last_at 刷新）
	for i := range triggered {
		evt := &triggered[i]
		triggeredByCode[evt.RuleCode] = true
		if err := e.repo.UpsertDiagnostic(ctx, sn, *evt); err != nil {
			logger.Warn("Upsert diagnostic failed", zap.String("sn", sn), zap.String("rule", evt.RuleCode), zap.Error(err))
		}
	}

	// 先前 active 的事件：触发条件不成立持续 3 个心跳周期（540s）→ resolved；
	// MAINTENANCE_DUE 为跨阈值提醒，保持 active 直到人工处理（文档 14.3）。
	resolveWindow := model.ResolveHeartbeatPeriods * model.HeartbeatPeriodSeconds * time.Second
	for code, evt := range activeByCode {
		if triggeredByCode[code] {
			continue
		}
		if code == model.RuleMaintenanceDue {
			continue
		}
		if now.Sub(evt.LastAt) >= resolveWindow {
			if err := e.repo.ResolveDiagnostic(ctx, sn, code); err != nil {
				logger.Warn("Resolve diagnostic failed", zap.String("sn", sn), zap.String("rule", code), zap.Error(err))
			}
			delete(activeByCode, code)
		}
	}

	// 重新组装活跃列表（触发 + 未恢复）用于健康度与 Redis 同步
	for i := range triggered {
		activeByCode[triggered[i].RuleCode] = triggered[i]
	}
	activeList := make([]model.DiagnosticEvent, 0, len(activeByCode))
	for _, evt := range activeByCode {
		activeList = append(activeList, evt)
	}

	health := ComputeHealth(sample, activeList, specs)
	if err := e.repo.SaveHealthScore(ctx, sn, health, sample.EventTime); err != nil {
		logger.Warn("Save health score failed", zap.String("sn", sn), zap.Error(err))
	}

	e.syncRealtime(ctx, sn, deriveThermalStatus(sample, specs), health, activeList)
}

// evaluateRules 计算当前心跳样本触发的诊断事件（规则见文档 14.1-14.3）。
func (e *DiagnosticEngine) evaluateRules(ctx context.Context, sn string, s *telemetryv2.Sample, specs model.DiagnosticSpecs) []model.DiagnosticEvent {
	now := time.Now().UTC()
	detail := func(kv ...any) map[string]any {
		m := make(map[string]any, len(kv)/2)
		for i := 0; i+1 < len(kv); i += 2 {
			m[kv[i].(string)] = kv[i+1]
		}
		return m
	}
	mk := func(code, level string, d map[string]any) model.DiagnosticEvent {
		return model.DiagnosticEvent{RuleCode: code, Level: level, Status: "active", Detail: d, LastAt: now}
	}

	var events []model.DiagnosticEvent

	// 14.1 散热诊断：风扇低速 + 对应温度过高 → fault
	invT, boostT := s.System.InverterTemperature, s.System.BoostTemperature
	if s.Fan.InvSpeed != nil && invT != nil && *s.Fan.InvSpeed < specs.FanSpeedLowPercent && *invT > specs.FanAbnormalTempC {
		events = append(events, mk(model.RuleInvFanAbnormal, "fault", detail(
			"inv_fan_speed", round1(*s.Fan.InvSpeed), "inverter_temperature", round1(*invT))))
	}
	if s.Fan.MPPTSpeed != nil && boostT != nil && *s.Fan.MPPTSpeed < specs.FanSpeedLowPercent && *boostT > specs.FanAbnormalTempC {
		events = append(events, mk(model.RuleMpptFanAbnormal, "fault", detail(
			"mppt_fan_speed", round1(*s.Fan.MPPTSpeed), "boost_temperature", round1(*boostT))))
	}
	if (invT != nil && *invT > specs.OverheatTempC) || (boostT != nil && *boostT > specs.OverheatTempC) {
		events = append(events, mk(model.RuleThermalOverheat, "fault", detail(
			"inverter_temperature", tempOrNil(invT), "boost_temperature", tempOrNil(boostT))))
	}

	// 14.2 并机诊断：paired>0 且 online<paired → warning；online>on → info
	if s.Sock.PairedSocket != nil {
		paired := *s.Sock.PairedSocket
		online := sockOrZero(s.Sock.OnlineSocket)
		on := sockOrZero(s.Sock.OnSocket)
		if paired > 0 && online < paired {
			events = append(events, mk(model.RuleParallelSlaveOffline, "warning", detail(
				"paired_socket", paired, "online_socket", online, "offline_mask", paired&^online)))
		}
		if online > on {
			events = append(events, mk(model.RuleParallelNotRunning, "info", detail(
				"online_socket", online, "on_socket", on, "not_running_mask", online&^on)))
		}
	}

	// 14.3 维护提醒：work_time_total 跨过阈值（上次 < 阈值 ≤ 本次）
	if s.Diag.WorkTimeTotal != nil {
		thresholdSec := specs.MaintenanceHours * 3600
		cur := *s.Diag.WorkTimeTotal
		if cur >= thresholdSec {
			prev, found, err := e.repo.GetPreviousWorkTimeTotal(ctx, sn, s.EventTime)
			if err != nil {
				logger.Warn("Get previous work_time_total failed", zap.String("sn", sn), zap.Error(err))
			} else if !found || prev < thresholdSec {
				events = append(events, mk(model.RuleMaintenanceDue, "warning", detail(
					"work_time_total", round1(cur), "threshold_hours", specs.MaintenanceHours)))
			}
		}
	}
	return events
}

// deriveThermalStatus 散热状态（文档 6.3/14.1）：fault / warning / normal。
func deriveThermalStatus(s *telemetryv2.Sample, specs model.DiagnosticSpecs) string {
	invT, boostT := s.System.InverterTemperature, s.System.BoostTemperature
	overheat := (invT != nil && *invT > specs.OverheatTempC) || (boostT != nil && *boostT > specs.OverheatTempC)
	fanFault := (s.Fan.InvSpeed != nil && invT != nil && *s.Fan.InvSpeed < specs.FanSpeedLowPercent && *invT > specs.FanAbnormalTempC) ||
		(s.Fan.MPPTSpeed != nil && boostT != nil && *s.Fan.MPPTSpeed < specs.FanSpeedLowPercent && *boostT > specs.FanAbnormalTempC)
	if overheat || fanFault {
		return "fault"
	}
	highTemp := (invT != nil && *invT > specs.FanAbnormalTempC) || (boostT != nil && *boostT > specs.FanAbnormalTempC)
	fanLow := (s.Fan.InvSpeed != nil && *s.Fan.InvSpeed < specs.FanSpeedLowPercent) ||
		(s.Fan.MPPTSpeed != nil && *s.Fan.MPPTSpeed < specs.FanSpeedLowPercent)
	if highTemp || fanLow {
		return "warning"
	}
	return "normal"
}

// syncRealtime 将诊断与健康度合并写入 Redis realtime:latest（不覆盖遥测组）：
// derived 组追加 thermal_status/health_score/health_level；新增 diagnostics 组（活跃列表）。
func (e *DiagnosticEngine) syncRealtime(ctx context.Context, sn string, thermalStatus string, health model.HealthResult, active []model.DiagnosticEvent) {
	if e.rdb == nil {
		return
	}
	key := "realtime:latest:" + sn
	rt := make(map[string]interface{})
	if existing, err := e.rdb.Get(ctx, key).Bytes(); err == nil {
		_ = json.Unmarshal(existing, &rt)
	}

	derivedData := make(map[string]interface{})
	if derived, ok := rt["derived"].(map[string]interface{}); ok {
		if data, ok := derived["data"].(map[string]interface{}); ok {
			derivedData = data
		}
	}
	derivedData["thermal_status"] = thermalStatus
	derivedData["health_score"] = health.Score
	derivedData["health_level"] = health.Level
	rt["derived"] = map[string]interface{}{
		"data":      derivedData,
		"timestamp": time.Now().UTC().Unix(),
	}

	diagList := make([]map[string]interface{}, 0, len(active))
	for _, evt := range active {
		diagList = append(diagList, map[string]interface{}{
			"rule_code": evt.RuleCode, "level": evt.Level, "status": evt.Status,
			"detail": evt.Detail, "first_at": evt.FirstAt, "last_at": evt.LastAt, "count": evt.Count,
		})
	}
	rt["diagnostics"] = map[string]interface{}{
		"data":      diagList,
		"timestamp": time.Now().UTC().Unix(),
	}
	rt["_updated_at"] = time.Now().UTC().Format(time.RFC3339)

	if merged, err := json.Marshal(rt); err == nil {
		_ = e.rdb.Set(ctx, key, merged, 10*time.Minute).Err()
	}
}

// 配置漂移检查（V2.1 文档 9.4）：desired 非空且 sync_status=drifted 时持续生成 CONFIG_DRIFT
// （心跳每 180s 刷新 last_at，天然满足“持续超过 1 个心跳周期”语义）；synced 时由 Run 统一 resolve。
func (e *DiagnosticEngine) checkConfigDrift(ctx context.Context, sn string, triggered *[]model.DiagnosticEvent) {
	desired, reported, syncStatus, err := e.repo.GetControlState(ctx, sn)
	if err != nil {
		return // 无 device_control_state 行（尚未上报配置）是正常情况，静默跳过
	}
	if len(desired) == 0 {
		return // 无下发配置，不判定漂移
	}
	if syncStatus == "drifted" {
		var diff []string
		for k := range desired {
			if !reflect.DeepEqual(desired[k], reported[k]) {
				diff = append(diff, k)
			}
		}
		sort.Strings(diff)
		*triggered = append(*triggered, model.DiagnosticEvent{
			RuleCode: model.RuleConfigDrift,
			Level:    "warning",
			Status:   "active",
			Detail:   map[string]any{"diff_keys": diff, "desired_count": len(desired), "reported_count": len(reported)},
			LastAt:   time.Now().UTC(),
		})
	}
}

func sockOrZero(p *uint32) uint32 {
	if p == nil {
		return 0
	}
	return *p
}

func tempOrNil(p *float64) any {
	if p == nil {
		return nil
	}
	return round1(*p)
}

func round1(v float64) float64 {
	return float64(int(v*10+0.5)) / 10
}
