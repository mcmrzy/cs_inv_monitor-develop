package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseID(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want int64
	}{
		{"valid positive", "42", 42},
		{"zero", "0", 0},
		{"negative", "-1", -1},
		{"large number", "9999999999", 9999999999},
		{"non-numeric", "abc", 0},
		{"empty string", "", 0},
		{"mixed", "12a34", 0},
		{"float", "1.5", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseID(tt.in)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParseInt(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want int
	}{
		{"valid positive", "10", 10},
		{"zero", "0", 0},
		{"negative", "-5", -5},
		{"non-numeric", "abc", 0},
		{"empty", "", 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseInt(tt.in)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestValidateSN(t *testing.T) {
	tests := []struct {
		name string
		sn   string
		want bool
	}{
		{"valid 8 chars", "ABCD1234", true},
		{"valid 16 chars", "ABCDEFGH12345678", true},
		{"valid 32 chars", "ABCDEFGH12345678ABCDEFGH12345678", true},
		{"too short 7 chars", "ABC1234", false},
		{"too long 33 chars", "ABCDEFGH12345678ABCDEFGH123456789", false},
		{"lowercase", "abcd1234", false},
		{"with special chars", "ABCD-1234", false},
		{"empty", "", false},
		{"only letters", "ABCDEFGH", true},
		{"only digits", "12345678", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := validateSN(tt.sn)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetQueryInt(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		queryKey     string
		queryValue   string
		defaultValue int
		want         int
	}{
		{"valid value", "page", "5", 1, 5},
		{"empty value", "page", "", 1, 1},
		{"invalid value", "page", "abc", 1, 1},
		{"zero value", "page", "0", 1, 0},
		{"negative value", "page", "-1", 1, -1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest(http.MethodGet, "/?"+tt.queryKey+"="+tt.queryValue, nil)

			got := getQueryInt(c, tt.queryKey, tt.defaultValue)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetQueryInt64(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		queryKey     string
		queryValue   string
		defaultValue int64
		want         int64
	}{
		{"valid value", "id", "12345", 0, 12345},
		{"empty value", "id", "", 0, 0},
		{"invalid value", "id", "abc", 0, 0},
		{"large value", "id", "9999999999", 0, 9999999999},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest(http.MethodGet, "/?"+tt.queryKey+"="+tt.queryValue, nil)

			got := getQueryInt64(c, tt.queryKey, tt.defaultValue)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParsePagination(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name         string
		query        string
		wantPage     int
		wantPageSize int
	}{
		{"defaults", "", 1, 20},
		{"custom page", "page=3", 3, 20},
		{"custom pageSize", "pageSize=50", 1, 50},
		{"both custom", "page=2&pageSize=10", 2, 10},
		{"page < 1 resets to 1", "page=0", 1, 20},
		{"pageSize < 1 resets to 20", "pageSize=0", 1, 20},
		{"pageSize > 100 capped at 100", "pageSize=200", 1, 100},
		{"invalid page", "page=abc", 1, 20},
		{"invalid pageSize", "pageSize=abc", 1, 20},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest(http.MethodGet, "/?"+tt.query, nil)

			page, pageSize := parsePagination(c)
			assert.Equal(t, tt.wantPage, page)
			assert.Equal(t, tt.wantPageSize, pageSize)
		})
	}
}

func TestParseListTimeParam(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name      string
		rawQuery  string
		wantNil   bool
		wantValue time.Time
		wantErr   bool
	}{
		{"RFC3339 UTC", "lastOnlineStart=2026-01-02T03:04:05Z", false, time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC), false},
		{"datetime format", "lastOnlineStart=2026-01-02%2003%3A04%3A05", false, time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC), false},
		{"plain date", "lastOnlineStart=2026-01-02", false, time.Date(2026, 1, 2, 0, 0, 0, 0, time.UTC), false},
		{"missing param", "", true, time.Time{}, false},
		{"invalid format", "lastOnlineStart=not-a-time", true, time.Time{}, true},
		{"invalid date value", "lastOnlineStart=2026-13-99", true, time.Time{}, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := httptest.NewRecorder()
			c, _ := gin.CreateTestContext(w)
			c.Request = httptest.NewRequest(http.MethodGet, "/?"+tt.rawQuery, nil)

			got, err := parseListTimeParam(c, "lastOnlineStart")
			if tt.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			if tt.wantNil {
				assert.Nil(t, got)
				return
			}
			require.NotNil(t, got)
			assert.True(t, tt.wantValue.Equal(*got), "want %v, got %v", tt.wantValue, *got)
		})
	}
}
