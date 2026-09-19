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

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/logger"

	"github.com/jackc/pgx/v5"
	"go.uber.org/zap"
)

// 调试模式运行参数（协议固定 30 秒，本期不开放任意高频配置）。
const (
	DebugIntervalSeconds     = 30
	DebugDefaultDurationSec  = 3600  // 每次开启默认 60 分钟
	DebugMinDurationSec      = 300   // 最短 5 分钟
	DebugMaxDurationSec      = 14400 // 最长 4 小时
	DebugMaxConcurrentDevices = 20   // 同时开启调试的设备数上限
	debugStartAckTimeout     = 90 * time.Second
	debugSampleStaleAfter    = 75 * time.Second
	debugCoordinatorInterval = 30 * time.Second
)

// DebugCommandSetDebugTelemetry 设备命令：切换心跳采样周期（V2 协议，args=[enabled, interval, duration]）。
const DebugCommandSetDebugTelemetry = "set_debug_telemetry"

// DeviceDebugService 单设备调试会话：权限、状态机、命令调度、有界样本查询。
type DeviceDebugService struct {
	repo         *repository.DeviceRepository
	permChecker  *PermChecker
	deviceSrvURL string
	internalKey  string
	httpClient   *http.Client
}

func NewDeviceDebugService(repo *repository.DeviceRepository, permChecker *PermChecker, deviceSrvURL, internalKey string) *DeviceDebugService {
	return &DeviceDebugService{
		repo:         repo,
		permChecker:  permChecker,
		deviceSrvURL: deviceSrvURL,
		internalKey:  internalKey,
		httpClient:   &http.Client{Timeout: 10 * time.Second},
	}
}

// authorize 查看类访问：登录 + 数据归属（系统管理员放行）。
func (s *DeviceDebugService) authorize(ctx context.Context, userID int64, isAdmin bool, sn string) error {
	if isAdmin {
		return nil
	}
	if !s.repo.HasDataPermission(ctx, userID, sn) {
		return apperr.Forbidden("permission denied")
	}
	return nil
}

// GetSession 查询设备当前/最近一次调试会话与在线状态。
func (s *DeviceDebugService) GetSession(ctx context.Context, userID int64, isAdmin bool, sn string) (*model.DeviceDebugSession, bool, error) {
	if err := s.authorize(ctx, userID, isAdmin, sn); err != nil {
		return nil, false, err
	}
	sess, err := s.repo.GetActiveDebugSession(ctx, sn)
	if err != nil {
		return nil, false, fmt.Errorf("get active debug session: %w", err)
	}
	if sess == nil {
		sess, err = s.repo.GetLatestDebugSession(ctx, sn)
		if err != nil {
			return nil, false, fmt.Errorf("get latest debug session: %w", err)
		}
	}
	online, err := s.repo.IsDeviceDebugOnline(ctx, sn)
	if err != nil {
		return nil, false, err
	}
	return sess, online, nil
}

