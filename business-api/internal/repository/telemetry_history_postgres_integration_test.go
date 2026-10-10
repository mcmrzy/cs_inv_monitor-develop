//go:build integration

package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTelemetryHistoryRepairsOmittedMappingsBeforeAggregation(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `ALTER TABLE device_telemetry_3min ADD COLUMN IF NOT EXISTS buck1_current REAL, ADD COLUMN IF NOT EXISTS buck2_current REAL, ADD COLUMN IF NOT EXISTS boost_temperature REAL, ADD COLUMN IF NOT EXISTS warning NUMERIC, ADD COLUMN IF NOT EXISTS work_time_total BIGINT, ADD COLUMN IF NOT EXISTS output_energy_daily DOUBLE PRECISION, ADD COLUMN IF NOT EXISTS output_energy_total DOUBLE PRECISION`)
	require.NoError(t, err)
	words := make([]interface{}, 87)
	for i := range words {
		words[i] = 0
	}
	words[3], words[4] = 900, 250
	raw, err := json.Marshal(map[string]interface{}{"v": 3, "data": map[string]interface{}{"run": words}})
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `INSERT INTO device_telemetry_3min (device_sn,protocol_version,sequence_no,event_time,data_hash,topic,raw_envelope,buck1_current,buck2_current,boost_temperature,warning,work_time_total,output_energy_daily,output_energy_total,bms_summary)
		VALUES ('MAP-SN',3,0,'2026-10-10T00:00:00Z','map-test','heartbeat',$1::jsonb,8.45,0,41,4294967296,5400,0.4,12.5,'{"layout":0,"bms_online":1,"capacity_remain":1.25,"soc":0,"mos_temp":3.5}'::jsonb)`, raw)
	require.NoError(t, err)
	repo := NewDeviceRepository(pool, nil)
	for _, granularity := range []string{"raw", "hour"} {
		rows, err := repo.GetTelemetryPage(ctx, "MAP-SN", "2026-10-10T00:00:00Z", "2026-10-10T01:00:00Z", granularity, "UTC", false, 0, 10, nil)
		require.NoError(t, err)
		require.Len(t, rows, 1)
		for key, want := range map[string]float64{"pv1_power": 900, "pv2_power": 250, "pv1_current": 8.45, "pv2_current": 0, "mos_temperature": 41, "runtime_hours": 1.5, "daily_load_energy": 0.4, "total_load_energy": 12.5, "alarm_code": 4294967296, "bms_capacity_remain": 125, "bms_soc": 0, "bms_mos_temp": 35} {
			require.InDelta(t, want, rows[0][key], 1e-5, "%s %s", granularity, key)
		}
		require.Nil(t, rows[0]["ac_power_factor"])
	}
}

func TestL10MappedFieldVisibilityMigration(t *testing.T) {
	pool, cleanup := setupCommandTestDB(t)
	defer cleanup()
	ctx := context.Background()
	_, err := pool.Exec(ctx, `INSERT INTO device_models (model_code,model_name) VALUES ('CS-L10-6K2','L10 mapping fixture') ON CONFLICT (model_code) DO NOTHING;
		INSERT INTO device_model_fields (model_id,field_key,group_code,is_supported,is_visible,show_realtime,show_history)
		SELECT m.id,c.field_key,c.category,false,false,false,false FROM device_models m CROSS JOIN telemetry_field_catalog c
		WHERE m.model_code='CS-L10-6K2' AND c.field_key IN ('pv1_power','pv2_power','pv1_current','pv2_current','mos_temperature','alarm_code','runtime_hours','ac_power_factor','efficiency','pv1_voltage_max')
		ON CONFLICT (model_id,field_key) DO UPDATE SET is_supported=false,is_visible=false,show_realtime=false,show_history=false`)
	require.NoError(t, err)
	read := func(suffix string) []byte {
		sql, err := os.ReadFile(filepath.Join("..", "..", "..", "database", "migrations", "128_l10_v3_mapped_fields."+suffix+".sql"))
		require.NoError(t, err)
		return sql
	}
	_, err = pool.Exec(ctx, string(read("up")))
	require.NoError(t, err)
	var enabled int
	err = pool.QueryRow(ctx, `SELECT count(*) FROM device_model_fields f JOIN device_models m ON m.id=f.model_id WHERE m.model_code='CS-L10-6K2' AND f.field_key IN ('pv1_power','pv2_power','pv1_current','pv2_current','mos_temperature','alarm_code','runtime_hours') AND is_supported AND is_visible AND show_realtime AND show_history`).Scan(&enabled)
	require.NoError(t, err)
	require.Equal(t, 7, enabled)
	var unsupported int
	err = pool.QueryRow(ctx, `SELECT count(*) FROM device_model_fields f JOIN device_models m ON m.id=f.model_id WHERE m.model_code='CS-L10-6K2' AND f.field_key IN ('ac_power_factor','efficiency','pv1_voltage_max') AND is_supported`).Scan(&unsupported)
	require.NoError(t, err)
	require.Zero(t, unsupported)
	_, err = pool.Exec(ctx, string(read("down")))
	require.NoError(t, err)
	_, err = pool.Exec(ctx, string(read("up")))
	require.NoError(t, err)
}

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
