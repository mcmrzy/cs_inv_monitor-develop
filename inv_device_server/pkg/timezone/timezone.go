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

// DateRangeInTimezone 在指定时区中计算日期范围的 UTC 起止时间
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
