package service

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// generateTaskID 生成唯一的任务ID
func generateTaskID() string {
	id, err := uuid.NewV7()
	if err != nil {
		return uuid.NewString()
	}
	return id.String()
}

// jitterSeconds returns a random offset in [0, max) seconds for cache TTL jitter.
// This prevents cache stampede from synchronized expiry across multiple keys.
func jitterSeconds(max int) int {
	if max <= 0 {
		return 0
	}
	n, err := rand.Int(rand.Reader, big.NewInt(int64(max)))
	if err != nil {
		return max / 2 // fallback to midpoint
	}
	return int(n.Int64())
}

type UserService struct {
	repo  *repository.UserRepository
	cache *redis.Client
}

func NewUserService(repo *repository.UserRepository, cache *redis.Client) *UserService {
	return &UserService{repo: repo, cache: cache}
}

func (s *UserService) Cache() *redis.Client {
	return s.cache
}

func (s *UserService) GetByID(ctx context.Context, id int64) (*model.User, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *UserService) GetByPhone(ctx context.Context, phone string) (*model.User, error) {
	return s.repo.GetByPhone(ctx, phone)
}

func (s *UserService) GetByEmail(ctx context.Context, email string) (*model.User, error) {
	return s.repo.GetByEmail(ctx, email)
}

func (s *UserService) GetByNickname(ctx context.Context, nickname string) (*model.User, error) {
	return s.repo.GetByNickname(ctx, nickname)
}

func (s *UserService) Create(ctx context.Context, user *model.User) error {
	return s.repo.Create(ctx, user)
}

func (s *UserService) UpdatePassword(ctx context.Context, userID int64, passwordHash string) error {
	return s.repo.UpdatePassword(ctx, userID, passwordHash)
}

func (s *UserService) UpdateProfile(ctx context.Context, userID int64, nickname, avatar, timezone string) error {
	return s.repo.UpdateProfile(ctx, userID, nickname, avatar, timezone)
}

func (s *UserService) UpdateLoginInfo(ctx context.Context, userID int64, ip string) error {
	return s.repo.UpdateLoginInfo(ctx, userID, ip)
}

func (s *UserService) LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string) {
	s.repo.LogAudit(ctx, operatorID, operatorName, action, resourceType, resourceID, detail, ip)
}

func (s *UserService) Delete(ctx context.Context, userID int64) error {
	return s.repo.Delete(ctx, userID)
}

type JWTService struct {
	jwt   *jwt.JWT
	cache *redis.Client
}

func NewJWTService(jwtInstance *jwt.JWT, cache *redis.Client) *JWTService {
	return &JWTService{jwt: jwtInstance, cache: cache}
}

func (s *JWTService) GenerateToken(userID int64, phone string, role int) (string, string, error) {
	return s.jwt.GenerateToken(userID, phone, role)
}

func (s *JWTService) ParseToken(token string) (*jwt.Claims, error) {
	return s.jwt.ParseToken(token)
}

func (s *JWTService) StoreRefreshToken(ctx context.Context, userID int64, refreshToken string, expireTime time.Duration) error {
	key := fmt.Sprintf("refresh_token:%d:%s", userID, refreshToken)
	return s.cache.Set(ctx, key, "1", expireTime).Err()
}

func (s *JWTService) ValidateRefreshToken(ctx context.Context, userID int64, refreshToken string) bool {
	key := fmt.Sprintf("refresh_token:%d:%s", userID, refreshToken)
	exists, err := s.cache.Exists(ctx, key).Result()
	return err == nil && exists > 0
}

func (s *JWTService) RevokeRefreshToken(ctx context.Context, userID int64, refreshToken string) error {
	key := fmt.Sprintf("refresh_token:%d:%s", userID, refreshToken)
	return s.cache.Del(ctx, key).Err()
}

// SwapRefreshToken atomically validates the old refresh token and stores the new one using a Lua script.
// Returns true if the swap succeeded, false if the old token was already used/revoked.
func (s *JWTService) SwapRefreshToken(ctx context.Context, userID int64, oldToken, newToken string, expireTime time.Duration) (bool, error) {
	oldKey := fmt.Sprintf("refresh_token:%d:%s", userID, oldToken)
	newKey := fmt.Sprintf("refresh_token:%d:%s", userID, newToken)

	script := redis.NewScript(`
		if redis.call("EXISTS", KEYS[1]) == 1 then
			redis.call("DEL", KEYS[1])
			redis.call("SET", KEYS[2], "1", "PX", ARGV[1])
			return 1
		else
			return 0
		end
	`)

	result, err := script.Run(ctx, s.cache, []string{oldKey, newKey}, expireTime.Milliseconds()).Int()
	if err != nil {
		return false, err
	}
	return result == 1, nil
}