// StartSession 开启调试：幂等（同 request_id）、并发安全（部分唯一索引）、离线快速失败。
// 返回值 conflict=true 表示同设备已有占用中会话（resp 携带现有会话）。
func (s *DeviceDebugService) StartSession(ctx context.Context, userID int64, isAdmin bool, sn string, durationSeconds int, requestID, source string) (sess *model.DeviceDebugSession, conflict bool, err error) {
	if !isAdmin {
		if s.permChecker == nil || !s.permChecker.CheckPermission(userID, "devices", "control") || !s.repo.HasDataPermission(ctx, userID, sn) {
			return nil, false, apperr.Forbidden("permission denied")
		}
	}

	if durationSeconds <= 0 {
		durationSeconds = DebugDefaultDurationSec
	}
	if durationSeconds < DebugMinDurationSec || durationSeconds > DebugMaxDurationSec {
		return nil, false, apperr.BadRequestf("duration_seconds must be between %d and %d", DebugMinDurationSec, DebugMaxDurationSec)
	}
	if source != model.DebugSourceWeb && source != model.DebugSourceApp {
		source = model.DebugSourceWeb
	}

	// 幂等：同 request_id 直接返回既有会话。
	// 空 request_id 必须服务端兜底生成：UNIQUE(device_sn, request_id) 会让
	// 第二条 ('sn','') 插入撞 23505，被误判为「已有进行中的会话」永久 409。
	if requestID == "" {
		requestID = generateTaskID()
	}
	if existing, err := s.repo.GetDebugSessionByRequest(ctx, sn, requestID); err == nil && existing != nil {
		return existing, false, nil
	}
	// 并发：已有占用中会话 → 返回现有会话并标记冲突
	if existing, err := s.repo.GetActiveDebugSession(ctx, sn); err == nil && existing != nil {
		return existing, true, nil
	}
	// 全局并发上限
	if n, err := s.repo.CountOccupyingDebugSessions(ctx); err == nil && n >= DebugMaxConcurrentDevices {
		return nil, false, apperr.Conflict("调试设备数已达上限，请稍后重试")
	}

	// 设备必须在线：调试命令绝不进入离线延迟队列，过期才送达会造成意外高频上报
	online, err := s.repo.IsDeviceDebugOnline(ctx, sn)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, false, apperr.NotFound("device not found")
		}
		return nil, false, fmt.Errorf("check device online: %w", err)
	}
	if !online {
		return nil, false, apperr.Conflict("设备离线，无法开启调试")
	}

	now := time.Now().UTC()
	// 先生成并随会话持久化 task_id，再发送命令：命令回执按 task_id 定位会话，
	// 若回执早于回填到达会漏匹配（会话卡 starting 直至误判 failed）。
	taskID := generateTaskID()
	sess = &model.DeviceDebugSession{
		DeviceSN:        sn,
		RequestID:       requestID,
		Status:          model.DebugSessionStarting,
		IntervalSeconds: DebugIntervalSeconds,
		DurationSeconds: durationSeconds,
		StartedAt:       now,
		ExpiresAt:       now.Add(time.Duration(durationSeconds) * time.Second),
		RequestedBy:     userID,
		Source:          source,
		StartTaskID:     taskID,
	}
	if err := s.repo.CreateDebugSession(ctx, sess); err != nil {
		if err == repository.ErrDebugSessionConflict {
			if existing, gerr := s.repo.GetActiveDebugSession(ctx, sn); gerr == nil && existing != nil {
				return existing, true, nil
			}
			return nil, false, apperr.Conflict("该设备已有进行中的调试会话")
		}
		return nil, false, fmt.Errorf("create debug session: %w", err)
	}

	if _, serr := s.sendDebugCommand(ctx, sn, 1, DebugIntervalSeconds, durationSeconds, taskID); serr != nil {
		_ = s.repo.FinalizeDebugSession(ctx, sess.ID,
			[]string{model.DebugSessionStarting}, model.DebugSessionFailed, "命令下发失败: "+serr.Error())
		logger.Warn("debug start command failed", zap.String("sn", sn), zap.Error(serr))
		return nil, false, apperr.Conflict("命令下发失败: " + serr.Error())
	}
	sess.StartTaskID = taskID

	logger.Info("device debug session starting",
		zap.String("sn", sn), zap.Int64("session_id", sess.ID),
		zap.String("task_id", taskID), zap.Int("duration", durationSeconds), zap.String("source", source))
	return sess, false, nil
}

// StopSession 关闭调试：幂等；离线时不排队停止命令，设备侧 TTL 到期自恢复默认周期。
func (s *DeviceDebugService) StopSession(ctx context.Context, userID int64, isAdmin bool, sn string, sessionID int64) (*model.DeviceDebugSession, error) {
	if !isAdmin {
		if s.permChecker == nil || !s.permChecker.CheckPermission(userID, "devices", "control") || !s.repo.HasDataPermission(ctx, userID, sn) {
			return nil, apperr.Forbidden("permission denied")
		}
	}
	sess, err := s.repo.GetDebugSessionByID(ctx, sn, sessionID)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, apperr.NotFound("debug session not found")
		}
		return nil, fmt.Errorf("get debug session: %w", err)
	}
	if model.IsDebugSessionTerminal(sess.Status) {
		return sess, nil
	}

	// 与开启同理：先持久化停止 task_id 再发送，保证回执可达会话。
	stopTaskID := generateTaskID()
	if err := s.repo.MarkDebugSessionStopping(ctx, sess.ID, stopTaskID); err != nil {
		return nil, fmt.Errorf("mark stopping: %w", err)
	}
	sess.Status = model.DebugSessionStopping
	sess.StopTaskID = stopTaskID

	if _, serr := s.sendDebugCommand(ctx, sn, 0, DebugIntervalSeconds, 0, stopTaskID); serr != nil {
		// 停止命令失败不回滚：会话保持 stopping，协调循环在 expires_at 兜底置 expired；
		// 设备侧 TTL 同样会自行恢复默认周期。
		logger.Warn("debug stop command failed", zap.String("sn", sn), zap.Error(serr))
	}
	return sess, nil
}

