package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"inv-api-server/internal/repository"
	"inv-api-server/pkg/response"
	"inv-api-server/pkg/sn"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"
)

type AdminHandler struct {
	db          *pgxpool.Pool
	rdb         *redis.Client
	htmlPath    string
	htmlCache   []byte
	deviceRepo  *repository.DeviceRepository
	stationRepo *repository.StationRepository
	userRepo    *repository.UserRepository
	alarmRepo   *repository.AlarmRepository
	notifyRepo  *repository.NotifyRepository
}

func NewAdminHandler(
	db *pgxpool.Pool,
	rdb *redis.Client,
	htmlPath string,
	deviceRepo *repository.DeviceRepository,
	stationRepo *repository.StationRepository,
	userRepo *repository.UserRepository,
	alarmRepo *repository.AlarmRepository,
	notifyRepo *repository.NotifyRepository,
) *AdminHandler {
	h := &AdminHandler{
		db:          db,
		rdb:         rdb,
		htmlPath:    htmlPath,
		deviceRepo:  deviceRepo,
		stationRepo: stationRepo,
		userRepo:    userRepo,
		alarmRepo:   alarmRepo,
		notifyRepo:  notifyRepo,
	}
	h.loadHTML()
	return h
}

func (h *AdminHandler) loadHTML() {
	data, err := os.ReadFile(h.htmlPath)
	if err != nil {
		h.htmlCache = []byte("<html><body><h1>Admin page not found</h1></body></html>")
		return
	}
	h.htmlCache = data
}

func (h *AdminHandler) Index(c *gin.Context) {
	h.loadHTML()
	c.Data(http.StatusOK, "text/html; charset=utf-8", h.htmlCache)
}