func (s *JWTService) RevokeAllUserTokens(ctx context.Context, userID int64) error {
	pattern := fmt.Sprintf("refresh_token:%d:*", userID)
	keys, err := s.cache.Keys(ctx, pattern).Result()
	if err != nil {
		return err
	}
	if len(keys) > 0 {
		return s.cache.Del(ctx, keys...).Err()
	}
	return nil
}

func (s *JWTService) AddToBlacklist(ctx context.Context, jti string, expireTime time.Duration) error {
	key := fmt.Sprintf("token_blacklist:%s", jti)
	return s.cache.Set(ctx, key, "1", expireTime).Err()
}

func (s *JWTService) IsBlacklisted(ctx context.Context, jti string) bool {
	key := fmt.Sprintf("token_blacklist:%s", jti)
	exists, err := s.cache.Exists(ctx, key).Result()
	return err == nil && exists > 0
}

func (s *JWTService) GetJTI(claims *jwt.Claims) string {
	return s.jwt.GetJTI(claims)
}

type SMSService struct {
	cache    *redis.Client
	provider SMSProvider
}

func NewSMSService(cache *redis.Client, provider SMSProvider) *SMSService {
	return &SMSService{cache: cache, provider: provider}
}

func (s *SMSService) SendCode(ctx context.Context, phone, codeType string) error {
	key := fmt.Sprintf("sms:%s:%s", phone, codeType)
	cooldownKey := fmt.Sprintf("sms:%s:%s:cooldown", phone, codeType)

	exists, err := s.cache.Exists(ctx, cooldownKey).Result()
	if err != nil {
		return err
	}

	if exists > 0 {
		ttl, _ := s.cache.TTL(ctx, cooldownKey).Result()
		return fmt.Errorf("请等待 %d 秒后再发送", int(ttl.Seconds()))
	}

	code := generateCode(6)

	logger.Debug("SMS code generated", zap.String("phone", maskPhone(phone)), zap.String("type", codeType))

	if s.provider != nil {
		if err := s.provider.Send(ctx, phone, code); err != nil {
			logger.Warn("SMS send failed, code still stored locally", zap.String("phone", maskPhone(phone)), zap.Error(err))
		}
	}

	pipe := s.cache.Pipeline()
	pipe.Set(ctx, key, code, 5*time.Minute)
	pipe.Set(ctx, cooldownKey, "1", 60*time.Second)
	_, err = pipe.Exec(ctx)
	return err
}

func (s *SMSService) VerifyCode(ctx context.Context, phone, code, codeType string) bool {
	key := fmt.Sprintf("sms:%s:%s", phone, codeType)
	failKey := fmt.Sprintf("sms:%s:%s:fail", phone, codeType)

	storedCode, err := s.cache.Get(ctx, key).Result()
	if err != nil {
		return false
	}

	// 检查验证码尝试次数
	failCount, _ := s.cache.Get(ctx, failKey).Int()
	if failCount >= 5 {
		return false
	}

	if storedCode == code {
		pipe := s.cache.Pipeline()
		pipe.Del(ctx, key)
		pipe.Del(ctx, failKey)
		pipe.Exec(ctx)
		return true
	}

	// 记录失败次数
	s.cache.Incr(ctx, failKey)
	s.cache.Expire(ctx, failKey, 5*time.Minute)
	return false
}

func generateCode(length int) string {
	code := make([]byte, length)
	for i := range code {
		n, _ := rand.Int(rand.Reader, big.NewInt(10))
		code[i] = byte('0' + n.Int64())
	}
	return string(code)
}

func maskPhone(phone string) string {
	if len(phone) < 7 {
		return "***"
	}
	return phone[:3] + "****" + phone[len(phone)-4:]
}

func maskEmail(email string) string {
	at := -1
	for i := 0; i < len(email); i++ {
		if email[i] == '@' {
			at = i
			break
		}
	}
	if at <= 1 {
		return "***"
	}
	return email[:1] + "***" + email[at:]
}