// GetSamples 有界查询调试曲线样本。windowMinutes 限 5..240；样本窗口被会话
// started_at 下界约束，不允许任意历史区间回放。
func (s *DeviceDebugService) GetSamples(ctx context.Context, userID int64, isAdmin bool, sn string, sessionID int64, windowMinutes int, after string, limit int) (items []model.DebugSamplePoint, nextCursor string, sess *model.DeviceDebugSession, err error) {
	if err := s.authorize(ctx, userID, isAdmin, sn); err != nil {
		return nil, "", nil, err
	}
	if windowMinutes <= 0 {
		windowMinutes = 60
	}
	if windowMinutes < 5 {
		windowMinutes = 5
	}
	if windowMinutes > 240 {
		windowMinutes = 240
	}
	if limit <= 0 {
		limit = 200
	}
	if limit > 200 {
		limit = 200
	}

	if sessionID > 0 {
		sess, err = s.repo.GetDebugSessionByID(ctx, sn, sessionID)
	} else {
		sess, err = s.repo.GetActiveDebugSession(ctx, sn)
		if err == nil && sess == nil {
			sess, err = s.repo.GetLatestDebugSession(ctx, sn)
		}
	}
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, "", nil, apperr.NotFound("debug session not found")
		}
		return nil, "", nil, fmt.Errorf("get debug session: %w", err)
	}
	if sess == nil {
		return []model.DebugSamplePoint{}, "", nil, nil
	}

	now := time.Now().UTC()
	from := now.Add(-time.Duration(windowMinutes) * time.Minute)
	if sess.StartedAt.Add(-2 * time.Minute).After(from) {
		from = sess.StartedAt.Add(-2 * time.Minute)
	}
	to := now

	var afterTime *time.Time
	var afterHash string
	if after != "" {
		parts := strings.SplitN(after, "|", 2)
		if t, perr := time.Parse(time.RFC3339Nano, parts[0]); perr == nil {
			afterTime = &t
			if len(parts) == 2 {
				afterHash = parts[1]
			}
		}
	}

	items, nextCursor, err = s.repo.GetDebugSamples(ctx, sn, from, to, afterTime, afterHash, limit)
	if err != nil {
		return nil, "", nil, fmt.Errorf("get debug samples: %w", err)
	}
	return items, nextCursor, sess, nil
}

// HandleCommandResult 命令回执推进状态机（由 internal/device-cmd-result 调用）。
// status 为命令日志状态：success/acknowledged/executing/failed；
// 仅 success 与 failed 是终态结论，acknowledged/executing 不改变会话状态。
func (s *DeviceDebugService) HandleCommandResult(ctx context.Context, taskID, status, message string) {
	if taskID == "" || s == nil {
		return
	}
	sess, err := s.repo.GetDebugSessionByTaskID(ctx, taskID)
	if err != nil {
		if err != pgx.ErrNoRows {
			logger.Warn("debug session lookup by task failed", zap.String("task_id", taskID), zap.Error(err))
		}
		return
	}
	switch {
	case sess.StartTaskID == taskID && sess.Status == model.DebugSessionStarting && status == "success":
		// 命令已确认；active 以首条新样本落库为准（协调循环刷新 last_sample_at 后
		// 由 ReapStale 兜底），回执成功先进入 active，避免固件回执先于样本时长时间停留 starting。
		_ = s.repo.FinalizeDebugSession(ctx, sess.ID,
			[]string{model.DebugSessionStarting}, model.DebugSessionActive, "")
	case sess.StartTaskID == taskID && sess.Status == model.DebugSessionStarting && status == "failed":
		_ = s.repo.FinalizeDebugSession(ctx, sess.ID,
			[]string{model.DebugSessionStarting}, model.DebugSessionFailed, "设备拒绝: "+message)
	case sess.StopTaskID == taskID && sess.Status == model.DebugSessionStopping && status == "success":
		_ = s.repo.FinalizeDebugSession(ctx, sess.ID,
			[]string{model.DebugSessionStopping}, model.DebugSessionStopped, "")
	}
}

