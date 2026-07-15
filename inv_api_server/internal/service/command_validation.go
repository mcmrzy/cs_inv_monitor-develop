package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/pkg/logger"

	"go.uber.org/zap"
)

// PreparedCommand 校验通过后的预编译命令
type PreparedCommand struct {
	TaskID    string
	Command   string
	Params    map[string]interface{}
	Args      []interface{}
	HasV2Spec bool
	Caps      *repository.CommandCapability
}

// getCommandCapability 获取指定设备的指定命令的完整能力定义
func (s *DeviceService) getCommandCapability(ctx context.Context, sn, commandCode string) (*repository.CommandCapability, error) {
	modelID, err := s.modelRepo.GetModelIDByDeviceSN(ctx, sn)
	if err != nil || modelID == 0 {
		return nil, fmt.Errorf("无法获取设备型号ID")
	}
	caps, err := s.modelRepo.GetCommandCapabilitiesByModelID(ctx, modelID)
	if err != nil {
		return nil, fmt.Errorf("查询命令能力失败: %w", err)
	}
	for i := range caps {
		if caps[i].CommandCode == commandCode {
			return &caps[i], nil
		}
	}
	return nil, fmt.Errorf("命令 %s 不在设备型号支持列表中", commandCode)
}

// commandInvolvesCurrent 检查命令是否涉及充放电电流参数
func commandInvolvesCurrent(commandCode string, params map[string]interface{}) (charge, discharge bool) {
	// 基于命令码判断
	lowerCmd := strings.ToLower(commandCode)
	if strings.Contains(lowerCmd, "charge") {
		charge = true
	}
	if strings.Contains(lowerCmd, "discharge") {
		discharge = true
	}

	// 基于参数键判断
	currentKeys := []string{
		"charge_current", "max_charge_current", "charge_current_limit",
		"discharge_current", "max_discharge_current", "discharge_current_limit",
	}
	for key := range params {
		lowerKey := strings.ToLower(key)
		for _, ck := range currentKeys {
			if strings.Contains(lowerKey, ck) {
				if strings.Contains(lowerKey, "discharge") {
					discharge = true
				} else {
					charge = true
				}
			}
		}
	}
	return
}

// ValidateAndPrepareCommand 实现9步校验链
//
// 步骤1: 身份、设备归属、细粒度 permission
// 步骤2: 型号/固件是否支持命令
// 步骤3: 参数类型、单位、缩放、静态范围、枚举
// 步骤4: 多参数关系和互斥关系
// 步骤5: 设备在线、当前模式、停机/故障/忙状态
// 步骤6: BMS 在线及 CCL/DCL、电压、温度、SOC 动态限制
// 步骤7: 并机组级状态和拓扑限制
// 步骤8: 风险确认、调试授权窗口、TTL 和冷却时间
// 步骤9: 创建设备独立 task_id
func (s *DeviceService) ValidateAndPrepareCommand(ctx context.Context, userID int64, sn, commandCode string, params map[string]interface{}) (*PreparedCommand, error) {
	// ── 步骤1: 身份、设备归属、细粒度 permission ──
	// HasControlPermission 检查 RBAC devices:control + 数据归属
	if !s.HasControlPermission(ctx, userID, sn) {
		return nil, NewCommandError(ErrUnsupportedCommand, "无控制权限", 403)
	}
	// CheckCommandPermission 检查细粒度 permission_code
	if err := s.CheckCommandPermission(ctx, userID, sn, commandCode); err != nil {
		return nil, NewCommandError(ErrUnsupportedCommand, err.Error(), 403)
	}

	// ── 步骤2: 型号/固件是否支持命令（fail-closed：未知命令默认拒绝） ──
	found, enabled, err := s.modelRepo.CommandCapability(ctx, sn, commandCode)
	if err != nil {
		return nil, NewCommandError(ErrUnsupportedCommand, fmt.Sprintf("查询命令能力失败: %v", err), 500)
	}
	if !found {
		return nil, NewCommandError(ErrUnsupportedCommand,
			fmt.Sprintf("命令 %s 不在设备型号允许的控制命令中", commandCode), 400)
	}
	if !enabled {
		return nil, NewCommandError(ErrUnsupportedCommand,
			fmt.Sprintf("命令 %s 已被禁用", commandCode), 403)
	}

	// 获取完整能力定义用于后续步骤
	caps, err := s.getCommandCapability(ctx, sn, commandCode)
	if err != nil {
		return nil, NewCommandError(ErrUnsupportedCommand, err.Error(), 400)
	}

	// ── 步骤3: 参数类型、单位、缩放、静态范围、枚举 ──
	// ── 步骤4: 多参数关系和互斥关系 ──
	// 这两步由 BuildCommandArgs 统一完成
	args, hasV2Spec, err := s.modelRepo.BuildCommandArgs(ctx, sn, commandCode, params)
	if err != nil {
		return nil, NewCommandError(ErrInvalidRange, err.Error(), 400)
	}
	// 如果命令存在但未返回 V2 spec（hasV2Spec=false），说明是未知命令
	if !hasV2Spec {
		return nil, NewCommandError(ErrUnsupportedCommand,
			fmt.Sprintf("命令 %s 未配置参数模式", commandCode), 400)
	}

	// ── 步骤5: 设备在线、当前模式、停机/故障/忙状态 ──
	if s.preconditionChecker != nil {
		if err := s.preconditionChecker.CheckPrerequisites(ctx, sn, commandCode, *caps); err != nil {
			return nil, err
		}
	}

	// ── 步骤6: BMS 在线及 CCL/DCL、电压、温度、SOC 动态限制 ──
	if s.limitChecker != nil {
		if err := s.checkDynamicLimits(ctx, sn, commandCode, params, caps); err != nil {
			return nil, err
		}
	}

	// ── 步骤7: 并机组级状态和拓扑限制 ──
	// TODO: 实现并机拓扑检查。当前阶段先留空，后续根据 device_parallel_state 表完善
	// if caps.RequiresGroupMaster != nil && *caps.RequiresGroupMaster {
	//     // 检查设备是否为并机主机
	// }

	// ── 步骤8: 风险确认、调试授权窗口、TTL 和冷却时间 ──
	// 步骤8 的部分检查已在步骤5的 CheckPrerequisites 中完成（CheckRiskConfirmation + CheckCooldown）
	// 此处补充记录冷却期（在命令成功发送后记录）

	// ── 步骤9: 创建设备独立 task_id ──
	taskID := generateTaskID()

	return &PreparedCommand{
		TaskID:    taskID,
		Command:   commandCode,
		Params:    params,
		Args:      args,
		HasV2Spec: hasV2Spec,
		Caps:      caps,
	}, nil
}

