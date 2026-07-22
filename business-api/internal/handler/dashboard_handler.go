package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/apperr"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/timezone"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type DashboardHandler struct {
	db  *pgxpool.Pool
	rdb *redis.Client
}

func NewDashboardHandler(db *pgxpool.Pool, rdb *redis.Client) *DashboardHandler {
	return &DashboardHandler{db: db, rdb: rdb}
}

func (h *DashboardHandler) isSuperAdmin(ctx context.Context, userID int64) bool {
	var role int
	err := h.db.QueryRow(ctx, "SELECT role FROM users WHERE id = $1", userID).Scan(&role)
	if err != nil {
		return false
	}
	return role == 0
}

// getUserTimezone 获取用户账号的时区配置（包级共享函数）
func getUserTimezone(ctx context.Context, db *pgxpool.Pool, userID int64) string {
	var tz string
	db.QueryRow(ctx, "SELECT COALESCE(timezone, '') FROM users WHERE id = $1", userID).Scan(&tz)
	if tz == "" {
		return timezone.AsiaShanghai
	}
	if err := timezone.ValidateTimezone(tz); err != nil {
		return timezone.AsiaShanghai
	}
	return tz
}

func (h *DashboardHandler) GetStatistics(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)
	tz := getUserTimezone(ctx, h.db, userID)

	type DeviceStats struct {
		Total   int64 `json:"total"`
		Online  int64 `json:"online"`
		Offline int64 `json:"offline"`
		Fault   int64 `json:"fault"`
	}

	var deviceStats DeviceStats
	var deviceQuery string
	var deviceArgs []interface{}

	if isAdmin {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL
		`
	} else {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL AND user_id = $1
		`
		deviceArgs = append(deviceArgs, userID)
	}

	err := h.db.QueryRow(ctx, deviceQuery, deviceArgs...).Scan(
		&deviceStats.Total, &deviceStats.Online, &deviceStats.Offline, &deviceStats.Fault,
	)
	if err != nil {
		response.HandleError(c, apperr.Internal("get device stats failed", err))
		return
	}

	var todayEnergy float64
	var totalEnergy float64

	var deviceSNs []string
	var snQuery string
	var snArgs []interface{}

	if isAdmin {
		snQuery = `SELECT sn FROM devices WHERE deleted_at IS NULL`
	} else {
		snQuery = `SELECT sn FROM devices WHERE deleted_at IS NULL AND user_id = $1`
		snArgs = append(snArgs, userID)
	}

	snRows, err := h.db.Query(ctx, snQuery, snArgs...)
	if err == nil {
		defer snRows.Close()
		for snRows.Next() {
			var sn string
			if snRows.Scan(&sn) == nil {
				deviceSNs = append(deviceSNs, sn)
			}
		}
	}

	if len(deviceSNs) > 0 {
		todayStr := timezone.TodayInTimezone(tz)
		h.db.QueryRow(ctx, `SELECT COALESCE(SUM(e.pv_energy),0)
			FROM device_energy_day e WHERE e.device_sn=ANY($1) AND e.stat_date=$2::date`,
			deviceSNs, todayStr).Scan(&todayEnergy)
		h.db.QueryRow(ctx, `SELECT COALESCE(SUM(l.total_pv_energy),0)
			FROM device_latest_state l WHERE l.device_sn=ANY($1)`, deviceSNs).Scan(&totalEnergy)
	}

	type RecentAlarm struct {
		ID           int64     `json:"id"`
		DeviceSN     string    `json:"device_sn"`
		AlarmLevel   int       `json:"alarm_level"`
		FaultCode    string    `json:"fault_code"`
		FaultMessage string    `json:"fault_message"`
		OccurredAt   time.Time `json:"occurred_at"`
	}

	var alarmQuery string
	var alarmArgs []interface{}

	if isAdmin {
		alarmQuery = `
			SELECT id, device_sn, alarm_level, fault_code, fault_message, occurred_at
			FROM alarms
			ORDER BY occurred_at DESC
			LIMIT 5
		`
	} else {
		alarmQuery = `
			SELECT a.id, a.device_sn, a.alarm_level, a.fault_code, a.fault_message, a.occurred_at
			FROM alarms a
			JOIN devices d ON d.sn = a.device_sn
			WHERE d.user_id = $1
			ORDER BY a.occurred_at DESC
			LIMIT 5
		`
		alarmArgs = append(alarmArgs, userID)
	}

	rows, err := h.db.Query(ctx, alarmQuery, alarmArgs...)
	var recentAlarms []RecentAlarm
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var alarm RecentAlarm
			if err := rows.Scan(&alarm.ID, &alarm.DeviceSN, &alarm.AlarmLevel, &alarm.FaultCode, &alarm.FaultMessage, &alarm.OccurredAt); err == nil {
				recentAlarms = append(recentAlarms, alarm)
			}
		}
	}
	if recentAlarms == nil {
		recentAlarms = []RecentAlarm{}
	}

	response.Success(c, gin.H{
		"deviceStats":  deviceStats,
		"todayEnergy":  todayEnergy,
		"totalEnergy":  totalEnergy,
		"recentAlarms": recentAlarms,
	})
}