// RunCoordinator 协调循环：样本新鲜度刷新、starting 超时、active 中断、到期收口（含补发停止命令）。
func (s *DeviceDebugService) RunCoordinator(ctx context.Context, done <-chan struct{}) {
	ticker := time.NewTicker(debugCoordinatorInterval)
	defer ticker.Stop()
	for {
		select {
		case <-done:
			return
		case <-ticker.C:
			s.coordinateOnce(ctx)
		}
	}
}

func (s *DeviceDebugService) coordinateOnce(ctx context.Context) {
	cctx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()

	if _, err := s.repo.RefreshDebugSampleTimes(cctx); err != nil {
		logger.Warn("debug sample refresh failed", zap.Error(err))
	}
	if reaps, err := s.repo.ReapStaleStartingSessions(cctx, debugStartAckTimeout); err != nil {
		logger.Warn("debug starting reap failed", zap.Error(err))
	} else if len(reaps) > 0 {
		logger.Info("debug starting sessions timed out", zap.Int("count", len(reaps)))
	}
	if reaps, err := s.repo.ReapStaleActiveSessions(cctx, debugSampleStaleAfter); err != nil {
		logger.Warn("debug active reap failed", zap.Error(err))
	} else if len(reaps) > 0 {
		logger.Info("debug active sessions interrupted", zap.Int("count", len(reaps)))
	}

	expired, err := s.repo.ExpireDebugSessions(cctx)
	if err != nil {
		logger.Warn("debug expire failed", zap.Error(err))
		return
	}
	for _, reap := range expired {
		// 到期前仍处于 active/stopping 的会话补发停止命令（best-effort，离线即放弃）
		if reap.Status == model.DebugSessionActive || reap.Status == model.DebugSessionStopping {
			sctx, scancel := context.WithTimeout(ctx, 8*time.Second)
			if _, err := s.sendDebugCommand(sctx, reap.DeviceSN, 0, DebugIntervalSeconds, 0, generateTaskID()); err != nil {
				logger.Warn("debug expiry stop command failed",
					zap.String("sn", reap.DeviceSN), zap.Error(err))
			}
			scancel()
		}
	}
}

// sendDebugCommand 下发 set_debug_telemetry（V2 命令，args=[enabled, interval, duration]）。
// taskID 由调用方生成并已随会话持久化（回执按其定位会话）。
// 复用既有审计表 device_cmd_logs；503（离线）直接报错，绝不入离线队列。
func (s *DeviceDebugService) sendDebugCommand(ctx context.Context, sn string, enabled, intervalSeconds, durationSeconds int, taskID string) (string, error) {
	if s.deviceSrvURL == "" {
		return "", fmt.Errorf("device server URL not configured")
	}

	paramsJSON := "{}"
	if err := s.repo.InsertCommandLog(ctx, sn, taskID, DebugCommandSetDebugTelemetry, paramsJSON); err != nil {
		return "", fmt.Errorf("persist command audit log: %w", err)
	}

	body, err := json.Marshal(map[string]interface{}{
		"command": DebugCommandSetDebugTelemetry,
		"params":  map[string]interface{}{},
		"task_id": taskID,
		"v":       2,
		"t":       time.Now().Unix(),
		"cmd":     DebugCommandSetDebugTelemetry,
		"args":    []int{enabled, intervalSeconds, durationSeconds},
		"expires_at": time.Now().Add(5 * time.Minute).Unix(),
	})
	if err != nil {
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "marshal command failed")
		return "", fmt.Errorf("marshal command: %w", err)
	}

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
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "发送失败: "+err.Error())
		return "", fmt.Errorf("send command to device server: %w", err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)

	if resp.StatusCode == http.StatusServiceUnavailable {
		// 设计要求：调试命令离线明确失败，不转 queued
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", "设备离线，调试命令不入队")
		return "", fmt.Errorf("device offline")
	}
	if resp.StatusCode >= http.StatusBadRequest {
		_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "failed", fmt.Sprintf("Device Server 返回 %d", resp.StatusCode))
		return "", fmt.Errorf("device server returned status %d", resp.StatusCode)
	}

	_ = s.repo.UpdateCommandLogStatus(ctx, taskID, "sent", "调试命令已发送")
	logger.Info("debug telemetry command sent",
		zap.String("sn", sn), zap.String("task_id", taskID),
		zap.Int("enabled", enabled), zap.Int("interval", intervalSeconds))
	return taskID, nil
}