type StationService struct {
	repo *repository.StationRepository
}

func NewStationService(repo *repository.StationRepository) *StationService {
	return &StationService{repo: repo}
}

func (s *StationService) Create(ctx context.Context, station *model.Station) error {
	return s.repo.Create(ctx, station)
}

func (s *StationService) Update(ctx context.Context, station *model.Station) error {
	return s.repo.Update(ctx, station)
}

func (s *StationService) Delete(ctx context.Context, id int64) error {
	return s.repo.Delete(ctx, id)
}

func (s *StationService) Assign(ctx context.Context, id int64, userID int64) error {
	return s.repo.Assign(ctx, id, userID)
}

func (s *StationService) GetByID(ctx context.Context, id int64) (*model.Station, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *StationService) GetByUserID(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error) {
	return s.repo.GetByUserID(ctx, userID, page, pageSize)
}

func (s *StationService) GetAll(ctx context.Context, page, pageSize int) ([]*model.Station, int64, error) {
	return s.repo.GetAll(ctx, page, pageSize)
}

func (s *StationService) GetDayData(ctx context.Context, stationID int64, date string) (*model.StationDayData, error) {
	return s.repo.GetDayData(ctx, stationID, date)
}

func (s *StationService) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period, tz string) ([]map[string]interface{}, error) {
	return s.repo.GetStatistics(ctx, stationID, startDate, endDate, period, tz)
}

type DeviceService struct {
	repo                *repository.DeviceRepository
	cache               *redis.Client
	modelRepo           *repository.ModelRepository
	permChecker         *PermChecker
	deviceSrvURL        string
	internalKey         string
	httpClient          *http.Client
	db                  *pgxpool.Pool
	limitChecker        *DynamicLimitChecker
	preconditionChecker *PreconditionChecker
}

func NewDeviceService(repo *repository.DeviceRepository, cache *redis.Client, modelRepo *repository.ModelRepository, permChecker *PermChecker, deviceSrvURL string, internalKey string, db *pgxpool.Pool) *DeviceService {
	s := &DeviceService{
		repo:         repo,
		cache:        cache,
		modelRepo:    modelRepo,
		permChecker:  permChecker,
		deviceSrvURL: deviceSrvURL,
		internalKey:  internalKey,
		db:           db,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        50,
				MaxIdleConnsPerHost: 20,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
	s.limitChecker = NewDynamicLimitChecker(cache, db)
	s.preconditionChecker = NewPreconditionChecker(cache)
	return s
}

func (s *DeviceService) GetBySN(ctx context.Context, sn string) (*model.Device, error) {
	return s.repo.GetBySN(ctx, sn)
}

func (s *DeviceService) GetByUserID(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	return s.repo.GetByUserID(ctx, userID, stationID, status, page, pageSize)
}

func (s *DeviceService) GetAll(ctx context.Context, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	return s.repo.GetAll(ctx, stationID, status, page, pageSize)
}

func (s *DeviceService) GetByStationID(ctx context.Context, stationID int64) ([]*model.Device, error) {
	return s.repo.GetByStationID(ctx, stationID)
}

func (s *DeviceService) GetStationRealtimeSummary(ctx context.Context, stationID int64, tz string) (float64, float64, error) {
	return s.repo.GetStationRealtimeSummary(ctx, stationID, tz)
}

func (s *DeviceService) GetStationEnergySummary(ctx context.Context, stationID int64, tz string) (float64, float64) {
	return s.repo.GetStationEnergySummary(ctx, stationID, tz)
}

func (s *DeviceService) GetStationYearEnergy(ctx context.Context, stationID int64, tz string) float64 {
	return s.repo.GetStationYearEnergy(ctx, stationID, tz)
}

func (s *DeviceService) GetStationTodayEnergy(ctx context.Context, stationID int64, tz string) (float64, error) {
	return s.repo.GetStationTodayEnergy(ctx, stationID, tz)
}

func (s *DeviceService) GetStationPowerBreakdown(ctx context.Context, stationID int64) (float64, float64, float64, float64, float64) {
	return s.repo.GetStationPowerBreakdown(ctx, stationID)
}

func (s *DeviceService) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	return s.repo.GetRealtimeData(ctx, sn)
}

// BatchGetRealtimeData fetches realtime data for multiple devices in a single
// Redis Pipeline round-trip, eliminating N+1 queries in device list endpoints.
func (s *DeviceService) BatchGetRealtimeData(ctx context.Context, sns []string) (map[string]map[string]interface{}, error) {
	return s.repo.BatchGetRealtimeData(ctx, sns)
}