func (h *DashboardHandler) GetDeviceDistribution(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)

	var online, offline, fault int64
	var query string
	var args []interface{}

	if isAdmin {
		query = `
			SELECT 
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL
		`
	} else {
		query = `
			SELECT 
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL AND user_id = $1
		`
		args = append(args, userID)
	}

	err := h.db.QueryRow(ctx, query, args...).Scan(&online, &offline, &fault)
	if err != nil {
		response.HandleError(c, apperr.Internal("get distribution failed", err))
		return
	}

	response.Success(c, gin.H{
		"online":  online,
		"offline": offline,
		"fault":   fault,
	})
}

func (h *DashboardHandler) GetTrend(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)
	tz := getUserTimezone(ctx, h.db, userID)

	trendType := c.DefaultQuery("type", "day")

	var startDate, endDate string
	now := timezone.NowInTimezone(tz)

	switch trendType {
	case "day":
		startDate = now.AddDate(0, 0, -7).Format("2006-01-02")
		endDate = now.Format("2006-01-02")
	case "30days":
		startDate = now.AddDate(0, 0, -30).Format("2006-01-02")
		endDate = now.Format("2006-01-02")
	case "week":
		startDate = now.AddDate(0, 0, -28).Format("2006-01-02")
		endDate = now.Format("2006-01-02")
	case "month":
		startDate = now.AddDate(0, -12, 0).Format("2006-01-02")
		endDate = now.Format("2006-01-02")
	default:
		startDate = now.AddDate(0, 0, -7).Format("2006-01-02")
		endDate = now.Format("2006-01-02")
	}

	log.Printf("[GetTrend] user_id=%d, is_admin=%v, trend_type=%s, start_date=%s, end_date=%s", userID, isAdmin, trendType, startDate, endDate)

	type TrendData struct {
		Date       string  `json:"date"`
		Energy     float64 `json:"energy"`
		Load       float64 `json:"load"`
		Cumulative float64 `json:"cumulative"`
	}

	var query string
	var args []interface{}

	// 将本地日期范围转为 UTC 时间范围用于数据库查询
	loc := timezone.LoadLocation(tz)
	startLocal, _ := time.ParseInLocation("2006-01-02", startDate, loc)
	endLocal, _ := time.ParseInLocation("2006-01-02", endDate, loc)
	startUTCTime := startLocal.UTC()
	endUTCTime := endLocal.AddDate(0, 0, 1).UTC()

	if isAdmin {
		query = `
			SELECT TO_CHAR(e.stat_date,'YYYY-MM-DD'),SUM(e.pv_energy),SUM(e.load_energy),COALESCE(MAX(e.total_pv_energy),0)
			FROM device_energy_day e JOIN devices d ON d.sn=e.device_sn
			WHERE d.deleted_at IS NULL AND e.stat_date >= ($1 AT TIME ZONE $3)::date
			AND e.stat_date < ($2 AT TIME ZONE $3)::date GROUP BY e.stat_date ORDER BY e.stat_date
		`
		args = append(args, startUTCTime, endUTCTime, tz)
	} else {
		query = `
			SELECT TO_CHAR(e.stat_date,'YYYY-MM-DD'),SUM(e.pv_energy),SUM(e.load_energy),COALESCE(MAX(e.total_pv_energy),0)
			FROM device_energy_day e JOIN devices d ON d.sn=e.device_sn
			WHERE d.deleted_at IS NULL
			AND d.sn IN (SELECT sn FROM devices WHERE user_id=$1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id=$1)
			AND e.stat_date >= ($2 AT TIME ZONE $4)::date AND e.stat_date < ($3 AT TIME ZONE $4)::date
			GROUP BY e.stat_date ORDER BY e.stat_date
		`
		args = append(args, userID, startUTCTime, endUTCTime, tz)
	}

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		log.Printf("[GetTrend] query error: user_id=%d, err=%v", userID, err)
		response.HandleError(c, apperr.Internal("获取趋势数据失败", err))
		return
	}
	defer rows.Close()

	dateMap := make(map[string]TrendData)
	for rows.Next() {
		var date string
		var energy, load, cumulative float64
		err := rows.Scan(&date, &energy, &load, &cumulative)
		if err != nil {
			log.Printf("[GetTrend] row scan error: err=%v", err)
			continue
		}
		dateMap[date] = TrendData{
			Date:       date,
			Energy:     energy,
			Load:       load,
			Cumulative: cumulative,
		}
	}
	if rows.Err() != nil {
		log.Printf("[GetTrend] rows error: %v", rows.Err())
	}

	start, _ := time.Parse("2006-01-02", startDate)
	end, _ := time.Parse("2006-01-02", endDate)

	var trendData []TrendData
	var lastCumulative float64
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		dateStr := d.Format("2006-01-02")
		td, ok := dateMap[dateStr]
		if !ok {
			td = TrendData{
				Date:   dateStr,
				Energy: 0,
				Load:   0,
			}
		}
		if td.Cumulative > 0 {
			lastCumulative = td.Cumulative
		} else {
			td.Cumulative = lastCumulative
		}
		trendData = append(trendData, td)
	}

	log.Printf("[GetTrend] returning %d records", len(trendData))

	response.Success(c, trendData)
}

