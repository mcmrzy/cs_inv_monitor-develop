package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"inv-api-server/internal/config"
	"inv-api-server/pkg/logger"

	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// jpushPushURL 极光推送 Push API v3 端点
const jpushPushURL = "https://api.jpush.cn/v3/push"

// JPushService 封装极光推送 REST API，支持别名定向推送与全量广播。
type JPushService struct {
	enabled      bool
	appKey       string
	masterSecret string
	timeout      int
	dedupTTL     int
	httpClient   *http.Client
	rdb          *redis.Client
}

// NewJPushService 根据配置创建 JPushService。
// 当未启用或 AppKey 为空时，返回 enabled=false 的实例，所有推送方法将直接返回。
func NewJPushService(cfg *config.JPushConfig, rdb *redis.Client) *JPushService {
	if cfg == nil || !cfg.Enabled || cfg.AppKey == "" {
		return &JPushService{enabled: false, rdb: rdb}
	}

	timeout := cfg.Timeout
	if timeout <= 0 {
		timeout = 10
	}

	dedupTTL := cfg.DedupTTL
	if dedupTTL <= 0 {
		dedupTTL = 120
	}

	return &JPushService{
		enabled:      true,
		appKey:       cfg.AppKey,
		masterSecret: cfg.MasterSecret,
		timeout:      timeout,
		dedupTTL:     dedupTTL,
		httpClient:   &http.Client{Timeout: time.Duration(timeout) * time.Second},
		rdb:          rdb,
	}
}

// --- JPush REST API 请求/响应结构 ---

// jpushPayload 对应 JPush Push API v3 请求体
type jpushPayload struct {
	Platform     string            `json:"platform"` // 固定 "all"，同时推送到 Android 和 iOS
	Audience     interface{}       `json:"audience"` // "all" 或 {"alias": [...]}
	Notification jpushNotification `json:"notification"`
	Options      jpushOptions      `json:"options"`
}

type jpushNotification struct {
	Android *jpushPlatformNotify `json:"android,omitempty"`
	IOS     *jpushPlatformNotify `json:"ios,omitempty"`
}

// jpushPlatformNotify 单平台通知内容
type jpushPlatformNotify struct {
	Alert  string            `json:"alert"`
	Title  string            `json:"title,omitempty"`
	Sound  string            `json:"sound,omitempty"`
	Extras map[string]string `json:"extras,omitempty"`
}

type jpushOptions struct {
	TimeToLive     int  `json:"time_to_live"`      // 离线消息保留时长（秒）
	ApnsProduction bool `json:"apns_production"`   // true=生产环境，false=开发环境
}

// jpushSuccessResp JPush 成功响应
type jpushSuccessResp struct {
	Sendno string `json:"sendno"`
	MsgID  string `json:"msg_id"`
}

// jpushErrorResp JPush 错误响应
type jpushErrorResp struct {
	Error struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// pushToJPush 调用极光推送 REST API 发送推送请求。
// aliases 为别名列表；若 audience 设为 "all" 则全量广播。
func (s *JPushService) pushToJPush(audience interface{}, title, content string, extras map[string]string) error {
	notify := &jpushPlatformNotify{
		Alert:  content,
		Title:  title,
		Extras: extras,
	}

	payload := jpushPayload{
		Platform: "all",
		Audience: audience,
		Notification: jpushNotification{
			Android: notify,
			IOS: &jpushPlatformNotify{
				Alert:  content,
				Sound:  "default",
				Extras: extras,
			},
		},
		Options: jpushOptions{
			TimeToLive:     86400,
			ApnsProduction: true,
		},
	}

	jsonBody, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal jpush payload: %w", err)
	}

	// 异步推送使用独立 context，不受请求生命周期影响
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(s.timeout)*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, jpushPushURL, bytes.NewReader(jsonBody))
	if err != nil {
		return fmt.Errorf("create jpush request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	// JPush 使用 HTTP Basic Auth (app_key:master_secret)
	req.SetBasicAuth(s.appKey, s.masterSecret)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("send jpush request: %w", err)
	}
	defer resp.Body.Close()

	// HTTP 状态码非 200，解析 JPush 错误响应
	if resp.StatusCode != http.StatusOK {
		var errResp jpushErrorResp
		if decodeErr := json.NewDecoder(resp.Body).Decode(&errResp); decodeErr == nil && errResp.Error.Message != "" {
			return fmt.Errorf("jpush error: code=%d, message=%s", errResp.Error.Code, errResp.Error.Message)
		}
		return fmt.Errorf("jpush api returned status: %d", resp.StatusCode)
	}

	var success jpushSuccessResp
	if err := json.NewDecoder(resp.Body).Decode(&success); err != nil {
		return fmt.Errorf("decode jpush response: %w", err)
	}

	logger.Debug("JPush notification sent",
		zap.String("sendno", success.Sendno),
		zap.String("msg_id", success.MsgID),
	)
	return nil
}