func (h *AdminHandler) Dashboard(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	result := map[string]interface{}{
		"server": map[string]interface{}{
			"status": "running",
			"time":   time.Now().Format("2006-01-02 15:04:05"),
			"tz":     time.Now().Location().String(),
		},
	}

	dbStatus := "ok"
	if err := h.db.Ping(ctx); err != nil {
		dbStatus = "error: " + err.Error()
	}
	result["database"] = dbStatus

	redisStatus := "ok"
	if err := h.rdb.Ping(ctx).Err(); err != nil {
		redisStatus = "error: " + err.Error()
	}
	result["redis"] = redisStatus

	var deviceCount, onlineCount, faultCount int
	err := h.db.QueryRow(ctx, `SELECT COUNT(*), COUNT(*) FILTER (WHERE status=1), COUNT(*) FILTER (WHERE status=2) FROM devices WHERE deleted_at IS NULL`).
		Scan(&deviceCount, &onlineCount, &faultCount)
	if err == nil {
		result["devices"] = map[string]interface{}{
			"total":  deviceCount,
			"online": onlineCount,
			"fault":  faultCount,
		}
	}

	var stationCount int
	err = h.db.QueryRow(ctx, `SELECT COUNT(*) FROM stations WHERE deleted_at IS NULL`).Scan(&stationCount)
	if err == nil {
		result["stations"] = stationCount
	}

	var userCount int
	err = h.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`).Scan(&userCount)
	if err == nil {
		result["users"] = userCount
	}

	var alarmCount int
	err = h.db.QueryRow(ctx, `SELECT COUNT(*) FROM alarms WHERE status = 0`).Scan(&alarmCount)
	if err == nil {
		result["alarms_active"] = alarmCount
	}

	c.JSON(http.StatusOK, result)
}

func (h *AdminHandler) Devices(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rows, err := h.db.Query(ctx, `
		SELECT d.id, d.sn, COALESCE(d.model,''), COALESCE(d.rated_power,0), COALESCE(d.firmware_version,''),
			   d.user_id, COALESCE(d.station_id,0), d.status, d.last_online_at, d.created_at,
			   COALESCE(u.phone,'') as owner_phone
		FROM devices d LEFT JOIN users u ON u.id = d.user_id
		WHERE d.deleted_at IS NULL ORDER BY d.created_at DESC LIMIT 200
	`)
	if err != nil {
		response.InternalError(c, "query failed")
		return
	}
	defer rows.Close()

	type DeviceRow struct {
		ID              int64      `json:"id"`
		SN              string     `json:"sn"`
		Model           string     `json:"model"`
		RatedPower      float64    `json:"rated_power"`
		FirmwareVersion string     `json:"firmware_version"`
		UserID          int64      `json:"user_id"`
		StationID       int64      `json:"station_id"`
		Status          int        `json:"status"`
		LastOnlineAt    *time.Time `json:"last_online_at"`
		CreatedAt       time.Time  `json:"created_at"`
		OwnerPhone      string     `json:"owner_phone"`
	}

	devices := make([]DeviceRow, 0)
	for rows.Next() {
		var d DeviceRow
		var lastOnlineAt *time.Time
		if err := rows.Scan(&d.ID, &d.SN, &d.Model, &d.RatedPower, &d.FirmwareVersion,
			&d.UserID, &d.StationID, &d.Status, &lastOnlineAt, &d.CreatedAt, &d.OwnerPhone); err != nil {
			continue
		}
		d.LastOnlineAt = lastOnlineAt
		devices = append(devices, d)
	}

	c.JSON(http.StatusOK, devices)
}

func (h *AdminHandler) Stations(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rows, err := h.db.Query(ctx, `
		SELECT s.id, s.user_id, s.name, COALESCE(s.province,''), COALESCE(s.city,''), COALESCE(s.capacity,0),
			   CASE WHEN EXISTS (SELECT 1 FROM devices d WHERE d.station_id = s.id AND d.status = 1 AND d.deleted_at IS NULL) THEN 1 ELSE 0 END,
			   s.created_at, COALESCE(u.phone,'') as owner_phone
		FROM stations s LEFT JOIN users u ON u.id = s.user_id
		WHERE s.deleted_at IS NULL ORDER BY s.created_at DESC LIMIT 200
	`)
	if err != nil {
		response.InternalError(c, "query failed")
		return
	}
	defer rows.Close()

	type StationRow struct {
		ID         int64     `json:"id"`
		UserID     int64     `json:"user_id"`
		Name       string    `json:"name"`
		Province   string    `json:"province"`
		City       string    `json:"city"`
		Capacity   float64   `json:"capacity"`
		Status     int       `json:"status"`
		CreatedAt  time.Time `json:"created_at"`
		OwnerPhone string    `json:"owner_phone"`
	}

	stations := make([]StationRow, 0)
	for rows.Next() {
		var s StationRow
		if err := rows.Scan(&s.ID, &s.UserID, &s.Name, &s.Province, &s.City, &s.Capacity,
			&s.Status, &s.CreatedAt, &s.OwnerPhone); err != nil {
			continue
		}
		stations = append(stations, s)
	}

	c.JSON(http.StatusOK, stations)
}

func (h *AdminHandler) Users(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rows, err := h.db.Query(ctx, `
		SELECT id, COALESCE(phone,''), COALESCE(email,''), COALESCE(nickname,''), role, status, last_login_at, created_at
		FROM users WHERE deleted_at IS NULL ORDER BY id DESC LIMIT 200
	`)
	if err != nil {
		response.InternalError(c, "query failed")
		return
	}
	defer rows.Close()

	type UserRow struct {
		ID          int64      `json:"id"`
		Phone       string     `json:"phone"`
		Email       string     `json:"email"`
		Nickname    string     `json:"nickname"`
		Role        int        `json:"role"`
		Status      int        `json:"status"`
		LastLoginAt *time.Time `json:"last_login_at"`
		CreatedAt   time.Time  `json:"created_at"`
	}

	users := make([]UserRow, 0)
	for rows.Next() {
		var u UserRow
		var lastLoginAt *time.Time
		if err := rows.Scan(&u.ID, &u.Phone, &u.Email, &u.Nickname, &u.Role, &u.Status, &lastLoginAt, &u.CreatedAt); err != nil {
			continue
		}
		u.LastLoginAt = lastLoginAt
		users = append(users, u)
	}

	c.JSON(http.StatusOK, users)
}

func (h *AdminHandler) Alarms(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rows, err := h.db.Query(ctx, `
		SELECT id, device_sn, alarm_level, COALESCE(fault_code,''), COALESCE(fault_message,''), status, occurred_at, created_at
		FROM alarms ORDER BY occurred_at DESC LIMIT 200
	`)
	if err != nil {
		response.InternalError(c, "query failed")
		return
	}
	defer rows.Close()

	type AlarmRow struct {
		ID           int64     `json:"id"`
		DeviceSN     string    `json:"device_sn"`
		AlarmLevel   int       `json:"alarm_level"`
		FaultCode    string    `json:"fault_code"`
		FaultMessage string    `json:"fault_message"`
		Status       int       `json:"status"`
		OccurredAt   time.Time `json:"occurred_at"`
		CreatedAt    time.Time `json:"created_at"`
	}

	alarms := make([]AlarmRow, 0)
	for rows.Next() {
		var a AlarmRow
		if err := rows.Scan(&a.ID, &a.DeviceSN, &a.AlarmLevel, &a.FaultCode, &a.FaultMessage,
			&a.Status, &a.OccurredAt, &a.CreatedAt); err != nil {
			continue
		}
		alarms = append(alarms, a)
	}

	c.JSON(http.StatusOK, alarms)
}

func (h *AdminHandler) ProxyAPI(c *gin.Context) {
	var req struct {
		Method  string                 `json:"method"`
		Path    string                 `json:"path"`
		Body    map[string]interface{} `json:"body"`
		Headers map[string]string      `json:"headers"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"error": err.Error()})
		return
	}

	bodyBytes, _ := json.Marshal(req.Body)
	var bodyReader *bytes.Reader
	if len(bodyBytes) > 4 {
		bodyReader = bytes.NewReader(bodyBytes)
	}

	var httpReq *http.Request
	var err error
	if bodyReader != nil {
		httpReq, err = http.NewRequest(req.Method, "http://localhost:8080"+req.Path, bodyReader)
	} else {
		httpReq, err = http.NewRequest(req.Method, "http://localhost:8080"+req.Path, nil)
	}
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"error": err.Error()})
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"error": err.Error()})
		return
	}
	defer resp.Body.Close()

	var result interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	c.JSON(http.StatusOK, map[string]interface{}{
		"status_code": resp.StatusCode,
		"body":        result,
	})
}

func checkPort(host string, port int) string {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", host, port), 2*time.Second)
	if err != nil {
		return "offline"
	}
	conn.Close()
	return "online"
}

