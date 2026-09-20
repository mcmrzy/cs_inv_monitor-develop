//go:build integration

package repository

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestTelemetryHistoryPagingAndAggregation 覆盖历史数据读取的两条路径：
// raw 分页必须覆盖全部行且翻页不重不漏（同一 event_time 多行时也不能错位）；
// 聚合粒度必须按时间桶合并、瞬时量取均值、累计计数器取桶内最大值。
func TestTelemetryHistoryPagingAndAggregation(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	repo := NewDeviceRepository(pool, nil)

	const sn = "HIST-SN-1"
	start := "2026-03-01T00:00:00Z"
	end := "2026-03-01T06:00:00Z"

	type row struct {
		at      string
		hash    string
		pvPower float64
		dailyPV float64
	}
	rows := []row{
		// 08:00 本地：三行 → pv 均值 200，日电量计数器取最大值 30
		{"2026-03-01T00:00:00Z", "h1", 100, 10},
		{"2026-03-01T00:01:00Z", "h2", 200, 20},
		{"2026-03-01T00:02:00Z", "h3", 300, 30},
		// 09:00 本地：单行
		{"2026-03-01T01:00:00Z", "h4", 400, 40},
		// 10:00 本地：同一 event_time 两行（不同 data_hash）→ pv 均值 600
		{"2026-03-01T02:00:00Z", "aaa", 500, 50},
		{"2026-03-01T02:00:00Z", "zzz", 700, 60},
	}
	for _, r := range rows {
		_, err := pool.Exec(ctx, `
			INSERT INTO device_telemetry_3min
				(device_sn, protocol_version, sequence_no, event_time, data_hash, topic, pv_total_power, daily_pv_energy)
			VALUES ($1, 2, 0, $2::timestamptz, $3, 'heartbeat', $4, $5)`,
			sn, r.at, r.hash, r.pvPower, r.dailyPV)
		require.NoError(t, err)
	}

	total, err := repo.CountTelemetry(ctx, sn, start, end, TelemetryGranularityRaw, "Asia/Shanghai")
	require.NoError(t, err)
	assert.EqualValues(t, len(rows), total, "raw total 应为区间内全部行")

	// raw 分页：逐页取回并按 (time, data_hash) 去重，必须恰好覆盖全部行
	seen := map[string]bool{}
	for offset := 0; offset < len(rows); offset += 2 {
		page, err := repo.GetTelemetryPage(ctx, sn, start, end, "raw", "Asia/Shanghai", false, offset, 2, nil)
		require.NoError(t, err)
		require.NotEmpty(t, page)
		for _, item := range page {
			key := fmt.Sprintf("%v|%v", item["time"], item["data_hash"])
			require.Falsef(t, seen[key], "翻页出现重复行: %s", key)
			seen[key] = true
		}
	}
	assert.Len(t, seen, len(rows), "分页必须覆盖全部行，不重不漏")

	// 降序：最新一行在前
	descPage, err := repo.GetTelemetryPage(ctx, sn, start, end, "raw", "Asia/Shanghai", true, 0, 1, nil)
	require.NoError(t, err)
	require.Len(t, descPage, 1)
	assert.Contains(t, descPage[0]["time"], "2026-03-01T02:00:00")

	// hour 聚合：3 个桶
	hourTotal, err := repo.CountTelemetry(ctx, sn, start, end, TelemetryGranularityHour, "Asia/Shanghai")
	require.NoError(t, err)
	assert.EqualValues(t, 3, hourTotal, "hour 桶数应为 3")

	hourPage, err := repo.GetTelemetryPage(ctx, sn, start, end, TelemetryGranularityHour, "Asia/Shanghai", false, 0, 10, nil)
	require.NoError(t, err)
	require.Len(t, hourPage, 3)
	assert.Contains(t, hourPage[0]["time"], "2026-03-01T00:00:00")
	assert.Contains(t, hourPage[2]["time"], "2026-03-01T02:00:00")

	// 瞬时量取均值，累计计数器取桶内最大值
	assert.InDelta(t, 200.0, hourPage[0]["pv_total_power"], 0.001, "pv_total_power 应为桶内均值")
	assert.InDelta(t, 30.0, hourPage[0]["daily_pv_energy"], 0.001, "daily_pv_energy 应为桶内最大值")
	assert.InDelta(t, 600.0, hourPage[2]["pv_total_power"], 0.001, "同 event_time 多行也应进入同一桶")
	assert.InDelta(t, 60.0, hourPage[2]["daily_pv_energy"], 0.001)

	// 元数据列不得混进聚合结果
	for _, key := range []string{"protocol_version", "quality_flags", "sequence_no", "data_hash", "topic", "event_time"} {
		_, exists := hourPage[0][key]
		assert.Falsef(t, exists, "聚合结果不应包含元数据列 %s", key)
	}

	// 字段白名单只保留 time + 指定字段
	filtered, err := repo.GetTelemetryPage(ctx, sn, start, end, TelemetryGranularityHour, "Asia/Shanghai",
		false, 0, 10, []string{"pv_total_power"})
	require.NoError(t, err)
	require.Len(t, filtered, 3)
	assert.Len(t, filtered[0], 2, "白名单命中时应只返回 time 与所选字段")
	assert.InDelta(t, 200.0, filtered[0]["pv_total_power"], 0.001)

	// 桶分页：每页 1 桶，覆盖 3 个桶
	seenBuckets := map[string]bool{}
	for offset := 0; offset < 3; offset++ {
		page, err := repo.GetTelemetryPage(ctx, sn, start, end, TelemetryGranularityHour, "Asia/Shanghai", false, offset, 1, nil)
		require.NoError(t, err)
		require.Len(t, page, 1)
		seenBuckets[page[0]["time"].(string)] = true
	}
	assert.Len(t, seenBuckets, 3, "桶分页应覆盖全部桶")

	// day 聚合按站点本地零点切分：UTC 00:00-06:00 全部落在本地 2026-03-01
	dayTotal, err := repo.CountTelemetry(ctx, sn, start, end, TelemetryGranularityDay, "Asia/Shanghai")
	require.NoError(t, err)
	assert.EqualValues(t, 1, dayTotal)

	dayPage, err := repo.GetTelemetryPage(ctx, sn, start, end, TelemetryGranularityDay, "Asia/Shanghai", false, 0, 10, nil)
	require.NoError(t, err)
	require.Len(t, dayPage, 1)
	assert.Contains(t, dayPage[0]["time"], "2026-02-28T16:00:00", "本地零点对应 UTC 前一天 16:00")
	assert.InDelta(t, 60.0, dayPage[0]["daily_pv_energy"], 0.001, "日桶计数器取当日最大值")

	// 不同设备互不干扰
	otherTotal, err := repo.CountTelemetry(ctx, "HIST-SN-OTHER", start, end, TelemetryGranularityRaw, "Asia/Shanghai")
	require.NoError(t, err)
	assert.EqualValues(t, 0, otherTotal)
}

