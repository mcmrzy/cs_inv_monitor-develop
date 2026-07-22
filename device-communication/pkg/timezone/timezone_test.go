package timezone

import (
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestLoadLocation(t *testing.T) {
	tests := []struct {
		name     string
		tz       string
		expected string
	}{
		{"UTC", "UTC", "UTC"},
		{"Asia/Shanghai", "Asia/Shanghai", "Asia/Shanghai"},
		{"America/New_York", "America/New_York", "America/New_York"},
		{"empty fallback", "", "Asia/Shanghai"},
		{"invalid fallback", "Invalid/Timezone", "UTC"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			loc := LoadLocation(tt.tz)
			assert.NotNil(t, loc)
			assert.Equal(t, tt.expected, loc.String())
		})
	}
}

func TestLoadLocation_Cache(t *testing.T) {
	// 第一次加载
	loc1 := LoadLocation("Asia/Shanghai")
	// 第二次应从缓存返回
	loc2 := LoadLocation("Asia/Shanghai")
	assert.Same(t, loc1, loc2)
}

func TestLoadLocation_Concurrent(t *testing.T) {
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			loc := LoadLocation("Asia/Shanghai")
			assert.NotNil(t, loc)
		}()
	}
	wg.Wait()
}

func TestToUTC(t *testing.T) {
	shanghai := LoadLocation("Asia/Shanghai")
	local := time.Date(2024, 1, 1, 12, 0, 0, 0, shanghai)
	utc := ToUTC(local)
	assert.Equal(t, time.UTC, utc.Location())
	assert.Equal(t, 2024, utc.Year())
	assert.Equal(t, time.January, utc.Month())
	assert.Equal(t, 1, utc.Day())
	assert.Equal(t, 4, utc.Hour())
}

func TestFromUnixToUTC(t *testing.T) {
	ts := int64(1700000000)
	utc := FromUnixToUTC(ts)
	assert.Equal(t, time.UTC, utc.Location())
	assert.Equal(t, ts, utc.Unix())
}

func TestInTimezone(t *testing.T) {
	utc := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	local := InTimezone(utc, "Asia/Shanghai")
	assert.Equal(t, "Asia/Shanghai", local.Location().String())
	assert.Equal(t, 8, local.Hour())
}

func TestFormatInTimezone(t *testing.T) {
	utc := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	formatted := FormatInTimezone(utc, "Asia/Shanghai", "2006-01-02 15:04:05")
	assert.Equal(t, "2024-01-01 08:00:00", formatted)
}

func TestFormatInTimezone_DefaultLayout(t *testing.T) {
	utc := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	formatted := FormatInTimezone(utc, "UTC", "")
	assert.Contains(t, formatted, "2024-01-01T00:00:00")
}

func TestNowUTC(t *testing.T) {
	now := NowUTC()
	assert.Equal(t, time.UTC, now.Location())
	assert.WithinDuration(t, time.Now().UTC(), now, time.Second)
}

func TestNowInTimezone(t *testing.T) {
	now := NowInTimezone("Asia/Shanghai")
	assert.Equal(t, "Asia/Shanghai", now.Location().String())
}

func TestValidateTimezone(t *testing.T) {
	tests := []struct {
		name    string
		tz      string
		wantErr bool
	}{
		{"valid", "Asia/Shanghai", false},
		{"UTC", "UTC", false},
		{"empty", "", true},
		{"invalid", "Not/Real", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateTimezone(tt.tz)
			if tt.wantErr {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestEncodeTimezoneForURL(t *testing.T) {
	encoded := EncodeTimezoneForURL("Asia/Shanghai")
	assert.Equal(t, "Asia%2FShanghai", encoded)

	encoded = EncodeTimezoneForURL("America/New_York")
	assert.Equal(t, "America%2FNew_York", encoded)
}

func TestDateRangeInTimezone(t *testing.T) {
	utc, err := DateRangeInTimezone("2024-01-01", "Asia/Shanghai")
	assert.NoError(t, err)
	assert.Equal(t, time.UTC, utc.Location())
	assert.Equal(t, 2023, utc.Year())
	assert.Equal(t, time.December, utc.Month())
	assert.Equal(t, 31, utc.Day())
	assert.Equal(t, 16, utc.Hour())
}

func TestDateRangeInTimezone_Invalid(t *testing.T) {
	_, err := DateRangeInTimezone("not-a-date", "Asia/Shanghai")
	assert.Error(t, err)
}

func TestTodayInTimezone(t *testing.T) {
	today := TodayInTimezone("UTC")
	assert.Regexp(t, `^\d{4}-\d{2}-\d{2}$`, today)
}

// TestCrossDayBoundary 跨日边界计算
func TestCrossDayBoundary(t *testing.T) {
	// Asia/Shanghai 2024-01-01 23:30 = UTC 2024-01-01 15:30 (同一天)
	shanghai := LoadLocation("Asia/Shanghai")
	local := time.Date(2024, 1, 1, 23, 30, 0, 0, shanghai)
	utc := ToUTC(local)
	assert.Equal(t, 2024, utc.Year())
	assert.Equal(t, time.January, utc.Month())
	assert.Equal(t, 1, utc.Day())

	// Asia/Shanghai 2024-01-01 00:30 = UTC 2023-12-31 16:30 (跨日)
	local = time.Date(2024, 1, 1, 0, 30, 0, 0, shanghai)
	utc = ToUTC(local)
	assert.Equal(t, 2023, utc.Year())
	assert.Equal(t, time.December, utc.Month())
	assert.Equal(t, 31, utc.Day())
}