func (h *AdminHandler) Services(c *gin.Context) {
	result := map[string]interface{}{
		"api_server":     checkPort("127.0.0.1", 8080),
		"device_server":  checkPort("127.0.0.1", 8081),
		"mqtt_broker":    checkPort("127.0.0.1", 1883),
		"mqtt_websocket": checkPort("127.0.0.1", 8083),
		"postgresql":     checkPort("127.0.0.1", 5432),
		"redis":          checkPort("127.0.0.1", 6379),
		"checked_at":     time.Now().Format("2006-01-02 15:04:05"),
	}
	c.JSON(http.StatusOK, result)
}

func (h *AdminHandler) RestartServices(c *gin.Context) {
	batPath := "d:\\INV-MQTT\\restart_others.bat"
	cmd := exec.Command("cmd", "/c", "start", "/min", "cmd", "/c", batPath)
	cmd.Dir = "d:\\INV-MQTT"
	cmd.Start()

	c.JSON(http.StatusOK, map[string]interface{}{
		"status": "ok",
		"message": "重启命令已下发，其他服务将在后台启动。请等待 5 秒后刷新页面",
	})
}

func (h *AdminHandler) Logs(c *gin.Context) {
	service := c.DefaultQuery("service", "api")
	var logFile string
	switch service {
	case "device":
		logFile = "d:\\INV-MQTT\\inv_device_server\\logs\\device-server.log"
	case "mqtt":
		logData, ok := h.readMosquittoLog()
		if !ok {
			c.JSON(http.StatusOK, map[string]interface{}{"log": "Mosquitto 以控制台模式运行，无日志文件。请查看 Mosquitto 终端窗口"})
			return
		}
		c.JSON(http.StatusOK, map[string]interface{}{"log": logData})
		return
	default:
		logFile = "d:\\INV-MQTT\\inv_api_server\\logs\\api-server.log"
	}
	data, err := os.ReadFile(logFile)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{
			"log": "(日志文件不存在或无法读取，服务可能尚未生成日志" + err.Error() + ")",
		})
		return
	}
	content := string(data)
	if len(content) > 50000 {
		content = content[len(content)-50000:]
	}
	c.JSON(http.StatusOK, map[string]interface{}{
		"log": content,
	})
}

func (h *AdminHandler) readMosquittoLog() (string, bool) {
	paths := []string{
		"C:\\Program Files\\mosquitto\\mosquitto.log",
		"C:\\ProgramData\\mosquitto\\mosquitto.log",
	}
	for _, p := range paths {
		if data, err := os.ReadFile(p); err == nil {
			content := string(data)
			if len(content) > 50000 {
				content = content[len(content)-50000:]
			}
			return content, true
		}
	}
	return "", false
}

func (h *AdminHandler) Connections(c *gin.Context) {
	cmd := exec.Command("netstat", "-ano")
	cmd.Dir = "d:\\INV-MQTT"
	output, err := cmd.CombinedOutput()
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{
			"error": err.Error(),
		})
		return
	}

	lines := []string{}
	for _, line := range splitLines(string(output)) {
		for _, port := range []string{":8080", ":8081", ":1883", ":8083", ":5432", ":6379"} {
			if len(line) > 4 && (lineHas(line, port)) {
				lines = append(lines, line)
				break
			}
		}
	}
	result := strings.Join(lines, "\n")
	if result == "" {
		result = string(output)
		if len(result) > 10000 {
			result = result[len(result)-10000:]
		}
	}
	c.JSON(http.StatusOK, map[string]interface{}{
		"connections": result,
	})
}

func (h *AdminHandler) DeviceLogs(c *gin.Context) {
	logFile := "d:\\INV-MQTT\\inv_device_server\\logs\\device-server.log"
	data, err := os.ReadFile(logFile)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{
			"error": "cannot read device-server log: " + err.Error(),
		})
		return
	}
	content := string(data)
	if len(content) > 50000 {
		content = content[len(content)-50000:]
	}
	c.JSON(http.StatusOK, map[string]interface{}{
		"log": content,
	})
}

func splitLines(s string) []string {
	var result []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			result = append(result, s[start:i])
			start = i + 1
		} else if s[i] == '\r' {
			if i+1 < len(s) && s[i+1] == '\n' {
				result = append(result, s[start:i])
				start = i + 2
				i++
			} else {
				result = append(result, s[start:i])
				start = i + 1
			}
		}
	}
	if start < len(s) {
		result = append(result, s[start:])
	}
	return result
}