func (h *DashboardHandler) GetBigScreen(c *gin.Context) {
	h.GetStatistics(c)
}

func (h *DashboardHandler) CompareDevices(c *gin.Context) {
	userID := middleware.GetUserID(c)

	devicesParam := c.Query("devices")
	metric := c.DefaultQuery("metric", "total_active_power")
	startTime := c.Query("startTime")
	endTime := c.Query("endTime")

	if devicesParam == "" {
		response.HandleError(c, apperr.BadRequest("missing devices parameter"))
		return
	}

	deviceSNs := strings.Split(devicesParam, ",")

	ctx := c.Request.Context()

	for _, sn := range deviceSNs {
		var count int
		err := h.db.QueryRow(ctx,
			"SELECT COUNT(*) FROM devices WHERE sn = $1 AND user_id = $2 AND deleted_at IS NULL",
			sn, userID).Scan(&count)
		if err != nil || count == 0 {
			response.HandleError(c, apperr.Forbidden("permission denied for device: "+sn))
			return
		}
	}

	placeholder := ""
	var args []interface{}
	for i, sn := range deviceSNs {
		if i > 0 {
			placeholder += ", "
		}
		placeholder += fmt.Sprintf("$%d", i+1)
		args = append(args, sn)
	}
	args = append(args, startTime, endTime)

	query := fmt.Sprintf(`
		SELECT device_sn, event_time,
			to_jsonb(device_telemetry_3min) - 'device_sn' - 'received_at' - 'event_time' AS data
		FROM device_telemetry_3min
		WHERE device_sn IN (%s) AND event_time >= $%d AND event_time <= $%d
		ORDER BY event_time
	`, placeholder, len(args)-1, len(args))

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.HandleError(c, apperr.Internal("get compare data failed", err))
		return
	}
	defer rows.Close()

	type SeriesPoint struct {
		Time   time.Time          `json:"time"`
		Values map[string]float64 `json:"values"`
	}

	timeSeriesMap := make(map[time.Time]map[string]float64)
	var times []time.Time
	timeSet := make(map[time.Time]bool)

	for rows.Next() {
		var sn string
		var t time.Time
		var dataJSON []byte
		if err := rows.Scan(&sn, &t, &dataJSON); err == nil {
			if !timeSet[t] {
				times = append(times, t)
				timeSet[t] = true
			}
			if _, ok := timeSeriesMap[t]; !ok {
				timeSeriesMap[t] = make(map[string]float64)
			}
			var data map[string]interface{}
			if err := json.Unmarshal(dataJSON, &data); err == nil {
				if val, ok := data[metric]; ok {
					switch v := val.(type) {
					case float64:
						timeSeriesMap[t][sn] = v
					case string:
						var f float64
						if _, err := fmt.Sscanf(v, "%f", &f); err == nil {
							timeSeriesMap[t][sn] = f
						}
					}
				}
			}
		}
	}

	var series []SeriesPoint
	for _, t := range times {
		series = append(series, SeriesPoint{
			Time:   t,
			Values: timeSeriesMap[t],
		})
	}
	if series == nil {
		series = []SeriesPoint{}
	}

	response.Success(c, gin.H{
		"devices": deviceSNs,
		"metric":  metric,
		"series":  series,
	})
}

