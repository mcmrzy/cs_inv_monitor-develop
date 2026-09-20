package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"inv-api-server/pkg/timezone"
)

// 遥测历史读取粒度。raw 返回 device_telemetry_3min 的原始行；
// hour/day/week/month 先按时间桶聚合再分页，避免长区间把整段原始行拉进内存。
const (
	TelemetryGranularityRaw   = "raw"
	TelemetryGranularityHour  = "hour"
	TelemetryGranularityDay   = "day"
	TelemetryGranularityWeek  = "week"
	TelemetryGranularityMonth = "month"
)

// telemetryCounterFieldPattern 匹配累计型计数器（日/总电量、运行时长、循环次数）。
// 聚合时计数器取桶内最大值（即桶结束时的表底），瞬时量取平均值。
const telemetryCounterFieldPattern = `(^daily_|^total_|_energy$|_energy_daily$|_energy_total$|^runtime_hours$|^battery_cycle_count$|_time$|_time_total$)`

// telemetryNumericLiteralPattern 判断 jsonb 文本值能否安全转 numeric。
// 直接 ::numeric 遇到 "charging" 这类字符串会让整条查询报错，所以先用正则筛掉。
const telemetryNumericLiteralPattern = `^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$`

// telemetryNonMetricKeys 是聚合时排除的元数据列：标识与质量位取平均没有意义，
// 混进结果还会污染前端字段列表。
const telemetryNonMetricKeys = `('device_sn','received_at','event_time','time','topic','protocol_version','quality_flags','sequence_no','data_hash','raw_envelope')`

// NormalizeTelemetryGranularity 把客户端传入的粒度别名收敛到受支持的桶宽。
// 历史调用方传过 hour/day/week/month；未知值一律退回 raw（原始行）。
func NormalizeTelemetryGranularity(granularity string) string {
	switch strings.ToLower(strings.TrimSpace(granularity)) {
	case "hour", "hourly", "1h":
		return TelemetryGranularityHour
	case "day", "daily", "1d":
		return TelemetryGranularityDay
	case "week", "weekly", "1w":
		return TelemetryGranularityWeek
	case "month", "monthly", "1mo":
		return TelemetryGranularityMonth
	default:
		return TelemetryGranularityRaw
	}
}

// normalizeTelemetryTimezone 归一化时区参数：非法值退回 UTC，空值按项目默认（Asia/Shanghai）。
// 返回的字符串直接作为 AT TIME ZONE 的参数，必须是合法的 IANA 名称。
func normalizeTelemetryTimezone(tz string) string {
	return timezone.LoadLocation(tz).String()
}

// telemetryBucketExpression 返回把 event_time 归入本地时区时间桶的 SQL 表达式。
// 用 AT TIME ZONE 往返一次，让 day/week/month 桶按站点本地零点切分，而不是按 UTC 零点。
func telemetryBucketExpression(unitParam, tzParam string) string {
	return fmt.Sprintf("date_trunc(%s, t.event_time AT TIME ZONE %s) AT TIME ZONE %s", unitParam, tzParam, tzParam)
}

// CountTelemetry 返回区间内的行数（raw）或时间桶数（聚合粒度）。
func (r *DeviceRepository) CountTelemetry(ctx context.Context, sn, startTime, endTime, granularity, tz string) (int64, error) {
	granularity = NormalizeTelemetryGranularity(granularity)
	var total int64
	if granularity == TelemetryGranularityRaw {
		err := r.db.QueryRow(ctx, `
			SELECT count(*) FROM device_telemetry_3min t
			WHERE t.device_sn=$1 AND t.event_time >= $2::timestamptz AND t.event_time <= $3::timestamptz`,
			sn, startTime, endTime).Scan(&total)
		return total, err
	}
	err := r.db.QueryRow(ctx, fmt.Sprintf(`
		SELECT count(DISTINCT %s) FROM device_telemetry_3min t
		WHERE t.device_sn=$1 AND t.event_time >= $2::timestamptz AND t.event_time <= $3::timestamptz`,
		telemetryBucketExpression("$4", "$5")),
		sn, startTime, endTime, granularity, normalizeTelemetryTimezone(tz)).Scan(&total)
	return total, err
}

// GetTelemetryPage 读取一页遥测数据。
//
// raw 粒度按 event_time 排序后由数据库 LIMIT/OFFSET 分页；排序键带上 data_hash 兜底，
// 否则同一 event_time 的多条记录（不同 topic 各占一行）在翻页之间顺序不稳定，会重复或漏行。
// 聚合粒度先对时间桶分页，再只对当页的桶做聚合，因此长区间也只读取一页的数据量。
func (r *DeviceRepository) GetTelemetryPage(ctx context.Context, sn, startTime, endTime, granularity, tz string, desc bool, offset, limit int, fields []string) ([]map[string]interface{}, error) {
	granularity = NormalizeTelemetryGranularity(granularity)
	if granularity == TelemetryGranularityRaw {
		return r.getTelemetryRawPage(ctx, sn, startTime, endTime, desc, offset, limit)
	}
	return r.getTelemetryBucketPage(ctx, sn, startTime, endTime, granularity, tz, desc, offset, limit, fields)
}