func InternalDeviceStatus(c *gin.Context) {
	var req struct {
		SN     string `json:"sn"`
		Status int    `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.SN == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "invalid request"})
		return
	}

	db := getDB()
	if db == nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "db not ready"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	result, err := db.Exec(ctx, `UPDATE devices SET status=$1, updated_at=NOW() WHERE sn=$2 AND deleted_at IS NULL`, req.Status, req.SN)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if req.Status == 1 {
		db.Exec(ctx, `UPDATE devices SET last_online_at=NOW() WHERE sn=$1 AND deleted_at IS NULL`, req.SN)
	}
	if result.RowsAffected() == 0 {
		_, err = db.Exec(ctx,
			`INSERT INTO devices (sn, status, last_online_at, user_id, deleted_at, created_at, updated_at) VALUES ($1,$2,NOW(),0,NULL,NOW(),NOW()) ON CONFLICT (sn) DO UPDATE SET status=$2, last_online_at=NOW(), deleted_at=NULL, updated_at=NOW()`,
			req.SN, req.Status)
		if err != nil {
			c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
			return
		}
	}

	db.Exec(ctx, `
		UPDATE stations SET
			status = CASE
				WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status = 1 AND devices.deleted_at IS NULL) THEN 1
				ELSE 0
			END,
			updated_at = NOW()
		WHERE deleted_at IS NULL
	`)

	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
}

func InternalDeviceData(c *gin.Context) {
	type MPPTArray []float64
	type StringCurrentsArray []float64
	var data struct {
		SerialNumber         string             `json:"serial_number"`
		Manufacturer         string             `json:"manufacturer"`
		Model                string             `json:"model"`
		DeviceTypeCode       int                `json:"device_type_code"`
		ArmVersion           string             `json:"arm_version"`
		DSPVersion           string             `json:"dsp_version"`
		ProtocolNumber       int                `json:"protocol_number"`
		ProtocolVersion      int                `json:"protocol_version"`
		NominalActivePower   float64            `json:"nominal_active_power"`
		NominalReactivePower float64            `json:"nominal_reactive_power"`
		OutputType           int                `json:"output_type"`
		DailyPowerYields     float64            `json:"daily_power_yields"`
		TotalPowerYields     float64            `json:"total_power_yields"`
		TotalPowerYields01   float64            `json:"total_power_yields_01"`
		MonthlyPowerYields   float64            `json:"monthly_power_yields"`
		TotalRunningTime     int                `json:"total_running_time"`
		DailyRunningTime     int                `json:"daily_running_time"`
		InternalTemperature  float64            `json:"internal_temperature"`
		MPPTVoltage          MPPTArray          `json:"mppt_voltage"`
		MPPTCurrent          MPPTArray          `json:"mppt_current"`
		TotalDCPower         float64            `json:"total_dc_power"`
		PhaseAVoltage        float64            `json:"phase_a_voltage"`
		PhaseBVoltage        float64            `json:"phase_b_voltage"`
		PhaseCVoltage        float64            `json:"phase_c_voltage"`
		PhaseACurrent        float64            `json:"phase_a_current"`
		PhaseBCurrent        float64            `json:"phase_b_current"`
		PhaseCCurrent        float64            `json:"phase_c_current"`
		TotalActivePower     float64            `json:"total_active_power"`
		TotalReactivePower   float64            `json:"total_reactive_power"`
		TotalApparentPower   float64            `json:"total_apparent_power"`
		PowerFactor          float64            `json:"power_factor"`
		GridFrequency        float64            `json:"grid_frequency"`
		WorkState1           string             `json:"work_state_1"`
		WorkState1Code       int                `json:"work_state_1_code"`
		WorkState2           int                `json:"work_state_2"`
		InverterState1       int                `json:"inverter_state_1"`
		InverterState2       int                `json:"inverter_state_2"`
		InsulationResistance int                `json:"insulation_resistance"`
		BusVoltage           float64            `json:"bus_voltage"`
		NegativeGroundVoltage float64            `json:"negative_ground_voltage"`
		PIDWorkState         int                `json:"pid_work_state"`
		PIDAlarmCode         int                `json:"pid_alarm_code"`
		CountryCode          int                `json:"country_code"`
		MeterTotalPower      float64            `json:"meter_total_power"`
		MeterPhaseAPower     float64            `json:"meter_phase_a_power"`
		MeterPhaseBPower     float64            `json:"meter_phase_b_power"`
		MeterPhaseCPower     float64            `json:"meter_phase_c_power"`
		LoadPower            float64            `json:"load_power"`
		DailyFeedEnergy      float64            `json:"daily_feed_energy"`
		TotalFeedEnergy      float64            `json:"total_feed_energy"`
		DailyGridImport      float64            `json:"daily_grid_import"`
		TotalGridImport      float64            `json:"total_grid_import"`
		StringCurrents       StringCurrentsArray `json:"string_currents"`
		ActivePowerSetting   float64            `json:"active_power_setting"`
		ReactivePowerSetting float64            `json:"reactive_power_setting"`
		PowerFactorSetting   float64            `json:"power_factor_setting"`
		Timestamp            int                `json:"timestamp"`
	}
	if err := c.ShouldBindJSON(&data); err != nil || data.SerialNumber == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "invalid request"})
		return
	}

	db := getDB()
	if db == nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "db not ready"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rawJSON, _ := json.Marshal(data)
	_, err := db.Exec(ctx, `INSERT INTO device_telemetry (device_sn, data, time, created_at) VALUES ($1, $2::jsonb, NOW(), NOW())`, data.SerialNumber, rawJSON)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
}
func InternalDeviceCmdStatus(c *gin.Context) {
	var data struct {
		DeviceSN  string `json:"-"`
		Status    string `json:"status"`
		Message   string `json:"message"`
		Timestamp int    `json:"timestamp"`
	}
	data.DeviceSN = c.Query("sn")

	if err := c.ShouldBindJSON(&data); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "invalid request"})
		return
	}

	if data.DeviceSN == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
		return
	}

	db := getDB()
	if db == nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	db.Exec(ctx, `CREATE TABLE IF NOT EXISTS device_cmd_logs (
		id BIGSERIAL PRIMARY KEY,
		device_sn VARCHAR(50) NOT NULL,
		command VARCHAR(50),
		status VARCHAR(20) NOT NULL,
		message VARCHAR(200),
		created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
	)`)

	db.Exec(ctx, `INSERT INTO device_cmd_logs (device_sn, status, message, created_at) VALUES ($1, $2, $3, NOW())`,
		data.DeviceSN, data.Status, data.Message)

	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
}

var globalDB *pgxpool.Pool

func SetDB(db *pgxpool.Pool) {
	globalDB = db
}

func getDB() *pgxpool.Pool {
	return globalDB
}

func lineHas(line, substr string) bool {
	for i := 0; i <= len(line)-len(substr); i++ {
		if line[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func (h *AdminHandler) CreateDevice(c *gin.Context) {
	var req struct {
		SN              string  `json:"sn"`
		Model           string  `json:"model"`
		RatedPower      float64 `json:"rated_power"`
		FirmwareVersion string  `json:"firmware_version"`
		HardwareVersion string  `json:"hardware_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if req.SN == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "sn is required"})
		return
	}
	if req.Model == "" {
		req.Model = "INV-5000-TL"
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	_, err := h.db.Exec(ctx, `
		INSERT INTO devices (sn, model, rated_power, firmware_version, hardware_version, user_id, status, deleted_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, 0, 0, NULL, NOW(), NOW())
		ON CONFLICT (sn) DO UPDATE SET model=$2, rated_power=$3, firmware_version=$4, hardware_version=$5, deleted_at=NULL, updated_at=NOW()
	`, req.SN, req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, map[string]interface{}{
		"status":  "ok",
		"message": "device " + req.SN + " created/updated",
	})
}