func (h *DashboardHandler) GetEnergyStats(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)
	tz := getUserTimezone(ctx, h.db, userID)

	statType := c.DefaultQuery("type", "day")
	stationIDStr := c.Query("stationId")

	var daysBack int
	switch statType {
	case "day":
		daysBack = 7
	case "week":
		daysBack = 28
	case "month":
		daysBack = 365
	default:
		daysBack = 7
	}

	now := timezone.NowInTimezone(tz)
	startDate := now.AddDate(0, 0, -daysBack).Format("2006-01-02")
	endDate := now.Format("2006-01-02")

	var query string
	var args []interface{}

	if stationIDStr != "" {
		sid, err := strconv.ParseInt(stationIDStr, 10, 64)
		if err != nil || sid < 1 {
			response.HandleError(c, apperr.BadRequest("invalid stationId"))
			return
		}

		if isAdmin {
			query = `
				SELECT dd.stat_date,
					COALESCE(SUM(dd.pv_energy), 0), COALESCE(SUM(dd.charge_energy), 0),
					COALESCE(SUM(dd.discharge_energy), 0), COALESCE(SUM(dd.load_energy), 0)
				FROM device_energy_day dd
				JOIN devices d ON d.sn = dd.device_sn
				WHERE d.deleted_at IS NULL AND d.station_id = $1
					AND dd.stat_date >= $2 AND dd.stat_date <= $3
				GROUP BY dd.stat_date ORDER BY dd.stat_date
			`
			args = append(args, sid, startDate, endDate)
		} else {
			query = `
				SELECT dd.stat_date,
					COALESCE(SUM(dd.pv_energy), 0), COALESCE(SUM(dd.charge_energy), 0),
					COALESCE(SUM(dd.discharge_energy), 0), COALESCE(SUM(dd.load_energy), 0)
				FROM device_energy_day dd
				JOIN devices d ON d.sn = dd.device_sn
				WHERE d.deleted_at IS NULL AND d.user_id = $1 AND d.station_id = $2
					AND dd.stat_date >= $3 AND dd.stat_date <= $4
				GROUP BY dd.stat_date ORDER BY dd.stat_date
			`
			args = append(args, userID, sid, startDate, endDate)
		}
	} else {
		if isAdmin {
			query = `
				SELECT dd.stat_date,
					COALESCE(SUM(dd.pv_energy), 0), COALESCE(SUM(dd.charge_energy), 0),
					COALESCE(SUM(dd.discharge_energy), 0), COALESCE(SUM(dd.load_energy), 0)
				FROM device_energy_day dd
				JOIN devices d ON d.sn = dd.device_sn
				WHERE d.deleted_at IS NULL
					AND dd.stat_date >= $1 AND dd.stat_date <= $2
				GROUP BY dd.stat_date ORDER BY dd.stat_date
			`
			args = append(args, startDate, endDate)
		} else {
			query = `
				SELECT dd.stat_date,
					COALESCE(SUM(dd.pv_energy), 0), COALESCE(SUM(dd.charge_energy), 0),
					COALESCE(SUM(dd.discharge_energy), 0), COALESCE(SUM(dd.load_energy), 0)
				FROM device_energy_day dd
				JOIN devices d ON d.sn = dd.device_sn
				WHERE d.deleted_at IS NULL AND d.user_id = $1
					AND dd.stat_date >= $2 AND dd.stat_date <= $3
				GROUP BY dd.stat_date ORDER BY dd.stat_date
			`
			args = append(args, userID, startDate, endDate)
		}
	}

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		log.Printf("[GetEnergyStats] query error: %v, args: %v", err, args)
		response.HandleError(c, apperr.Internal("get energy stats failed", err))
		return
	}
	defer rows.Close()

	var dates []string
	var pv, batteryCharge, batteryDischarge, loadEnergy, inverterOutput, gridExport, gridImport []float64

	for rows.Next() {
		var date time.Time
		var energyProduce, dailyCharge, dailyDischarge, dailyLoad float64
		if err := rows.Scan(&date, &energyProduce, &dailyCharge, &dailyDischarge, &dailyLoad); err != nil {
			log.Printf("[GetEnergyStats] scan error: %v", err)
			continue
		}
		dates = append(dates, date.Format("2006-01-02"))
		pv = append(pv, energyProduce)
		batteryCharge = append(batteryCharge, dailyCharge)
		batteryDischarge = append(batteryDischarge, dailyDischarge)
		loadEnergy = append(loadEnergy, dailyLoad)
		inverterOutput = append(inverterOutput, 0)
		gridExport = append(gridExport, 0)
		gridImport = append(gridImport, 0)
	}

	if dates == nil {
		dates = []string{}
		pv = []float64{}
		batteryCharge = []float64{}
		batteryDischarge = []float64{}
		loadEnergy = []float64{}
		inverterOutput = []float64{}
		gridExport = []float64{}
		gridImport = []float64{}
	}

	response.Success(c, gin.H{
		"dates":            dates,
		"pv":               pv,
		"batteryCharge":    batteryCharge,
		"batteryDischarge": batteryDischarge,
		"load":             loadEnergy,
		"inverterOutput":   inverterOutput,
		"gridExport":       gridExport,
		"gridImport":       gridImport,
	})
}

