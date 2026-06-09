package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"inv-api-server/internal/middleware"
	"inv-api-server/pkg/response"

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

func (h *DashboardHandler) GetStatistics(c *gin.Context) {
	userID := middleware.GetUserID(c)
	ctx := c.Request.Context()
	isAdmin := h.isSuperAdmin(ctx, userID)

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
		response.InternalError(c, "get device stats failed")
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

	if h.rdb != nil {
		for _, sn := range deviceSNs {
			mainKey := "realtime:latest:" + sn
			cached, err := h.rdb.Get(ctx, mainKey).Result()
			if err == nil && cached != "" {
				var m map[string]interface{}
				if json.Unmarshal([]byte(cached), &m) == nil {
					if v, ok := m["daily_pv"]; ok {
						if f, ok := toFloat64Dashboard(v); ok {
							todayEnergy += f
						}
					}
					if v, ok := m["total_pv"]; ok {
						if f, ok := toFloat64Dashboard(v); ok {
							totalEnergy += f
						}
					}
				}
			}

			dailyPvKey := "realtime:latest:" + sn + ":daily_pv"
			dailyPvVal, err := h.rdb.Get(ctx, dailyPvKey).Result()
			if err == nil && dailyPvVal != "" {
				var fieldData map[string]interface{}
				if json.Unmarshal([]byte(dailyPvVal), &fieldData) == nil {
					if v, ok := fieldData["v"]; ok {
						if f, ok := toFloat64Dashboard(v); ok && f > todayEnergy {
							todayEnergy = f
						}
					}
				}
			}

			totalPvKey := "realtime:latest:" + sn + ":total_pv"
			totalPvVal, err := h.rdb.Get(ctx, totalPvKey).Result()
			if err == nil && totalPvVal != "" {
				var fieldData map[string]interface{}
				if json.Unmarshal([]byte(totalPvVal), &fieldData) == nil {
					if v, ok := fieldData["v"]; ok {
						if f, ok := toFloat64Dashboard(v); ok && f > totalEnergy {
							totalEnergy = f
						}
					}
				}
			}
		}
	}

	type RecentAlarm struct {
		ID           int64     `json:"id"`
		DeviceSN     string    `json:"device_sn"`
		AlarmLevel   int       `json:"alarm_level"`
		FaultMessage string    `json:"fault_message"`
		OccurredAt   time.Time `json:"occurred_at"`
	}

	var alarmQuery string
	var alarmArgs []interface{}

	if isAdmin {
		alarmQuery = `
			SELECT id, device_sn, alarm_level, fault_message, occurred_at
			FROM alarms 
			ORDER BY occurred_at DESC 
			LIMIT 5
		`
	} else {
		alarmQuery = `
			SELECT a.id, a.device_sn, a.alarm_level, a.fault_message, a.occurred_at
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
			if err := rows.Scan(&alarm.ID, &alarm.DeviceSN, &alarm.AlarmLevel, &alarm.FaultMessage, &alarm.OccurredAt); err == nil {
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
		response.InternalError(c, "get distribution failed")
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

	trendType := c.DefaultQuery("type", "day")

	var startDate, endDate string
	now := time.Now()

	switch trendType {
	case "day":
		startDate = now.AddDate(0, 0, -7).Format("2006-01-02")
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

	type TrendData struct {
		Date       string  `json:"date"`
		Energy     float64 `json:"energy"`
		Cumulative float64 `json:"cumulative"`
	}

	var query string
	var args []interface{}

	if isAdmin {
		query = `
			SELECT 
				dd.data_date as date,
				COALESCE(SUM(dd.energy_produce), 0) as energy
			FROM device_day_data dd
			JOIN devices d ON d.sn = dd.device_sn
			WHERE d.deleted_at IS NULL AND dd.data_date >= $1 AND dd.data_date <= $2
			GROUP BY dd.data_date
			ORDER BY dd.data_date
		`
		args = append(args, startDate, endDate)
	} else {
		query = `
			SELECT 
				dd.data_date as date,
				COALESCE(SUM(dd.energy_produce), 0) as energy
			FROM device_day_data dd
			JOIN devices d ON d.sn = dd.device_sn
			WHERE d.deleted_at IS NULL AND d.user_id = $1 AND dd.data_date >= $2 AND dd.data_date <= $3
			GROUP BY dd.data_date
			ORDER BY dd.data_date
		`
		args = append(args, userID, startDate, endDate)
	}

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.InternalError(c, "get trend failed: "+err.Error())
		return
	}
	defer rows.Close()

	var trendData []TrendData
	var cumulative float64
	for rows.Next() {
		var td TrendData
		if err := rows.Scan(&td.Date, &td.Energy); err == nil {
			cumulative += td.Energy
			td.Cumulative = cumulative
			trendData = append(trendData, td)
		}
	}
	if trendData == nil {
		trendData = []TrendData{}
	}

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
		response.BadRequest(c, "missing devices parameter")
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
			response.Forbidden(c, "permission denied for device: "+sn)
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
		SELECT device_sn, time, data
		FROM device_telemetry 
		WHERE device_sn IN (%s) AND time >= $%d AND time <= $%d
		ORDER BY time
	`, placeholder, len(args)-1, len(args))

	rows, err := h.db.Query(ctx, query, args...)
	if err != nil {
		response.InternalError(c, "get compare data failed")
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