func (h *AdminHandler) DeleteDevice(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "sn is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	result, err := h.db.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE sn=$1`, sn)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "device not found"})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "device " + sn + " deleted"})
}

func (h *AdminHandler) BatchCreateDevices(c *gin.Context) {
	var req struct {
		Prefix          string `json:"prefix"`
		Count           int    `json:"count"`
		StartSeq        int    `json:"start_seq"`
		Model           string `json:"model"`
		RatedPower      float64 `json:"rated_power"`
		FirmwareVersion string `json:"firmware_version"`
		SNFormat        string `json:"sn_format"`
		Manufacturer    string `json:"manufacturer"`
		Country         string `json:"country"`
		CustomerGrade   string `json:"customer_grade"`
		CustomerNum     int    `json:"customer_num"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if req.Count <= 0 || req.Count > 100000 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "count must be 1-100000"})
		return
	}
	if req.StartSeq <= 0 {
		req.StartSeq = 1
	}
	if req.Model == "" {
		req.Model = "INV-5000-TL"
	}
	if req.SNFormat == "" {
		req.SNFormat = "chenshuo_std"
	}

	now := time.Now()

	ctx, cancel := context.WithTimeout(c.Request.Context(), 60*time.Second)
	defer cancel()

	created := 0
	errors := []string{}

	for i := 0; i < req.Count; i++ {
		var snStr string
		mfr := req.Manufacturer
		if mfr == "" {
			mfr = "H1"
		}
		cty := req.Country
		if cty == "" {
			cty = "CN"
		}
		custGrade := req.CustomerGrade
		if custGrade == "" {
			custGrade = "C"
		}
		custNum := req.CustomerNum
		if custNum <= 0 {
			custNum = 1
		}
		customer := fmt.Sprintf("%s%03d", custGrade, custNum)
		info, genErr := sn.GenerateSN(mfr, cty, customer, now, req.StartSeq+i)
		if genErr != nil {
			errors = append(errors, fmt.Sprintf("seq %d: %s", req.StartSeq+i, genErr.Error()))
			continue
		}
		snStr = info.String()

		_, err := h.db.Exec(ctx, `
			INSERT INTO devices (sn, model, rated_power, firmware_version, user_id, status, created_at, updated_at)
			VALUES ($1, $2, $3, $4, 0, 0, NOW(), NOW())
			ON CONFLICT (sn) DO NOTHING
		`, snStr, req.Model, req.RatedPower, req.FirmwareVersion)
		if err != nil {
			errors = append(errors, snStr+": "+err.Error())
		} else {
			created++
		}
	}

	c.JSON(http.StatusOK, map[string]interface{}{
		"status":  "ok",
		"created": created,
		"errors":  errors,
	})
}

func (h *AdminHandler) BatchDeleteDevices(c *gin.Context) {
	var req struct {
		Manufacturer  string `json:"manufacturer"`
		Country       string `json:"country"`
		CustomerGrade string `json:"customer_grade"`
		CustomerNum   int    `json:"customer_num"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	mfr := req.Manufacturer
	if mfr == "" {
		mfr = "H1"
	}
	cty := req.Country
	if cty == "" {
		cty = "CN"
	}
	custGrade := req.CustomerGrade
	if custGrade == "" {
		custGrade = "C"
	}
	custNum := req.CustomerNum
	if custNum <= 0 {
		custNum = 1
	}
	prefix := fmt.Sprintf("%s%s%s%03d", mfr, cty, custGrade, custNum)

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	result, err := h.db.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE sn LIKE $1 AND deleted_at IS NULL`, prefix+"%")
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}

	deleted := result.RowsAffected()

	c.JSON(http.StatusOK, map[string]interface{}{
		"status":  "ok",
		"deleted": deleted,
	})
}

func (h *AdminHandler) CleanupOldDevices(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	result, err := h.db.Exec(ctx, `UPDATE devices SET deleted_at=NOW() WHERE deleted_at IS NULL AND sn !~ '^[HOS][0-9A-Z][A-Z]{2}[ABCXP][0-9]{3}[1-9A-Z][1-9ABC][0-9]{5}[0-9A-Z]$'`)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}

	c.JSON(http.StatusOK, map[string]interface{}{
		"status":  "ok",
		"deleted": result.RowsAffected(),
	})
}

var startTime = time.Now()

func (h *AdminHandler) SystemInfo(c *gin.Context) {
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	uptime := time.Since(startTime).String()
	c.JSON(http.StatusOK, map[string]interface{}{
		"version":     "1.0.0",
		"uptime":      uptime,
		"go_version":  runtime.Version(),
		"num_cpu":     runtime.NumCPU(),
		"num_goroutine": runtime.NumGoroutine(),
		"alloc_mb":    fmt.Sprintf("%.1f", float64(mem.Alloc)/1024/1024),
		"total_alloc_mb": fmt.Sprintf("%.1f", float64(mem.TotalAlloc)/1024/1024),
		"sys_mb":      fmt.Sprintf("%.1f", float64(mem.Sys)/1024/1024),
		"gc_count":    mem.NumGC,
		"started_at":  startTime.Format("2006-01-02 15:04:05"),
	})
}

func (h *AdminHandler) CreateStation(c *gin.Context) {
	var req struct {
		Name       string  `json:"name"`
		UserID     int64   `json:"user_id"`
		Province   string  `json:"province"`
		City       string  `json:"city"`
		District   string  `json:"district"`
		Address    string  `json:"address"`
		Capacity   float64 `json:"capacity"`
		PanelCount int     `json:"panel_count"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Name == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "name is required"})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	_, err := h.db.Exec(ctx, `INSERT INTO stations (user_id, name, province, city, district, address, capacity, panel_count, status, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,NOW(),NOW())`,
		req.UserID, req.Name, req.Province, req.City, req.District, req.Address, req.Capacity, req.PanelCount)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "station created"})
}