func (h *DashboardHandler) GetStationRanking(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)
	tz := getUserTimezone(ctx, h.db, userID)

	period := c.DefaultQuery("period", "today")
	limitStr := c.DefaultQuery("limit", "10")
	limit, _ := strconv.Atoi(limitStr)
	if limit < 1 {
		limit = 1
	}
	if limit > 100 {
		limit = 100
	}

	now := timezone.NowInTimezone(tz)
	var startDate string
	switch period {
	case "today":
		startDate = now.Format("2006-01-02")
	case "week":
		startDate = now.AddDate(0, 0, -7).Format("2006-01-02")
	case "month":
		startDate = now.AddDate(0, -1, 0).Format("2006-01-02")
	case "year":
		startDate = now.AddDate(-1, 0, 0).Format("2006-01-02")
	default:
		startDate = now.Format("2006-01-02")
	}
	endDate := now.Format("2006-01-02")

	type StationRankingItem struct {
		StationID   int64   `json:"stationId"`
		StationName string  `json:"stationName"`
		Energy      float64 `json:"energy"`
		DeviceCount int     `json:"deviceCount"`
	}

	var query string
	var args []interface{}

	if isAdmin {
		query = `
			SELECT s.id, s.name,
				COALESCE(SUM(dd.pv_energy), 0) as energy,
				COUNT(DISTINCT d.sn) as device_count
			FROM stations s
			LEFT JOIN devices d ON d.station_id = s.id AND d.deleted_at IS NULL
			LEFT JOIN device_energy_day dd ON dd.device_sn = d.sn
				AND dd.stat_date >= $1 AND dd.stat_date <= $2
			WHERE s.deleted_at IS NULL
			GROUP BY s.id, s.name
			HAVING COALESCE(SUM(dd.pv_energy), 0) > 0
			ORDER BY energy DESC
			LIMIT $3
		`
		args = append(args, startDate, endDate, limit)
	} else {
		query = `
			SELECT s.id, s.name,
				COALESCE(SUM(dd.pv_energy), 0) as energy,
				COUNT(DISTINCT d.sn) as device_count
			FROM stations s
			LEFT JOIN devices d ON d.station_id = s.id AND d.deleted_at IS NULL
			LEFT JOIN device_energy_day dd ON dd.device_sn = d.sn
				AND dd.stat_date >= $2 AND dd.stat_date <= $3
			WHERE s.deleted_at IS NULL AND s.user_id = $1
			GROUP BY s.id, s.name
			HAVING COALESCE(SUM(dd.pv_energy), 0) > 0
			ORDER BY energy DESC
			LIMIT $4
		`
		args = append(args, userID, startDate, endDate, limit)
	}

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.HandleError(c, apperr.Internal("get station ranking failed", err))
		return
	}
	defer rows.Close()

	var ranking []StationRankingItem
	for rows.Next() {
		var item StationRankingItem
		if err := rows.Scan(&item.StationID, &item.StationName, &item.Energy, &item.DeviceCount); err == nil {
			ranking = append(ranking, item)
		}
	}
	if ranking == nil {
		ranking = []StationRankingItem{}
	}

	response.Success(c, ranking)
}