func (s *DeviceService) EnsureDevice(ctx context.Context, sn string) error {
	return s.repo.EnsureDevice(ctx, sn)
}

// Create creates a new device with the specified fields.
func (s *DeviceService) Create(ctx context.Context, sn, model string, ratedPower *float64, firmwareArm, firmwareEsp string) error {
	return s.repo.Create(ctx, sn, model, ratedPower, firmwareArm, firmwareEsp)
}

func (s *DeviceService) Bind(ctx context.Context, sn string, userID, stationID int64) error {
	return s.repo.Bind(ctx, sn, userID, stationID)
}

func (s *DeviceService) Unbind(ctx context.Context, sn string) error {
	return s.repo.Unbind(ctx, sn)
}

func (s *DeviceService) AddToStation(ctx context.Context, sn string, stationID int64) error {
	return s.repo.AddToStation(ctx, sn, stationID)
}

func (s *DeviceService) RemoveFromStation(ctx context.Context, sn string) error {
	return s.repo.RemoveFromStation(ctx, sn)
}

func (s *DeviceService) HasPermission(ctx context.Context, userID int64, sn string) bool {
	return s.repo.HasDataPermission(ctx, userID, sn)
}

func (s *DeviceService) HasControlPermission(ctx context.Context, userID int64, sn string) bool {
	// 先检查 RBAC devices:control 权限
	if s.permChecker != nil && !s.permChecker.CheckPermission(userID, "devices", "control") {
		return false
	}
	// 再检查数据归属
	return s.repo.HasDataPermission(ctx, userID, sn)
}

func (s *DeviceService) ValidateControlCommand(ctx context.Context, sn string, command string) error {
	found, enabled, err := s.modelRepo.CommandCapability(ctx, sn, command)
	if err != nil {
		return fmt.Errorf("query command capability: %w", err)
	}
	if !found {
		return fmt.Errorf("命令 %s 不在设备型号允许的控制命令中", command)
	}
	if !enabled {
		return fmt.Errorf("命令 %s 已被禁用", command)
	}
	return nil
}

// CheckCommandPermission performs fine-grained permission_code validation for a specific command.
// If the command has no permission_code configured, the check is skipped (backward compatible).
// The permission_code format is "resource_action" (e.g. "device_control_basic"),
// split on the last underscore to get (resource, action).
func (s *DeviceService) CheckCommandPermission(ctx context.Context, userID int64, sn, commandCode string) error {
	permCode, err := s.modelRepo.GetCommandPermissionCode(ctx, sn, commandCode)
	if err != nil {
		return fmt.Errorf("query command permission code: %w", err)
	}
	if permCode == "" {
		// 命令未配置权限码，跳过细粒度检查（向后兼容）
		return nil
	}
	// 将权限码拆分为 (resource, action) 二元组
	// 例如 "device_control_basic" → resource="device_control", action="basic"
	idx := strings.LastIndex(permCode, "_")
	if idx <= 0 || idx == len(permCode)-1 {
		return fmt.Errorf("invalid permission_code format: %s", permCode)
	}
	resource, action := permCode[:idx], permCode[idx+1:]
	if s.permChecker != nil && !s.permChecker.CheckPermission(userID, resource, action) {
		return fmt.Errorf("缺少权限: %s", permCode)
	}
	return nil
}

// GetControlCapabilitiesBySN returns all command capabilities for the device model identified by SN.
func (s *DeviceService) GetControlCapabilitiesBySN(ctx context.Context, sn string) ([]repository.CommandCapability, error) {
	modelID, err := s.modelRepo.GetModelIDByDeviceSN(ctx, sn)
	if err != nil || modelID == 0 {
		return []repository.CommandCapability{}, nil
	}
	return s.modelRepo.GetCommandCapabilitiesByModelID(ctx, modelID)
}

func (s *DeviceService) GetControlFieldsBySN(ctx context.Context, sn string) ([]model.DeviceModelField, error) {
	modelID, err := s.modelRepo.GetModelIDByDeviceSN(ctx, sn)
	if err != nil || modelID == 0 {
		return []model.DeviceModelField{}, nil
	}
	return s.modelRepo.GetControlFieldsByModelID(ctx, modelID)
}

