package timezone

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ==================== LoadLocation ====================

func TestLoadLocation_空字符串回退到AsiaShanghai(t *testing.T) {
	loc := LoadLocation("")
	assert.Equal(t, "Asia/Shanghai", loc.String())
}

func TestLoadLocation_有效时区正常加载(t *testing.T) {
	tests := []string{"UTC", "Asia/Shanghai", "America/New_York", "Europe/London"}
	for _, tz := range tests {
		t.Run(tz, func(t *testing.T) {
			loc := LoadLocation(tz)
			assert.NotNil(t, loc)
			assert.Equal(t, tz, loc.String())
		})
	}
}

func TestLoadLocation_无效时区回退到UTC(t *testing.T) {
	loc := LoadLocation("Invalid/Timezone_XYZ")
	assert.Equal(t, time.UTC, loc)
}

func TestLoadLocation_缓存命中返回同一对象(t *testing.T) {
	loc1 := LoadLocation("Asia/Tokyo")
	loc2 := LoadLocation("Asia/Tokyo")
	assert.Same(t, loc1, loc2, "两次加载应返回同一 *Location 对象")
}

// ==================== ToUTC ====================

func TestToUTC_正确转换为UTC(t *testing.T) {
	loc := LoadLocation("Asia/Shanghai")
	// 北京时间 2024-06-15 08:00 = UTC 2024-06-15 00:00
	shanghai := time.Date(2024, 6, 15, 8, 0, 0, 0, loc)
	utc := ToUTC(shanghai)

	assert.Equal(t, 2024, utc.Year())
	assert.Equal(t, time.June, utc.Month())
	assert.Equal(t, 15, utc.Day())
	assert.Equal(t, 0, utc.Hour())
	assert.Equal(t, time.UTC, utc.Location())
}

// ==================== FromUnixToUTC ====================

func TestFromUnixToUTC_正确转换(t *testing.T) {
	ts := int64(1718409600) // 2024-06-15T00:00:00Z
	utc := FromUnixToUTC(ts)

	assert.Equal(t, 2024, utc.Year())
	assert.Equal(t, time.June, utc.Month())
	assert.Equal(t, 15, utc.Day())
	assert.Equal(t, 0, utc.Hour())
	assert.Equal(t, time.UTC, utc.Location())
}

// ==================== InTimezone ====================

func TestInTimezone_正确转换到目标时区(t *testing.T) {
	utc := time.Date(2024, 6, 15, 0, 0, 0, 0, time.UTC)

	shanghai := InTimezone(utc, "Asia/Shanghai")
	assert.Equal(t, 8, shanghai.Hour())

	ny := InTimezone(utc, "America/New_York")
	// 6月是夏令时 EDT = UTC-4
	assert.Equal(t, 20, ny.Hour())
	assert.Equal(t, 14, ny.Day()) // 前一天
}

// ==================== FormatInTimezone ====================

func TestFormatInTimezone_默认RFC3339格式(t *testing.T) {
	utc := time.Date(2024, 6, 15, 8, 30, 0, 0, time.UTC)
	formatted := FormatInTimezone(utc, "Asia/Shanghai", "")

	assert.Contains(t, formatted, "2024-06-15T16:30:00+08:00")
}

func TestFormatInTimezone_自定义格式(t *testing.T) {
	utc := time.Date(2024, 6, 15, 8, 30, 0, 0, time.UTC)
	formatted := FormatInTimezone(utc, "Asia/Shanghai", "2006-01-02 15:04:05")

	assert.Equal(t, "2024-06-15 16:30:00", formatted)
}

// ==================== NowUTC ====================

func TestNowUTC_返回UTC时区(t *testing.T) {
	now := NowUTC()
	assert.Equal(t, time.UTC, now.Location())
}

// ==================== NowInTimezone ====================

func TestNowInTimezone_返回指定时区(t *testing.T) {
	now := NowInTimezone("Asia/Shanghai")
	assert.Equal(t, "Asia/Shanghai", now.Location().String())
}