// checkDynamicLimits 检查步骤6的动态限值
func (s *DeviceService) checkDynamicLimits(ctx context.Context, sn, commandCode string, params map[string]interface{}, caps *repository.CommandCapability) error {
	// 如果命令需要 BMS 在线但 BMS 不可用，返回 BMS_OFFLINE
	if caps.RequiresBmsOnline != nil && *caps.RequiresBmsOnline {
		// 检查 Redis 是否可用
		if s.cache == nil {
			return NewCommandError(ErrBMSOffline, "缓存不可用，无法验证 BMS 限制", 503)
		}
	}

	// 检查命令是否涉及充放电电流
	involvesCharge, involvesDischarge := commandInvolvesCurrent(commandCode, params)
	if !involvesCharge && !involvesDischarge {
		// 命令不涉及充放电电流，跳过动态限制检查
		return nil
	}

	// 检查请求的电流值是否超过动态限值
	if involvesCharge {
		effectiveLimit, err := s.limitChecker.GetEffectiveChargeCurrent(ctx, sn)
		if err != nil {
			logger.Warn("Failed to get effective charge current, degrading",
				zap.String("sn", sn), zap.Error(err))
			// 降级：无法获取限制值时不阻塞命令
			return nil
		}
		if effectiveLimit <= 0 {
			return nil // 无限制信息，不阻塞
		}
		requestedCurrent, ok := extractCurrentFromParams(params, true)
		if ok && requestedCurrent > effectiveLimit {
			return NewCommandError(ErrBMSLimitExceeded,
				fmt.Sprintf("请求充电电流 %.1fA 超过有效限制 %.1fA（BMS CCL/温度降额）", requestedCurrent, effectiveLimit),
				422)
		}
	}

	if involvesDischarge {
		effectiveLimit, err := s.limitChecker.GetEffectiveDischargeCurrent(ctx, sn)
		if err != nil {
			logger.Warn("Failed to get effective discharge current, degrading",
				zap.String("sn", sn), zap.Error(err))
			return nil
		}
		if effectiveLimit <= 0 {
			return nil
		}
		requestedCurrent, ok := extractCurrentFromParams(params, false)
		if ok && requestedCurrent > effectiveLimit {
			return NewCommandError(ErrBMSLimitExceeded,
				fmt.Sprintf("请求放电电流 %.1fA 超过有效限制 %.1fA（BMS DCL/温度降额）", requestedCurrent, effectiveLimit),
				422)
		}
	}

	return nil
}

