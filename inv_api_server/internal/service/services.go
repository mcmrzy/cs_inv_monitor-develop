package service

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"inv-api-server/internal/model"
	"inv-api-server/internal/repository"
	"inv-api-server/pkg/jwt"

	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

type UserService struct {
	repo  *repository.UserRepository
	cache *redis.Client
}

func NewUserService(repo *repository.UserRepository, cache *redis.Client) *UserService {
	return &UserService{repo: repo, cache: cache}
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

func (s *UserService) UpdateProfile(ctx context.Context, userID int64, nickname, avatar string) error {
	return s.repo.UpdateProfile(ctx, userID, nickname, avatar)
}

func (s *UserService) UpdateLoginInfo(ctx context.Context, userID int64, ip string) error {
	return s.repo.UpdateLoginInfo(ctx, userID, ip)
}

func (s *UserService) Delete(ctx context.Context, userID int64) error {
	return s.repo.Delete(ctx, userID)
}

type JWTService struct {
	jwt *jwt.JWT
}

func NewJWTService(jwtInstance *jwt.JWT) *JWTService {
	return &JWTService{jwt: jwtInstance}
}

func (s *JWTService) GenerateToken(userID int64, phone string, role int) (string, error) {
	return s.jwt.GenerateToken(userID, phone, role)
}

func (s *JWTService) ParseToken(token string) (*jwt.Claims, error) {
	return s.jwt.ParseToken(token)
}

type SMSService struct {
	cache *redis.Client
}

func NewSMSService(cache *redis.Client) *SMSService {
	return &SMSService{cache: cache}
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

	fmt.Printf("[SMS] Sending code %s to %s for %s\n", code, phone, codeType)

	pipe := s.cache.Pipeline()
	pipe.Set(ctx, key, code, 5*time.Minute)
	pipe.Set(ctx, cooldownKey, "1", 60*time.Second)
	_, err = pipe.Exec(ctx)
	return err
}

func (s *SMSService) VerifyCode(ctx context.Context, phone, code, codeType string) bool {
	key := fmt.Sprintf("sms:%s:%s", phone, codeType)
	storedCode, err := s.cache.Get(ctx, key).Result()
	if err != nil {
		return false
	}

	if storedCode == code {
		return true
	}

	return false
}

func generateCode(length int) string {
	return "123456"
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

func (s *StationService) GetByID(ctx context.Context, id int64) (*model.Station, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *StationService) GetByUserID(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error) {
	return s.repo.GetByUserID(ctx, userID, page, pageSize)
}

func (s *StationService) GetDayData(ctx context.Context, stationID int64, date string) (*model.StationDayData, error) {
	return s.repo.GetDayData(ctx, stationID, date)
}

func (s *StationService) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period string) ([]map[string]interface{}, error) {
	return s.repo.GetStatistics(ctx, stationID, startDate, endDate, period)
}

type DeviceService struct {
	repo        *repository.DeviceRepository
	cache       *redis.Client
	deviceSrvURL string
}

func NewDeviceService(repo *repository.DeviceRepository, cache *redis.Client, deviceSrvURL string) *DeviceService {
	return &DeviceService{
		repo:        repo,
		cache:       cache,
		deviceSrvURL: deviceSrvURL,
	}
}

func (s *DeviceService) GetBySN(ctx context.Context, sn string) (*model.Device, error) {
	return s.repo.GetBySN(ctx, sn)
}

func (s *DeviceService) GetByUserID(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	return s.repo.GetByUserID(ctx, userID, stationID, status, page, pageSize)
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

func (s *DeviceService) GetRealtimeData(ctx context.Context, sn string) (*model.DeviceRealtimeData, error) {
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
	device, err := s.repo.GetBySN(ctx, sn)
	if err != nil || device == nil {
		return false
	}

	if device.UserID == userID {
		return true
	}

	share, err := s.repo.GetShare(ctx, sn, userID)
	if err != nil || share == nil {
		return false
	}

	return true
}

func (s *DeviceService) HasControlPermission(ctx context.Context, userID int64, sn string) bool {
	device, err := s.repo.GetBySN(ctx, sn)
	if err != nil || device == nil {
		return false
	}

	if device.UserID == userID {
		return true
	}

	share, err := s.repo.GetShare(ctx, sn, userID)
	if err != nil || share == nil {
		return false
	}

	return share.Permission == "control"
}

func (s *DeviceService) GetParams(ctx context.Context, sn string) (map[string]interface{}, error) {
	return s.repo.GetParams(ctx, sn)
}

func (s *DeviceService) UpdateParams(ctx context.Context, sn string, params map[string]interface{}) error {
	if err := s.repo.UpdateParams(ctx, sn, params); err != nil {
		return err
	}

	return s.SendCommand(ctx, sn, "set_params", params)
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

func (s *DeviceService) Share(ctx context.Context, sn string, ownerID int64, phone, permission string) error {
	return s.repo.Share(ctx, sn, ownerID, phone, permission)
}

func (s *DeviceService) CancelShare(ctx context.Context, shareID, ownerID int64) error {
	return s.repo.CancelShare(ctx, shareID, ownerID)
}

func (s *DeviceService) GetShares(ctx context.Context, sn string) ([]*model.DeviceShare, error) {
	return s.repo.GetShares(ctx, sn)
}

func (s *DeviceService) ScanLocalNetwork(ctx context.Context, userID int64) ([]*model.Device, error) {
	return []*model.Device{}, nil
}

func (s *DeviceService) StartOTA(ctx context.Context, sn string, firmwareID int64) error {
	return s.repo.StartOTA(ctx, sn, firmwareID)
}

func (s *DeviceService) GetOTAStatus(ctx context.Context, sn string) (map[string]interface{}, error) {
	return s.repo.GetOTAStatus(ctx, sn)
}

type AlarmService struct {
	repo *repository.AlarmRepository
}

func NewAlarmService(repo *repository.AlarmRepository) *AlarmService {
	return &AlarmService{repo: repo}
}

func (s *AlarmService) List(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Alarm, int64, error) {
	return s.repo.List(ctx, userID, stationID, status, page, pageSize)
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

type StatisticsService struct {
	deviceRepo   *repository.DeviceRepository
	stationRepo  *repository.StationRepository
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

type NotifyService struct {
	repo  *repository.NotifyRepository
	cache *redis.Client
}

func NewNotifyService(repo *repository.NotifyRepository, cache *redis.Client) *NotifyService {
	return &NotifyService{repo: repo, cache: cache}
}

func (s *NotifyService) GetSettings(ctx context.Context, userID int64) (*model.UserNotifySetting, error) {
	return s.repo.GetSettings(ctx, userID)
}

func (s *NotifyService) UpdateSettings(ctx context.Context, userID int64, settings map[string]interface{}) error {
	return s.repo.UpdateSettings(ctx, userID, settings)
}

func (s *NotifyService) GetMessages(ctx context.Context, userID int64, msgType string, page, pageSize int) ([]*model.Message, int64, error) {
	return s.repo.GetMessages(ctx, userID, msgType, page, pageSize)
}

func (s *NotifyService) MarkMessageRead(ctx context.Context, ids []int64, userID int64) error {
	return s.repo.MarkMessageRead(ctx, ids, userID)
}

func (s *NotifyService) GetUnreadCount(ctx context.Context, userID int64) (int64, error) {
	return s.repo.GetUnreadCount(ctx, userID)
}

func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(bytes), err
}

func CheckPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

func ValidatePassword(password string) error {
	if len(password) < 6 || len(password) > 20 {
		return errors.New("password must be 6-20 characters")
	}
	return nil
}

func ValidatePhone(phone string) error {
	if len(phone) != 11 {
		return errors.New("invalid phone number")
	}
	return nil
}

func ValidateRole(role int) error {
	if role < 1 || role > 5 {
		return sql.ErrNoRows
	}
	return nil
}