// ==================== ValidateTimezone ====================

func TestValidateTimezone_有效时区无错误(t *testing.T) {
	tests := []string{"UTC", "Asia/Shanghai", "America/New_York", "Europe/Berlin"}
	for _, tz := range tests {
		t.Run(tz, func(t *testing.T) {
			assert.NoError(t, ValidateTimezone(tz))
		})
	}
}

func TestValidateTimezone_无效时区返回错误(t *testing.T) {
	tests := []struct {
		name string
		tz   string
	}{
		{"空字符串", ""},
		{"不存在的时区", "Invalid/XYZ"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			assert.Error(t, ValidateTimezone(tc.tz))
		})
	}
}

// ==================== EncodeTimezoneForURL ====================

func TestEncodeTimezoneForURL_正确编码(t *testing.T) {
	encoded := EncodeTimezoneForURL("Asia/Shanghai")
	assert.Equal(t, "Asia%2FShanghai", encoded)
}

func TestEncodeTimezoneForURL_无需编码的字符串(t *testing.T) {
	encoded := EncodeTimezoneForURL("UTC")
	assert.Equal(t, "UTC", encoded)
}

// ==================== GetTimezoneList ====================

func TestGetTimezoneList_返回非空列表(t *testing.T) {
	list := GetTimezoneList()
	assert.NotEmpty(t, list)
	assert.Greater(t, len(list), 10)

	// 检查上海时区存在
	found := false
	for _, info := range list {
		if info.ID == "Asia/Shanghai" {
			found = true
			assert.Equal(t, "+08:00", info.Offset)
			break
		}
	}
	assert.True(t, found, "应包含 Asia/Shanghai 时区")
}

func TestGetTimezoneList_每项字段非空(t *testing.T) {
	list := GetTimezoneList()
	for _, info := range list {
		assert.NotEmpty(t, info.ID)
		assert.NotEmpty(t, info.Label)
		assert.NotEmpty(t, info.Offset)
	}
}

// ==================== DateRangeInTimezone ====================

func TestDateRangeInTimezone_正确计算UTC起始时间(t *testing.T) {
	// Asia/Shanghai UTC+8
	// "2024-01-01" 在上海 = 2023-12-31T16:00:00Z
	utcStart, err := DateRangeInTimezone("2024-01-01", "Asia/Shanghai")
	require.NoError(t, err)

	assert.Equal(t, 2023, utcStart.Year())
	assert.Equal(t, time.December, utcStart.Month())
	assert.Equal(t, 31, utcStart.Day())
	assert.Equal(t, 16, utcStart.Hour())
	assert.Equal(t, time.UTC, utcStart.Location())
}

func TestDateRangeInTimezone_无效日期返回错误(t *testing.T) {
	_, err := DateRangeInTimezone("not-a-date", "Asia/Shanghai")
	assert.Error(t, err)
}

func TestDateRangeInTimezone_UTC时区不偏移(t *testing.T) {
	utcStart, err := DateRangeInTimezone("2024-06-15", "UTC")
	require.NoError(t, err)

	assert.Equal(t, 2024, utcStart.Year())
	assert.Equal(t, time.June, utcStart.Month())
	assert.Equal(t, 15, utcStart.Day())
	assert.Equal(t, 0, utcStart.Hour())
}

// ==================== TodayInTimezone ====================

func TestTodayInTimezone_返回合法日期格式(t *testing.T) {
	today := TodayInTimezone("Asia/Shanghai")
	_, err := time.Parse("2006-01-02", today)
	assert.NoError(t, err)
}

// ==================== CommonTimezones 数据完整性 ====================

func TestCommonTimezones_偏移格式正确(t *testing.T) {
	for _, info := range CommonTimezones {
		// Offset 应为 "+HH:MM" 或 "-HH:MM" 格式
		assert.Regexp(t, `^[+-]\d{2}:\d{2}$`, info.Offset, "时区 %s 偏移格式不正确: %s", info.ID, info.Offset)
	}
}