// GetEnergyFlow 获取指定日期的逐时能量流向数据
func (h *DashboardHandler) GetEnergyFlow(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	tz := getUserTimezone(ctx, h.db, userID)

	dateStr := c.DefaultQuery("date", timezone.TodayInTimezone(tz))
	targetDate, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		response.HandleError(c, apperr.BadRequest("invalid date format, use YYYY-MM-DD"))
		return
	}

	// 可选 stationId 过滤
	stationIDStr := c.Query("stationId")
	var stationID int64
	if stationIDStr != "" {
		if v, e := strconv.ParseInt(stationIDStr, 10, 64); e == nil {
			stationID = v
		}
	}

	// 数据库存的是UTC，将本地日期转为UTC范围
	loc := timezone.LoadLocation(tz)
	localDate := time.Date(targetDate.Year(), targetDate.Month(), targetDate.Day(), 0, 0, 0, 0, loc)
	startUTC := localDate.UTC().Format("2006-01-02 15:04:05")
	endUTC := localDate.AddDate(0, 0, 1).UTC().Format("2006-01-02 15:04:05")

	type FlowPoint struct {
		Time             time.Time `json:"time"`
		PVPower          float64   `json:"pvPower"`
		BatteryPower     float64   `json:"batteryPower"`
		LoadPower        float64   `json:"loadPower"`
		BatteryCharge    float64   `json:"batteryCharge"`
		BatteryDischarge float64   `json:"batteryDischarge"`
	}

	// 构建可选 station 过滤条件
	stationFilter := ""
	if stationID > 0 {
		stationFilter = fmt.Sprintf(" AND d.station_id = %d", stationID)
	}

	// 查询PV功率（time_bucket 做分钟级聚合）— 返回UTC时间，前端负责时区转换
	var pvQuery string
	var pvArgs []interface{}
	if h.isSuperAdmin(ctx, userID) {
		pvQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.pv_total_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL` + stationFilter + ` AND dt.event_time >= $1::timestamptz AND dt.event_time < $2::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		pvArgs = append(pvArgs, startUTC, endUTC)
	} else {
		pvQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.pv_total_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL AND d.user_id = $1` + stationFilter + `
				AND dt.event_time >= $2::timestamptz AND dt.event_time < $3::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		pvArgs = append(pvArgs, userID, startUTC, endUTC)
	}

	// 查询电池功率
	var battQuery string
	var battArgs []interface{}
	if h.isSuperAdmin(ctx, userID) {
		battQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.battery_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL` + stationFilter + ` AND dt.event_time >= $1::timestamptz AND dt.event_time < $2::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		battArgs = append(battArgs, startUTC, endUTC)
	} else {
		battQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.battery_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL AND d.user_id = $1` + stationFilter + `
				AND dt.event_time >= $2::timestamptz AND dt.event_time < $3::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		battArgs = append(battArgs, userID, startUTC, endUTC)
	}

	// 查询负载功率
	var loadQuery string
	var loadArgs []interface{}
	if h.isSuperAdmin(ctx, userID) {
		loadQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.ac_active_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL` + stationFilter + ` AND dt.event_time >= $1::timestamptz AND dt.event_time < $2::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		loadArgs = append(loadArgs, startUTC, endUTC)
	} else {
		loadQuery = `
			SELECT time_bucket('3 minutes', dt.event_time) as time_slot, AVG(COALESCE(dt.ac_active_power,0))
			FROM device_telemetry_3min dt
			JOIN devices d ON d.sn = dt.device_sn
			WHERE d.deleted_at IS NULL AND d.user_id = $1` + stationFilter + `
				AND dt.event_time >= $2::timestamptz AND dt.event_time < $3::timestamptz
			GROUP BY time_slot ORDER BY time_slot
		`
		loadArgs = append(loadArgs, userID, startUTC, endUTC)
	}

	// 收集所有时间点，key 为 Unix 分钟数，确保分钟级去重与排序
	flowMap := make(map[int64]*FlowPoint)

	// 查询PV
	pvRows, err := h.db.Query(ctx, pvQuery, pvArgs...)
	if err == nil {
		defer pvRows.Close()
		for pvRows.Next() {
			var t time.Time
			var pv float64
			if pvRows.Scan(&t, &pv) == nil {
				key := t.Unix() / 60
				if _, ok := flowMap[key]; !ok {
					flowMap[key] = &FlowPoint{Time: t}
				}
				flowMap[key].PVPower = pv
			}
		}
	}

	// 查询电池
	battRows, err := h.db.Query(ctx, battQuery, battArgs...)
	if err == nil {
		defer battRows.Close()
		for battRows.Next() {
			var t time.Time
			var batt float64
			if battRows.Scan(&t, &batt) == nil {
				key := t.Unix() / 60
				if _, ok := flowMap[key]; !ok {
					flowMap[key] = &FlowPoint{Time: t}
				}
				flowMap[key].BatteryPower = batt
				if batt > 0 {
					flowMap[key].BatteryCharge = batt
				} else {
					flowMap[key].BatteryDischarge = -batt
				}
			}
		}
	}

	// 查询负载
	loadRows, err := h.db.Query(ctx, loadQuery, loadArgs...)
	if err == nil {
		defer loadRows.Close()
		for loadRows.Next() {
			var t time.Time
			var load float64
			if loadRows.Scan(&t, &load) == nil {
				key := t.Unix() / 60
				if _, ok := flowMap[key]; !ok {
					flowMap[key] = &FlowPoint{Time: t}
				}
				flowMap[key].LoadPower = load
			}
		}
	}

	// 按分钟 key 排序输出
	var keys []int64
	for k := range flowMap {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })

	// 过滤边界上不完整的时间点（只有PV数据，电池/负载为0）
	for len(keys) > 0 {
		first := flowMap[keys[0]]
		if first.BatteryPower == 0 && first.LoadPower == 0 {
			keys = keys[1:]
		} else {
			break
		}
	}
	for len(keys) > 0 {
		last := flowMap[keys[len(keys)-1]]
		if last.BatteryPower == 0 && last.LoadPower == 0 {
			keys = keys[:len(keys)-1]
		} else {
			break
		}
	}

	var result []FlowPoint
	for _, k := range keys {
		result = append(result, *flowMap[k])
	}

	if result == nil {
		result = []FlowPoint{}
	}

	response.Success(c, gin.H{
		"date": dateStr,
		"data": result,
	})
}