func (r *DeviceRepository) getTelemetryRawPage(ctx context.Context, sn, startTime, endTime string, desc bool, offset, limit int) ([]map[string]interface{}, error) {
	direction := "ASC"
	if desc {
		direction = "DESC"
	}
	// protocol_version / quality_flags 保留在 JSON 契约里：客户端用它们解释解析器版本与降级样本。
	rows, err := r.db.Query(ctx, fmt.Sprintf(`
		SELECT to_jsonb(t) - 'device_sn' - 'received_at' || jsonb_build_object('time', t.event_time)
		FROM device_telemetry_3min t
		WHERE t.device_sn=$1 AND t.event_time >= $2::timestamptz AND t.event_time <= $3::timestamptz
		ORDER BY t.event_time %s, t.data_hash
		LIMIT $4 OFFSET $5`, direction), sn, startTime, endTime, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]interface{}, 0, limit)
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			return nil, err
		}
		var item map[string]interface{}
		if err := json.Unmarshal(raw, &item); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func (r *DeviceRepository) getTelemetryBucketPage(ctx context.Context, sn, startTime, endTime, granularity, tz string, desc bool, offset, limit int, fields []string) ([]map[string]interface{}, error) {
	direction := "ASC"
	if desc {
		direction = "DESC"
	}
	bucketExpr := telemetryBucketExpression("$4", "$5")

	// 参数：$1 sn, $2 start, $3 end, $4 桶宽, $5 时区, $6 limit, $7 offset,
	// $8 计数器正则, $9 字段白名单（NULL 表示不过滤）。
	// 字段名只作为 jsonb 取值参数出现，不做 SQL 拼接，避免注入。
	query := fmt.Sprintf(`
		WITH page_buckets AS (
			SELECT DISTINCT %s AS bucket
			FROM device_telemetry_3min t
			WHERE t.device_sn=$1 AND t.event_time >= $2::timestamptz AND t.event_time <= $3::timestamptz
			ORDER BY bucket %s
			LIMIT $6 OFFSET $7
		)
		SELECT b.bucket,
		       kv.key,
		       CASE WHEN kv.key ~ $8 THEN max(kv.value::numeric) ELSE avg(kv.value::numeric) END AS value
		FROM page_buckets b
		JOIN device_telemetry_3min t
		  ON t.device_sn=$1
		 AND %s = b.bucket
		 AND t.event_time >= $2::timestamptz AND t.event_time <= $3::timestamptz
		CROSS JOIN LATERAL jsonb_each_text(
			to_jsonb(t) - 'device_sn' - 'received_at' - 'raw_envelope' - 'data_hash' - 'sequence_no') AS kv(key, value)
		WHERE kv.key NOT IN %s
		  AND kv.value ~ '%s'
		  AND ($9::text[] IS NULL OR kv.key = ANY($9::text[]))
		GROUP BY b.bucket, kv.key
		ORDER BY b.bucket %s, kv.key`, bucketExpr, direction, bucketExpr, telemetryNonMetricKeys,
		telemetryNumericLiteralPattern, direction)

	var fieldFilter interface{}
	if len(fields) > 0 {
		fieldFilter = fields
	}
	rows, err := r.db.Query(ctx, query, sn, startTime, endTime, granularity, normalizeTelemetryTimezone(tz),
		limit, offset, telemetryCounterFieldPattern, fieldFilter)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// 同一桶的多个字段合并成一行；查询已按 bucket 排序，故按首次出现顺序即可保持时间序。
	ordered := make([]map[string]interface{}, 0, limit)
	byBucket := make(map[time.Time]map[string]interface{}, limit)
	for rows.Next() {
		var bucket time.Time
		var key string
		var value *float64
		if err := rows.Scan(&bucket, &key, &value); err != nil {
			return nil, err
		}
		item, ok := byBucket[bucket]
		if !ok {
			// 与 raw 路径的 jsonb 时间渲染保持一致（+00:00 而非 Z），两条路径的时间格式相同。
			item = map[string]interface{}{"time": bucket.UTC().Format("2006-01-02T15:04:05.999999-07:00")}
			byBucket[bucket] = item
			ordered = append(ordered, item)
		}
		if value != nil {
			item[key] = *value
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return ordered, nil
}

// TelemetryGranularityForRange 按区间长度挑选图表用的聚合粒度，保证返回点数可控：
// 2 天以内用原始行（≤960 点），14 天以内按小时（≤336 点），再长按天。
func TelemetryGranularityForRange(startTime, endTime string) string {
	start, startErr := time.Parse(time.RFC3339, startTime)
	end, endErr := time.Parse(time.RFC3339, endTime)
	if startErr != nil || endErr != nil || !end.After(start) {
		return TelemetryGranularityRaw
	}
	switch span := end.Sub(start); {
	case span <= 48*time.Hour:
		return TelemetryGranularityRaw
	case span <= 14*24*time.Hour:
		return TelemetryGranularityHour
	default:
		return TelemetryGranularityDay
	}
}