// SendNotificationAsync 异步向指定用户发送推送通知。
// 使用 Redis SetNX 进行去重：同一 deviceSN + notifyType 在 dedupTTL 秒内仅推送一次。
func (s *JPushService) SendNotificationAsync(
	ctx context.Context,
	userIDs []int64,
	notifyType, deviceSN, title, content string,
) {
	if !s.enabled {
		return
	}

	// Redis 去重检查：SetNX 成功表示窗口内首次推送
	dedupKey := fmt.Sprintf("push:dedup:%s:%s", deviceSN, notifyType)
	ok, err := s.rdb.SetNX(ctx, dedupKey, "1", time.Duration(s.dedupTTL)*time.Second).Result()
	if err != nil {
		logger.Warn("JPush dedup check failed, proceeding with push",
			zap.String("device_sn", deviceSN),
			zap.String("notify_type", notifyType),
			zap.Error(err),
		)
		// Redis 异常不阻断推送，继续执行
	} else if !ok {
		// key 已存在，窗口内已推送过
		logger.Debug("JPush notification skipped (dedup window)",
			zap.String("device_sn", deviceSN),
			zap.String("notify_type", notifyType),
		)
		return
	}

	// 复制参数，避免 goroutine 中引用外部变量被修改
	ids := make([]int64, len(userIDs))
	copy(ids, userIDs)

	go func() {
		// 将 userIDs 转换为 alias 列表 ["user_123", "user_456"]
		aliases := make([]string, 0, len(ids))
		for _, uid := range ids {
			aliases = append(aliases, fmt.Sprintf("user_%d", uid))
		}

		if len(aliases) == 0 {
			logger.Warn("JPush notification skipped: no target users",
				zap.String("device_sn", deviceSN),
				zap.String("notify_type", notifyType),
			)
			return
		}

		extras := map[string]string{
			"notify_type": notifyType,
			"device_sn":   deviceSN,
		}

		audience := map[string][]string{"alias": aliases}
		if err := s.pushToJPush(audience, title, content, extras); err != nil {
			logger.Error("JPush notification failed",
				zap.String("device_sn", deviceSN),
				zap.String("notify_type", notifyType),
				zap.Int("user_count", len(aliases)),
				zap.Error(err),
			)
		}
	}()
}

// SendBroadcastAsync 异步向全平台全用户广播推送（供系统公告使用）。
func (s *JPushService) SendBroadcastAsync(
	ctx context.Context,
	title, content string,
	extras map[string]string,
) {
	if !s.enabled {
		return
	}

	// 复制 extras，避免 goroutine 中引用外部变量被修改
	extrasCopy := make(map[string]string, len(extras))
	for k, v := range extras {
		extrasCopy[k] = v
	}

	go func() {
		// audience 设为 "all"，全平台全用户推送
		if err := s.pushToJPush("all", title, content, extrasCopy); err != nil {
			logger.Error("JPush broadcast failed",
				zap.String("title", title),
				zap.Error(err),
			)
		}
	}()
}

// IsEnabled 返回推送服务是否启用
func (s *JPushService) IsEnabled() bool {
	return s.enabled
}