func TestNormalizeTelemetryGranularity(t *testing.T) {
	cases := map[string]string{
		"":        TelemetryGranularityRaw,
		"raw":     TelemetryGranularityRaw,
		"3min":    TelemetryGranularityRaw,
		"hour":    TelemetryGranularityHour,
		"HOUR":    TelemetryGranularityHour,
		" day ":   TelemetryGranularityDay,
		"weekly":  TelemetryGranularityWeek,
		"monthly": TelemetryGranularityMonth,
		"bogus":   TelemetryGranularityRaw,
	}
	for input, want := range cases {
		assert.Equalf(t, want, NormalizeTelemetryGranularity(input), "granularity=%q", input)
	}
}

func TestTelemetryGranularityForRange(t *testing.T) {
	base := time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC)
	at := func(d time.Duration) string { return base.Add(d).Format(time.RFC3339) }
	cases := []struct {
		span time.Duration
		want string
	}{
		{time.Hour, TelemetryGranularityRaw},
		{48 * time.Hour, TelemetryGranularityRaw},
		{49 * time.Hour, TelemetryGranularityHour},
		{14 * 24 * time.Hour, TelemetryGranularityHour},
		{15 * 24 * time.Hour, TelemetryGranularityDay},
		{365 * 24 * time.Hour, TelemetryGranularityDay},
	}
	for _, c := range cases {
		assert.Equalf(t, c.want, TelemetryGranularityForRange(at(0), at(c.span)), "span=%s", c.span)
	}
	assert.Equal(t, TelemetryGranularityRaw, TelemetryGranularityForRange("not-a-time", at(time.Hour)))
}