func (h *AdminHandler) UpdateStation(c *gin.Context) {
	var req struct {
		Name       string  `json:"name"`
		Province   string  `json:"province"`
		City       string  `json:"city"`
		District   string  `json:"district"`
		Address    string  `json:"address"`
		Capacity   float64 `json:"capacity"`
		PanelCount int     `json:"panel_count"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	idStr := c.Param("id")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	result, err := h.db.Exec(ctx, `UPDATE stations SET name=$1, province=$2, city=$3, district=$4, address=$5, capacity=$6, panel_count=$7, updated_at=NOW() WHERE id=$8`,
		req.Name, req.Province, req.City, req.District, req.Address, req.Capacity, req.PanelCount, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "station not found"})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "station updated"})
}

func (h *AdminHandler) DeleteStation(c *gin.Context) {
	idStr := c.Param("id")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	result, err := h.db.Exec(ctx, `UPDATE stations SET deleted_at=NOW() WHERE id=$1`, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "station not found"})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "station deleted"})
}

func (h *AdminHandler) HandleAlarm(c *gin.Context) {
	idStr := c.Param("id")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	result, err := h.db.Exec(ctx, `UPDATE alarms SET status=1, updated_at=NOW() WHERE id=$1`, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "alarm not found"})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "alarm handled"})
}

func (h *AdminHandler) UpdateDevice(c *gin.Context) {
	sn := c.Param("sn")
	var req struct {
		Model           string  `json:"model"`
		RatedPower      float64 `json:"rated_power"`
		FirmwareVersion string  `json:"firmware_version"`
		HardwareVersion string  `json:"hardware_version"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	_, err := h.db.Exec(ctx, `UPDATE devices SET model=$1, rated_power=$2, firmware_version=$3, hardware_version=$4, updated_at=NOW() WHERE sn=$5`,
		req.Model, req.RatedPower, req.FirmwareVersion, req.HardwareVersion, sn)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "device updated"})
}

func (h *AdminHandler) UnbindDevice(c *gin.Context) {
	sn := c.Param("sn")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	_, err := h.db.Exec(ctx, `UPDATE devices SET user_id=0, station_id=NULL, updated_at=NOW() WHERE sn=$1`, sn)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "device unbound"})
}