func (s *DeviceService) GetModelFieldsBySN(ctx context.Context, sn string) ([]model.DeviceModelField, error) {
	modelID, err := s.modelRepo.GetModelIDByDeviceSN(ctx, sn)
	if err != nil || modelID == 0 {
		return []model.DeviceModelField{}, nil
	}
	return s.modelRepo.GetFieldsByModelID(ctx, modelID)
}

func (s *DeviceService) FilterByDataPermission(ctx context.Context, userID int64, sns []string) ([]string, error) {
	allowedSNs, err := s.modelRepo.GetUserAllowedSNs(ctx, userID)
	if err != nil {
		return sns, nil
	}

	if len(allowedSNs) == 0 {
		return sns, nil
	}

	allowedSet := make(map[string]bool)
	for _, sn := range allowedSNs {
		allowedSet[sn] = true
	}

	filtered := make([]string, 0)
	for _, sn := range sns {
		if allowedSet[sn] {
			filtered = append(filtered, sn)
		}
	}
	return filtered, nil
}

func (s *DeviceService) SendCommand(ctx context.Context, sn, cmdType string, params map[string]interface{}) (string, error) {
	if s.deviceSrvURL == "" {
		return "", fmt.Errorf("device server URL not configured")
	}

	// 生成唯一任务ID
	taskID := generateTaskID()
	args, hasV2Spec, err := s.modelRepo.BuildCommandArgs(ctx, sn, cmdType, params)
	if err != nil {
		return "", fmt.Errorf("invalid command %s: %w", cmdType, err)
	}

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
		logger.Error("SendCommand HTTP call failed",
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
		return taskID, nil // 命令已排队，可通过 task_id 跟踪
	}

	if resp.StatusCode >= http.StatusBadRequest {
		respBody, _ := io.ReadAll(resp.Body)
		logger.Error("SendCommand failed",
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

	logger.Info("Command sent to device server",
		zap.String("sn", sn), zap.String("cmd", cmdType), zap.String("task_id", taskID))
	return taskID, nil
}

// insertCmdNotification 插入命令发送通知
func (s *DeviceService) insertCmdNotification(ctx context.Context, sn, taskID, cmdType string) {
	if s.repo == nil {
		return
	}
	// 查找设备对应的 user_id 和 station_id
	device, err := s.repo.GetBySN(ctx, sn)
	if err != nil || device == nil {
		return
	}

	cmdLabels := map[string]string{
		"get_params":   "读取参数",
		"set_params":   "设置参数",
		"set_control":  "设置控制",
		"set_alarm":    "告警控制",
		"batch_config": "批量配置",
		"reset":        "重置设备",
		"restart":      "重启设备",
		"ota":          "OTA升级",
	}
	label := cmdLabels[cmdType]
	if label == "" {
		label = cmdType
	}

	title := "控制指令已发送"
	content := fmt.Sprintf("已向设备 %s 发送「%s」指令", sn, label)

	var stationID int64
	if device.StationID != nil {
		stationID = *device.StationID
	}
	_ = s.repo.InsertNotification(ctx, sn, stationID, device.UserID, "cmd_sent", title, content)
}

func (s *DeviceService) GetHistoryData(ctx context.Context, sn, startDate, endDate, period string) ([]map[string]interface{}, error) {
	return s.repo.GetHistoryData(ctx, sn, startDate, endDate, period)
}

func (s *DeviceService) GetStatistics(ctx context.Context, sn, startDate, endDate, period, tz string) (map[string]interface{}, error) {
	return s.repo.GetStatistics(ctx, sn, startDate, endDate, period, tz)
}

func (s *DeviceService) GetControlState(ctx context.Context, sn string) (map[string]interface{}, error) {
	return s.repo.GetControlState(ctx, sn)
}

func (s *DeviceService) ScanLocalNetwork(ctx context.Context, userID int64) ([]*model.Device, error) {
	return []*model.Device{}, nil
}

func (s *DeviceService) GetCommandHistory(ctx context.Context, sn string, page, pageSize int) ([]map[string]interface{}, int64, error) {
	return s.repo.GetCommandHistory(ctx, sn, page, pageSize)
}

func (s *DeviceService) GetTelemetryData(ctx context.Context, sn, startTime, endTime, granularity string) ([]map[string]interface{}, error) {
	return s.repo.GetTelemetryData(ctx, sn, startTime, endTime, granularity)
}

func (s *DeviceService) GetLifecycleHistory(ctx context.Context, sn string, page, pageSize int) ([]map[string]interface{}, int64, error) {
	return s.repo.GetLifecycleHistory(ctx, sn, page, pageSize)
}

func (s *DeviceService) Delete(ctx context.Context, sn string) error {
	return s.repo.Delete(ctx, sn)
}

func (s *DeviceService) Update(ctx context.Context, sn string, model string, ratedPower *float64, firmwareArm string, firmwareEsp string) error {
	return s.repo.Update(ctx, sn, model, ratedPower, firmwareArm, firmwareEsp)
}

func (s *DeviceService) RequestUnbind(ctx context.Context, deviceSN string, requestedBy int64, reason string) (int64, error) {
	return s.repo.RequestUnbind(ctx, deviceSN, requestedBy, reason)
}

func (s *DeviceService) GetUnbindRequests(ctx context.Context, page, pageSize int) ([]map[string]interface{}, int64, error) {
	return s.repo.GetUnbindRequests(ctx, page, pageSize)
}

func (s *DeviceService) ApproveUnbind(ctx context.Context, id, reviewerID int64, comment string) error {
	return s.repo.ApproveUnbind(ctx, id, reviewerID, comment)
}

func (s *DeviceService) RejectUnbind(ctx context.Context, id, reviewerID int64, comment string) error {
	return s.repo.RejectUnbind(ctx, id, reviewerID, comment)
}

// UpdateInstallerID 更新设备的安装商ID
func (s *DeviceService) UpdateInstallerID(ctx context.Context, sn string, installerID int64) error {
	var id *int64
	if installerID > 0 {
		id = &installerID
	}
	return s.repo.UpdateInstallerID(ctx, sn, id)
}

// BatchUpdateInstallerID 批量更新设备的安装商ID
func (s *DeviceService) BatchUpdateInstallerID(ctx context.Context, sns []string, installerID int64) error {
	return s.repo.BatchUpdateInstallerID(ctx, sns, installerID)
}

type AlarmService struct {
	repo *repository.AlarmRepository
}

func NewAlarmService(repo *repository.AlarmRepository) *AlarmService {
	return &AlarmService{repo: repo}
}

func (s *AlarmService) List(ctx context.Context, params repository.AlarmListParams) ([]*model.Alarm, int64, error) {
	return s.repo.List(ctx, params)
}

func (s *AlarmService) GetByDeviceSN(ctx context.Context, sn string, page, pageSize int) ([]*model.Alarm, int64, error) {
	return s.repo.GetByDeviceSN(ctx, sn, page, pageSize)
}

func (s *AlarmService) GetByID(ctx context.Context, id int64) (*model.Alarm, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *AlarmService) MarkHandled(ctx context.Context, id int64, userID int64) error {
	return s.repo.MarkHandled(ctx, id, userID)
}

func (s *AlarmService) MarkRead(ctx context.Context, ids []int64, userID int64) error {
	return s.repo.MarkRead(ctx, ids, userID)
}

func (s *AlarmService) GetStats(ctx context.Context, userID int64, role ...int) (map[string]interface{}, error) {
	return s.repo.GetStats(ctx, userID, role...)
}

func (s *AlarmService) MarkIgnored(ctx context.Context, id int64) error {
	return s.repo.MarkIgnored(ctx, id)
}

func (s *AlarmService) Delete(ctx context.Context, id int64) error {
	return s.repo.Delete(ctx, id)
}

func (s *AlarmService) ClearAll(ctx context.Context) error {
	return s.repo.ClearAll(ctx)
}

type StatisticsService struct {
	deviceRepo  *repository.DeviceRepository
	stationRepo *repository.StationRepository
}

func NewStatisticsService(deviceRepo *repository.DeviceRepository, stationRepo *repository.StationRepository) *StatisticsService {
	return &StatisticsService{
		deviceRepo:  deviceRepo,
		stationRepo: stationRepo,
	}
}

func (s *StatisticsService) GetOverview(ctx context.Context, userID int64, tz string) (map[string]interface{}, error) {
	return s.deviceRepo.GetOverview(ctx, userID, tz)
}

func (s *StatisticsService) GetTrend(ctx context.Context, userID int64, period, tz string) ([]map[string]interface{}, error) {
	return s.deviceRepo.GetTrend(ctx, userID, period, tz)
}
