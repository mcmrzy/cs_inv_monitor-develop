package service

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/jwt"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

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

func (s *StationService) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period string) ([]map[string]interface{}, error) {
	return s.repo.GetStatistics(ctx, stationID, startDate, endDate, period)
}

type DeviceService struct {
	repo         *repository.DeviceRepository
	cache        *redis.Client
	modelRepo    *repository.ModelRepository
	deviceSrvURL string
}

func NewDeviceService(repo *repository.DeviceRepository, cache *redis.Client, modelRepo *repository.ModelRepository, deviceSrvURL string) *DeviceService {
	return &DeviceService{
		repo:         repo,
		cache:        cache,
		modelRepo:    modelRepo,
		deviceSrvURL: deviceSrvURL,
	}
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

func (s *DeviceService) GetStationRealtimeSummary(ctx context.Context, stationID int64) (float64, float64, error) {
	return s.repo.GetStationRealtimeSummary(ctx, stationID)
}

func (s *DeviceService) GetStationEnergySummary(ctx context.Context, stationID int64) (float64, float64) {
	return s.repo.GetStationEnergySummary(ctx, stationID)
}

func (s *DeviceService) GetStationYearEnergy(ctx context.Context, stationID int64) float64 {
	return s.repo.GetStationYearEnergy(ctx, stationID)
}

func (s *DeviceService) GetStationTodayEnergy(ctx context.Context, stationID int64) (float64, error) {
	return s.repo.GetStationTodayEnergy(ctx, stationID)
}

func (s *DeviceService) GetStationPowerBreakdown(ctx context.Context, stationID int64) (float64, float64, float64, float64, float64) {
	return s.repo.GetStationPowerBreakdown(ctx, stationID)
}

func (s *DeviceService) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	return s.repo.GetRealtimeData(ctx, sn)
}

func (s *DeviceService) EnsureDevice(ctx context.Context, sn string) error {
	return s.repo.EnsureDevice(ctx, sn)
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

func (s *DeviceService) HasPermission(ctx context.Context, userID int64, sn string) bool {
	return s.repo.HasDataPermission(ctx, userID, sn)
}

func (s *DeviceService) HasControlPermission(ctx context.Context, userID int64, sn string) bool {
	return s.repo.HasDataPermission(ctx, userID, sn)
}

// 系统级命令白名单，不受型号控制字段校验限制
var systemCommands = map[string]bool{
	"get_params":   true,
	"set_params":   true,
	"batch_config": true,
	"reset":        true,
	"restart":      true,
	"ota":          true,
}

func (s *DeviceService) ValidateControlCommand(ctx context.Context, sn string, command string) error {
	// 系统级命令始终允许
	if systemCommands[command] {
		return nil
	}

	modelID, err := s.modelRepo.GetModelIDByDeviceSN(ctx, sn)
	if err != nil {
		return fmt.Errorf("查询设备型号失败: %w", err)
	}
	if modelID == 0 {
		// 设备未配置型号，允许所有命令（向后兼容）
		return nil
	}

	controlFields, err := s.modelRepo.GetControlFieldsByModelID(ctx, modelID)
	if err != nil {
		return fmt.Errorf("查询控制字段失败: %w", err)
	}

	if len(controlFields) == 0 {
		// 型号未配置控制字段，允许所有命令（向后兼容）
		return nil
	}

	allowed := make(map[string]bool)
	for _, f := range controlFields {
		allowed[f.FieldKey] = true
	}

	if !allowed[command] {
		return fmt.Errorf("命令 %s 不在设备型号允许的控制字段中", command)
	}

	return nil
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

	var filtered []string
	for _, sn := range sns {
		if allowedSet[sn] {
			filtered = append(filtered, sn)
		}
	}
	return filtered, nil
}

func (s *DeviceService) SendCommand(ctx context.Context, sn, cmdType string, params map[string]interface{}) error {
	return s.repo.SendCommand(ctx, sn, cmdType, params)
}

func (s *DeviceService) GetHistoryData(ctx context.Context, sn, startDate, endDate, period string) ([]map[string]interface{}, error) {
	return s.repo.GetHistoryData(ctx, sn, startDate, endDate, period)
}

func (s *DeviceService) GetStatistics(ctx context.Context, sn, startDate, endDate, period string) (map[string]interface{}, error) {
	return s.repo.GetStatistics(ctx, sn, startDate, endDate, period)
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

func (s *DeviceService) GetUnbindRequests(ctx context.Context, page, pageSize int) ([]map[string]interface{}, int64, error) {
	return s.repo.GetUnbindRequests(ctx, page, pageSize)
}

func (s *DeviceService) ApproveUnbind(ctx context.Context, id, reviewerID int64, comment string) error {
	return s.repo.ApproveUnbind(ctx, id, reviewerID, comment)
}

func (s *DeviceService) RejectUnbind(ctx context.Context, id, reviewerID int64, comment string) error {
	return s.repo.RejectUnbind(ctx, id, reviewerID, comment)
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

func (s *StatisticsService) GetOverview(ctx context.Context, userID int64) (map[string]interface{}, error) {
	return s.deviceRepo.GetOverview(ctx, userID)
}

func (s *StatisticsService) GetTrend(ctx context.Context, userID int64, period string) ([]map[string]interface{}, error) {
	return s.deviceRepo.GetTrend(ctx, userID, period)
}