// extractCurrentFromParams 从参数中提取电流值
func extractCurrentFromParams(params map[string]interface{}, isCharge bool) (float64, bool) {
	var keys []string
	if isCharge {
		keys = []string{"charge_current", "max_charge_current", "charge_current_limit"}
	} else {
		keys = []string{"discharge_current", "max_discharge_current", "discharge_current_limit"}
	}
	for _, key := range keys {
		if v, ok := params[key]; ok && v != nil {
			switch n := v.(type) {
			case float64:
				return n, true
			case int:
				return float64(n), true
			case int64:
				return float64(n), true
			}
		}
	}
	return 0, false
}

// SendPreparedCommand 发送已校验通过的预编译命令
// 这是对 SendCommand 的补充，跳过校验步骤直接发送
func (s *DeviceService) SendPreparedCommand(ctx context.Context, sn string, prepared *PreparedCommand) (string, error) {
	if s.deviceSrvURL == "" {
		return "", fmt.Errorf("device server URL not configured")
	}

	params := prepared.Params
	cmdType := prepared.Command
	taskID := prepared.TaskID
	args := prepared.Args
	hasV2Spec := prepared.HasV2Spec

	// 1. 写入命令日志（status=pending）
	paramsJSON, _ := json.Marshal(params)
	if err := s.repo.InsertCommandLog(ctx, sn, taskID, cmdType, string(paramsJSON)); err != nil {
		logger.Error("Failed to insert command log",
			zap.String("sn", sn), zap.String("task_id", taskID), zap.Error(err))
		return "", fmt.Errorf("persist command audit log: %w", err)
	}

	// 2. 构造命令体
	cmdBody := map[string]interface{}{
		"command": cmdType,
		"params":  params,
		"task_id": taskID,
	}
	if hasV2Spec {
		cmdBody["v"] = 1
		cmdBody["t"] = time.Now().Unix()
		cmdBody["cmd"] = cmdType
		cmdBody["args"] = args
		cmdBody["expires_at"] = time.Now().Add(5 * time.Minute).Unix()
	}
	body, err := json.Marshal(cmdBody)
	if err != nil {
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "marshal command failed")
		return "", fmt.Errorf("marshal command: %w", err)
	}

	// 3. 发送到 Device Server
	url := fmt.Sprintf("%s/api/v1/device/%s/command", s.deviceSrvURL, sn)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "create request failed")
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if s.internalKey != "" {
		req.Header.Set("X-Internal-Key", s.internalKey)
	}

	resp, err := s.httpClient.Do(req)
	if err != nil {
		logger.Error("SendPreparedCommand HTTP call failed",
			zap.String("sn", sn), zap.String("cmd", cmdType), zap.Error(err))
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "发送失败: "+err.Error())
		return "", fmt.Errorf("send command to device server: %w", err)
	}
	defer resp.Body.Close()

	// 4. 设备离线时，存入 Redis 离线队列
	if resp.StatusCode == http.StatusServiceUnavailable {
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "queued", fmt.Sprintf("设备 %s 离线，命令已排队等待发送", sn))
		if s.cache != nil {
			queueKey := "device:cmd:queue:" + sn
			_ = s.cache.RPush(ctx, queueKey, body).Err()
			_ = s.cache.Expire(ctx, queueKey, 5*time.Minute).Err()
			logger.Info("Command queued for offline device",
				zap.String("sn", sn), zap.String("task_id", taskID))
		}
		return taskID, nil
	}

	if resp.StatusCode >= http.StatusBadRequest {
		respBody, _ := io.ReadAll(resp.Body)
		logger.Error("SendPreparedCommand failed",
			zap.String("sn", sn), zap.String("cmd", cmdType),
			zap.Int("status", resp.StatusCode), zap.String("body", string(respBody)))
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", fmt.Sprintf("Device Server 返回 %d", resp.StatusCode))
		return "", fmt.Errorf("device server returned status %d", resp.StatusCode)
	}

	_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "sent", "命令已发送")

	// 5. 插入发送通知
	if hasV2Spec && !strings.HasPrefix(cmdType, "query_") {
		_ = s.repo.SetDesiredControlState(ctx, sn, taskID, cmdType, params)
	}
	s.insertCmdNotification(ctx, sn, taskID, cmdType)

	// 6. 记录冷却期
	if s.preconditionChecker != nil && prepared.Caps != nil && prepared.Caps.CooldownSeconds != nil {
		s.preconditionChecker.RecordCooldown(ctx, sn, cmdType, *prepared.Caps.CooldownSeconds)
	}

	logger.Info("Prepared command sent to device server",
		zap.String("sn", sn), zap.String("cmd", cmdType), zap.String("task_id", taskID))
	return taskID, nil
}