func (h *AdminHandler) CreateUser(c *gin.Context) {
	var req struct {
		Phone    string `json:"phone"`
		Email    string `json:"email"`
		Password string `json:"password"`
		Nickname string `json:"nickname"`
		Role     int    `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "invalid request"})
		return
	}
	if req.Phone == "" && req.Email == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "手机号和邮箱至少填写一个"})
		return
	}
	if req.Password == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "password is required"})
		return
	}
	if len(req.Password) < 6 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "密码长度不能少于6位"})
		return
	}
	if req.Role <= 0 { req.Role = 5 }

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "password encryption failed"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	if req.Phone != "" {
		var existingID int
		err = h.db.QueryRow(ctx, `SELECT id FROM users WHERE phone = $1`, req.Phone).Scan(&existingID)
		if err == nil {
			c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "该手机号已存在（用户ID: " + fmt.Sprintf("%d", existingID) + ")"})
			return
		}
	}

	if req.Email != "" {
		var existingID int
		err = h.db.QueryRow(ctx, `SELECT id FROM users WHERE email = $1`, req.Email).Scan(&existingID)
		if err == nil {
			c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "该邮箱已存在（用户ID: " + fmt.Sprintf("%d", existingID) + ")"})
			return
		}
	}

	var emailVal interface{}
	if req.Email != "" {
		emailVal = req.Email
	}

	_, err = h.db.Exec(ctx, `INSERT INTO users (phone, email, password_hash, nickname, role, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, 1, NOW(), NOW())`,
		req.Phone, emailVal, string(hashedPassword), req.Nickname, req.Role)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "user created"})
}

func (h *AdminHandler) ToggleUserStatus(c *gin.Context) {
	idStr := c.Param("id")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	_, err := h.db.Exec(ctx, `UPDATE users SET status=CASE WHEN status=1 THEN 0 ELSE 1 END, updated_at=NOW() WHERE id=$1`, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "user toggled"})
}

func (h *AdminHandler) UpdateUser(c *gin.Context) {
	idStr := c.Param("id")
	var req struct {
		Nickname string `json:"nickname"`
		Role     int    `json:"role"`
		Phone    string `json:"phone"`
		Email    string `json:"email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	var emailVal interface{}
	if req.Email != "" {
		emailVal = req.Email
	}

	_, err := h.db.Exec(ctx, `UPDATE users SET nickname=$1, role=$2, phone=$3, email=$4, updated_at=NOW() WHERE id=$5`,
		req.Nickname, req.Role, req.Phone, emailVal, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "user updated"})
}

func (h *AdminHandler) DeleteUser(c *gin.Context) {
	idStr := c.Param("id")
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	var count int
	err := h.db.QueryRow(ctx, `SELECT COUNT(*) FROM devices WHERE user_id = $1 AND deleted_at IS NULL`, idStr).Scan(&count)
	if err == nil && count > 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "该用户下还有设备，请先解绑或转移设备后再删除"})
		return
	}

	_, err = h.db.Exec(ctx, `UPDATE users SET deleted_at=NOW(), updated_at=NOW(), status=0, phone=phone||'_del_'||id WHERE id=$1`, idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "user deleted"})
}