func toFloat64Dashboard(v interface{}) (float64, bool) {
	switch val := v.(type) {
	case float64:
		return val, true
	case float32:
		return float64(val), true
	case int:
		return float64(val), true
	case int64:
		return float64(val), true
	case json.Number:
		f, err := val.Float64()
		return f, err == nil
	default:
		return 0, false
	}
}

// SSE 实现 Server-Sent Events 端点，实时推送 Dashboard 数据更新
// 优化：使用 Redis Pub/Sub 订阅事件驱动推送 + 30s 轮询回退
func (h *DashboardHandler) SSE(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()

	// 设置 SSE 响应头
	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("Access-Control-Allow-Origin", "*")
	c.Header("X-Accel-Buffering", "no")

	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		response.HandleError(c, apperr.Internal("streaming unsupported", nil))
		return
	}

	// 发送初始连接确认
	fmt.Fprintf(c.Writer, "event: connected\ndata: {\"status\":\"connected\"}\n\n")
	flusher.Flush()

	// 事件驱动：订阅 Redis Pub/Sub 频道，实时推送仪表盘更新
	var pubsub *redis.PubSub
	var pubsubCh <-chan *redis.Message
	if h.rdb != nil {
		pubsub = h.rdb.Subscribe(ctx, "dashboard:events")
		pubsubCh = pubsub.Channel()
		defer pubsub.Close()
	}

	// 回退轮询：30秒（从原10秒延长，因为事件驱动已覆盖实时性）
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	heartbeatTicker := time.NewTicker(30 * time.Second)
	defer heartbeatTicker.Stop()

	eventID := 0
	lastPush := time.Time{}
	// 防抖：避免短时间内重复推送（最小间隔 2 秒）
	const debounceInterval = 2 * time.Second

	pushUpdate := func() {
		// 防抖：距离上次推送不足 2 秒则跳过
		if time.Since(lastPush) < debounceInterval {
			return
		}
		lastPush = time.Now()

		eventID++
		data := h.collectDashboardSSEData(ctx, userID)
		data["event_id"] = eventID

		jsonData, err := json.Marshal(data)
		if err != nil {
			return
		}

		fmt.Fprintf(c.Writer, "event: dashboard_update\nid: %d\ndata: %s\n\n", eventID, jsonData)
		flusher.Flush()
	}

	for {
		select {
		case <-c.Request.Context().Done():
			// 客户端断开连接
			return
		case <-ctx.Done():
			return
		case <-heartbeatTicker.C:
			// 发送心跳保持连接
			fmt.Fprintf(c.Writer, ": heartbeat\n\n")
			flusher.Flush()
		case <-ticker.C:
			// 回退轮询：定期推送 Dashboard 数据更新
			pushUpdate()
		case msg := <-pubsubCh:
			// 事件驱动：收到 Redis Pub/Sub 事件时立即推送
			_ = msg
			pushUpdate()
		}
	}
}

