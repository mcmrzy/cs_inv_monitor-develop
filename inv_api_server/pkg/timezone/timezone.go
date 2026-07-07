// Package timezone 提供统一的时区管理功能
// 核心原则: 后端存储和传输统一使用 UTC, 前端根据站点时区进行本地化显示
package timezone

import (
	"fmt"
	"net/url"
	"sync"
	"time"
)

// 常用时区常量
const (
	UTC          = "UTC"
	AsiaShanghai = "Asia/Shanghai"
)

// 预定义常用时区映射 (按UTC偏移量从大到小排序，用于前端展示选择列表)
var CommonTimezones = []TimezoneInfo{
	{ID: "Pacific/Auckland", Label: "UTC+12 奥克兰", Offset: "+12:00"},
	{ID: "Australia/Sydney", Label: "UTC+10 悉尼", Offset: "+10:00"},
	{ID: "Asia/Tokyo", Label: "UTC+9 东京", Offset: "+09:00"},
	{ID: "Asia/Seoul", Label: "UTC+9 首尔", Offset: "+09:00"},
	{ID: "Asia/Shanghai", Label: "UTC+8 上海", Offset: "+08:00"},
	{ID: "Asia/Singapore", Label: "UTC+8 新加坡", Offset: "+08:00"},
	{ID: "Asia/Kuala_Lumpur", Label: "UTC+8 吉隆坡", Offset: "+08:00"},
	{ID: "Asia/Manila", Label: "UTC+8 马尼拉", Offset: "+08:00"},
	{ID: "Asia/Ho_Chi_Minh", Label: "UTC+7 胡志明", Offset: "+07:00"},
	{ID: "Asia/Bangkok", Label: "UTC+7 曼谷", Offset: "+07:00"},
	{ID: "Asia/Jakarta", Label: "UTC+7 雅加达", Offset: "+07:00"},
	{ID: "Asia/Kolkata", Label: "UTC+5:30 加尔各答", Offset: "+05:30"},
	{ID: "Asia/Dubai", Label: "UTC+4 迪拜", Offset: "+04:00"},
	{ID: "Asia/Riyadh", Label: "UTC+3 利雅得", Offset: "+03:00"},
	{ID: "Asia/Tehran", Label: "UTC+3:30 德黑兰", Offset: "+03:30"},
	{ID: "Europe/Moscow", Label: "UTC+3 莫斯科", Offset: "+03:00"},
	{ID: "Europe/Athens", Label: "UTC+2 雅典", Offset: "+02:00"},
	{ID: "Europe/Berlin", Label: "UTC+1 柏林", Offset: "+01:00"},
	{ID: "Europe/Paris", Label: "UTC+1 巴黎", Offset: "+01:00"},
	{ID: "Europe/Madrid", Label: "UTC+1 马德里", Offset: "+01:00"},
	{ID: "Africa/Lagos", Label: "UTC+1 拉各斯", Offset: "+01:00"},
	{ID: "Europe/London", Label: "UTC+0 伦敦", Offset: "+00:00"},
	{ID: "America/New_York", Label: "UTC-5 纽约", Offset: "-05:00"},
	{ID: "America/Chicago", Label: "UTC-6 芝加哥", Offset: "-06:00"},
	{ID: "America/Denver", Label: "UTC-7 丹佛", Offset: "-07:00"},
	{ID: "America/Los_Angeles", Label: "UTC-8 洛杉矶", Offset: "-08:00"},
	{ID: "America/Mexico_City", Label: "UTC-6 墨西哥城", Offset: "-06:00"},
	{ID: "America/Sao_Paulo", Label: "UTC-3 圣保罗", Offset: "-03:00"},
}

// TimezoneInfo 时区信息
type TimezoneInfo struct {
	ID     string `json:"id"`
	Label  string `json:"label"`
	Offset string `json:"offset"`
}

// 缓存已加载的 *time.Location 避免重复加载
var (
	locCache   = make(map[string]*time.Location)
	locCacheMu sync.RWMutex
)

// LoadLocation 加载时区, 带缓存和回退
func LoadLocation(tz string) *time.Location {
	if tz == "" {
		tz = AsiaShanghai
	}

	locCacheMu.RLock()
	if loc, ok := locCache[tz]; ok {
		locCacheMu.RUnlock()
		return loc
	}
	locCacheMu.RUnlock()

	loc, err := time.LoadLocation(tz)
	if err != nil {
		// 回退到 UTC
		loc = time.UTC
	}

	locCacheMu.Lock()
	locCache[tz] = loc
	locCacheMu.Unlock()

	return loc
}

// ToUTC 将指定时区的时间转换为 UTC
// t: 输入时间 (可能是任意时区)
// 返回: UTC 时间
func ToUTC(t time.Time) time.Time {
	return t.UTC()
}

// FromUnixToUTC 将 Unix 时间戳转换为 UTC 时间
func FromUnixToUTC(ts int64) time.Time {
	return time.Unix(ts, 0).UTC()
}

// InTimezone 将 UTC 时间转换为指定时区的本地时间
func InTimezone(utcTime time.Time, tz string) time.Time {
	loc := LoadLocation(tz)
	return utcTime.In(loc)
}

// FormatInTimezone 将 UTC 时间按指定时区格式化输出
func FormatInTimezone(utcTime time.Time, tz string, layout string) string {
	if layout == "" {
		layout = time.RFC3339
	}
	return InTimezone(utcTime, tz).Format(layout)
}

// NowUTC 获取当前 UTC 时间
func NowUTC() time.Time {
	return time.Now().UTC()
}

// NowInTimezone 获取指定时区的当前时间
func NowInTimezone(tz string) time.Time {
	loc := LoadLocation(tz)
	return time.Now().In(loc)
}

// ValidateTimezone 验证时区字符串是否有效
func ValidateTimezone(tz string) error {
	if tz == "" {
		return fmt.Errorf("timezone cannot be empty")
	}
	_, err := time.LoadLocation(tz)
	if err != nil {
		return fmt.Errorf("invalid timezone %q: %w", tz, err)
	}
	return nil
}

// EncodeTimezoneForURL 将时区字符串进行 URL 编码 (用于天气 API 等外部调用)
func EncodeTimezoneForURL(tz string) string {
	return url.PathEscape(tz)
}

// GetTimezoneList 获取所有可用时区列表 (供前端选择)
func GetTimezoneList() []TimezoneInfo {
	return CommonTimezones
}

// DateRangeInTimezone 在指定时区中计算日期范围的 UTC 起止时间
// 例如: 在 Asia/Shanghai 中查询 "2024-01-01" 到 "2024-01-02"
// 返回的 start 是 2023-12-31T16:00:00Z, end 是 2024-01-01T16:00:00Z
func DateRangeInTimezone(dateStr string, tz string) (time.Time, error) {
	loc := LoadLocation(tz)
	t, err := time.ParseInLocation("2006-01-02", dateStr, loc)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid date %q: %w", dateStr, err)
	}
	return t.UTC(), nil
}

// TodayInTimezone 获取指定时区的今天日期字符串 (格式: 2006-01-02)
func TodayInTimezone(tz string) string {
	return NowInTimezone(tz).Format("2006-01-02")
}