func (h *AdminHandler) ResetUserPassword(c *gin.Context) {
	idStr := c.Param("id")
	var req struct {
		NewPassword string `json:"new_password"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.NewPassword == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "new_password is required"})
		return
	}
	if len(req.NewPassword) < 6 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "密码长度不能少于6位"})
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "password encryption failed"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	result, err := h.db.Exec(ctx, `UPDATE users SET password_hash=$1, updated_at=NOW() WHERE id=$2 AND deleted_at IS NULL`, string(hashedPassword), idStr)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "用户不存在"})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "password reset success"})
}

func (h *AdminHandler) MQTTStats(c *gin.Context) {
	resp, err := http.Get("http://127.0.0.1:8081/api/v1/stats/mqtt")
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "device server not reachable: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	var stats map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&stats)
	c.JSON(http.StatusOK, stats)
}

func (h *AdminHandler) DeviceRealtimeData(c *gin.Context) {
	sn := c.Param("sn")
	if sn == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "sn is required"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	var device struct {
		ID              int64      `json:"id"`
		SN              string     `json:"sn"`
		Model           string     `json:"model"`
		RatedPower      float64    `json:"rated_power"`
		FirmwareARM     string     `json:"firmware_arm"`
		FirmwareESP     string     `json:"firmware_esp"`
		HardwareVersion string     `json:"hardware_version"`
		MACAddress      string     `json:"mac_address"`
		StationID       *int64     `json:"station_id"`
		UserID          int64      `json:"user_id"`
		Status          int        `json:"status"`
		LastOnlineAt    *time.Time `json:"last_online_at"`
		CreatedAt       time.Time  `json:"created_at"`
	}
	err := h.db.QueryRow(ctx, `
		SELECT d.id, d.sn, COALESCE(d.model,''), COALESCE(d.rated_power,0),
			   COALESCE(d.firmware_version,''), COALESCE(d.firmware_version,''),
			   COALESCE(d.hardware_version,''), COALESCE(d.mac_address,''),
			   d.station_id, d.user_id,
			   d.status, d.last_online_at, d.created_at
		FROM devices d WHERE d.sn = $1 AND d.deleted_at IS NULL
	`, sn).Scan(
		&device.ID, &device.SN, &device.Model, &device.RatedPower,
		&device.FirmwareARM, &device.FirmwareESP,
		&device.HardwareVersion, &device.MACAddress,
		&device.StationID, &device.UserID, &device.Status,
		&device.LastOnlineAt, &device.CreatedAt,
	)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "device not found"})
		return
	}

	cacheKey := "realtime:latest:" + sn
	if cached, err := h.rdb.Get(ctx, cacheKey).Result(); err == nil && cached != "" {
		var newTelemetry map[string]interface{}
		if json.Unmarshal([]byte(cached), &newTelemetry) == nil {
			newTelemetry["data_time"] = time.Now()
			c.JSON(http.StatusOK, map[string]interface{}{"device": device, "realtime": newTelemetry})
			return
		}
	}

	var telemetryData []byte
	var telemetryTime time.Time
	row := h.db.QueryRow(ctx, `SELECT data, time FROM device_telemetry WHERE device_sn = $1 ORDER BY time DESC LIMIT 1`, sn)
	if err := row.Scan(&telemetryData, &telemetryTime); err == nil && len(telemetryData) > 0 {
		var realtime map[string]interface{}
		json.Unmarshal(telemetryData, &realtime)
		realtime["data_time"] = telemetryTime
		c.JSON(http.StatusOK, map[string]interface{}{"device": device, "realtime": realtime})
		return
	}

	c.JSON(http.StatusOK, map[string]interface{}{"device": device, "realtime": map[string]interface{}{}})
}

func (h *AdminHandler) Models(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `SELECT id, model_code, model_name, manufacturer, category, COALESCE(rated_power_kw,0), is_active, data_fields, field_mapping, created_at FROM device_models ORDER BY model_code`)
	if err != nil {
		c.JSON(http.StatusOK, []interface{}{})
		return
	}
	var models []map[string]interface{}
	for rows.Next() {
		var m struct {
			ID            int64           `json:"id"`
			ModelCode     string          `json:"model_code"`
			ModelName     string          `json:"model_name"`
			Manufacturer  string          `json:"manufacturer"`
			Category      string          `json:"category"`
			RatedPowerKW  float64         `json:"rated_power_kw"`
			IsActive      bool            `json:"is_active"`
			DataFields    json.RawMessage `json:"data_fields"`
			FieldMapping  json.RawMessage `json:"field_mapping"`
			CreatedAt     time.Time       `json:"created_at"`
		}
		rows.Scan(&m.ID, &m.ModelCode, &m.ModelName, &m.Manufacturer, &m.Category, &m.RatedPowerKW, &m.IsActive, &m.DataFields, &m.FieldMapping, &m.CreatedAt)
		models = append(models, map[string]interface{}{
			"id": m.ID, "model_code": m.ModelCode, "model_name": m.ModelName,
			"manufacturer": m.Manufacturer, "category": m.Category,
			"rated_power_kw": m.RatedPowerKW, "is_active": m.IsActive,
			"data_fields": json.RawMessage(m.DataFields), "field_mapping": json.RawMessage(m.FieldMapping),
			"created_at": m.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, models)
}

func (h *AdminHandler) CreateModel(c *gin.Context) {
	var req struct {
		ModelCode    string          `json:"model_code" binding:"required"`
		ModelName    string          `json:"model_name" binding:"required"`
		Manufacturer string          `json:"manufacturer"`
		Category     string          `json:"category"`
		RatedPowerKW float64         `json:"rated_power_kw"`
		DataFields   json.RawMessage `json:"data_fields"`
		FieldMapping json.RawMessage `json:"field_mapping"`
		Description  string          `json:"description"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	if req.Category == "" { req.Category = "inverter" }
	if req.DataFields == nil { req.DataFields = json.RawMessage(`{}`) }
	if req.FieldMapping == nil { req.FieldMapping = json.RawMessage(`{}`) }
	_, err := h.db.Exec(c.Request.Context(),
		`INSERT INTO device_models (model_code, model_name, manufacturer, category, rated_power_kw, data_fields, field_mapping, description) VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8)`,
		req.ModelCode, req.ModelName, req.Manufacturer, req.Category, req.RatedPowerKW, req.DataFields, req.FieldMapping, req.Description)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok", "message": "型号创建成功"})
}

func (h *AdminHandler) UpdateModel(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		ModelName    string          `json:"model_name"`
		Manufacturer string          `json:"manufacturer"`
		Category     string          `json:"category"`
		RatedPowerKW float64         `json:"rated_power_kw"`
		DataFields   json.RawMessage `json:"data_fields"`
		FieldMapping json.RawMessage `json:"field_mapping"`
		Description  string          `json:"description"`
		IsActive     *bool           `json:"is_active"`
	}
	if c.ShouldBindJSON(&req) != nil {}
	_, err := h.db.Exec(c.Request.Context(),
		`UPDATE device_models SET model_name=COALESCE(NULLIF($2,''),model_name), manufacturer=COALESCE(NULLIF($3,''),manufacturer), category=COALESCE(NULLIF($4,''),category), rated_power_kw=COALESCE(NULLIF($5,0),rated_power_kw), data_fields=COALESCE($6::jsonb,data_fields), field_mapping=COALESCE($7::jsonb,field_mapping), description=COALESCE(NULLIF($8,''),description), is_active=COALESCE($9,is_active), updated_at=NOW() WHERE id=$1`,
		id, req.ModelName, req.Manufacturer, req.Category, req.RatedPowerKW, req.DataFields, req.FieldMapping, req.Description, req.IsActive)
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": err.Error()})
		return
	}
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
}

func (h *AdminHandler) DeleteModel(c *gin.Context) {
	id := c.Param("id")
	h.db.Exec(c.Request.Context(), `DELETE FROM device_models WHERE id=$1`, id)
	c.JSON(http.StatusOK, map[string]interface{}{"status": "ok"})
}

func (h *AdminHandler) DeviceCommand(c *gin.Context) {
	sn := c.Param("sn")
	var req struct {
		Command string                 `json:"command"`
		Params  map[string]interface{} `json:"params"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Command == "" {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "command is required"})
		return
	}

	body, _ := json.Marshal(map[string]interface{}{
		"command": req.Command,
		"params":  req.Params,
	})
	resp, err := http.Post("http://127.0.0.1:8081/api/v1/device/"+sn+"/command", "application/json", bytes.NewReader(body))
	if err != nil {
		c.JSON(http.StatusOK, map[string]interface{}{"status": "error", "message": "device server unreachable: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)
	c.JSON(http.StatusOK, result)
}