// collectDashboardData 收集 Dashboard 所需的统计数据
func (h *DashboardHandler) collectDashboardData(ctx context.Context, userID int64) map[string]interface{} {
	isAdmin := h.isSuperAdmin(ctx, userID)

	// 设备统计
	type DeviceStats struct {
		Total   int64 `json:"total"`
		Online  int64 `json:"online"`
		Offline int64 `json:"offline"`
		Fault   int64 `json:"fault"`
	}

	var deviceStats DeviceStats
	var deviceQuery string
	var deviceArgs []interface{}

	if isAdmin {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL
		`
	} else {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL AND user_id = $1
		`
		deviceArgs = append(deviceArgs, userID)
	}

	h.db.QueryRow(ctx, deviceQuery, deviceArgs...).Scan(
		&deviceStats.Total, &deviceStats.Online, &deviceStats.Offline, &deviceStats.Fault,
	)

	// 最近告警
	type RecentAlarm struct {
		ID           int64     `json:"id"`
		DeviceSN     string    `json:"device_sn"`
		AlarmLevel   int       `json:"alarm_level"`
		FaultCode    string    `json:"fault_code"`
		FaultMessage string    `json:"fault_message"`
		OccurredAt   time.Time `json:"occurred_at"`
	}

	var alarmQuery string
	var alarmArgs []interface{}

	if isAdmin {
		alarmQuery = `
			SELECT id, device_sn, alarm_level, fault_code, fault_message, occurred_at
			FROM alarms
			ORDER BY occurred_at DESC
			LIMIT 5
		`
	} else {
		alarmQuery = `
			SELECT a.id, a.device_sn, a.alarm_level, a.fault_code, a.fault_message, a.occurred_at
			FROM alarms a
			JOIN devices d ON d.sn = a.device_sn
			WHERE d.user_id = $1
			ORDER BY a.occurred_at DESC
			LIMIT 5
		`
		alarmArgs = append(alarmArgs, userID)
	}

	rows, err := h.db.Query(ctx, alarmQuery, alarmArgs...)
	var recentAlarms []RecentAlarm
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var alarm RecentAlarm
			if err := rows.Scan(&alarm.ID, &alarm.DeviceSN, &alarm.AlarmLevel, &alarm.FaultCode, &alarm.FaultMessage, &alarm.OccurredAt); err == nil {
				recentAlarms = append(recentAlarms, alarm)
			}
		}
	}
	if recentAlarms == nil {
		recentAlarms = []RecentAlarm{}
	}

	return map[string]interface{}{
		"deviceStats":  deviceStats,
		"recentAlarms": recentAlarms,
		"timestamp":    time.Now().UTC().Format(time.RFC3339),
		"type":         "dashboard_update",
	}
}

// collectDashboardSSEData 收集 Dashboard SSE 推送数据（匹配前端期望的格式）
func (h *DashboardHandler) collectDashboardSSEData(ctx context.Context, userID int64) map[string]interface{} {
	isAdmin := h.isSuperAdmin(ctx, userID)

	// 设备统计
	var total, online, offline, fault int64
	var deviceQuery string
	var deviceArgs []interface{}

	if isAdmin {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL
		`
	} else {
		deviceQuery = `
			SELECT 
				COUNT(*) as total,
				COUNT(*) FILTER (WHERE status = 1) as online,
				COUNT(*) FILTER (WHERE status = 0) as offline,
				COUNT(*) FILTER (WHERE status = 2) as fault
			FROM devices 
			WHERE deleted_at IS NULL AND user_id = $1
		`
		deviceArgs = append(deviceArgs, userID)
	}

	h.db.QueryRow(ctx, deviceQuery, deviceArgs...).Scan(&total, &online, &offline, &fault)

	// 最近告警
	type RecentAlarm struct {
		ID           int64     `json:"id"`
		DeviceSN     string    `json:"device_sn"`
		AlarmLevel   int       `json:"alarm_level"`
		FaultCode    string    `json:"fault_code"`
		FaultMessage string    `json:"fault_message"`
		OccurredAt   time.Time `json:"occurred_at"`
	}

	var alarmQuery string
	var alarmArgs []interface{}

	if isAdmin {
		alarmQuery = `
			SELECT id, device_sn, alarm_level, fault_code, fault_message, occurred_at
			FROM alarms
			ORDER BY occurred_at DESC
			LIMIT 5
		`
	} else {
		alarmQuery = `
			SELECT a.id, a.device_sn, a.alarm_level, a.fault_code, a.fault_message, a.occurred_at
			FROM alarms a
			JOIN devices d ON d.sn = a.device_sn
			WHERE d.user_id = $1
			ORDER BY a.occurred_at DESC
			LIMIT 5
		`
		alarmArgs = append(alarmArgs, userID)
	}

	rows, err := h.db.Query(ctx, alarmQuery, alarmArgs...)
	var recentAlarms []RecentAlarm
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var alarm RecentAlarm
			if err := rows.Scan(&alarm.ID, &alarm.DeviceSN, &alarm.AlarmLevel, &alarm.FaultCode, &alarm.FaultMessage, &alarm.OccurredAt); err == nil {
				recentAlarms = append(recentAlarms, alarm)
			}
		}
	}
	if recentAlarms == nil {
		recentAlarms = []RecentAlarm{}
	}

	// 匹配前端 DashboardData 的字段名
	return map[string]interface{}{
		"type": "dashboard_update",
		"deviceStats": map[string]interface{}{
			"total":   total,
			"online":  online,
			"offline": offline,
			"fault":   fault,
		},
		"recentAlarms": recentAlarms,
		"timestamp":    time.Now().UTC().Format(time.RFC3339),
	}
}
