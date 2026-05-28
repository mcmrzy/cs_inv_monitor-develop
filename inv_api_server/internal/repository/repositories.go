package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"inv-api-server/internal/model"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

type UserRepository struct {
	db    *pgxpool.Pool
	cache *redis.Client
}

func NewUserRepository(db *pgxpool.Pool, cache *redis.Client) *UserRepository {
	return &UserRepository{db: db, cache: cache}
}

func (r *UserRepository) GetByID(ctx context.Context, id int64) (*model.User, error) {
	query := `
		SELECT id, phone, COALESCE(email,''), password_hash, nickname, avatar, role, region_id, status,
			   last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE id = $1 AND deleted_at IS NULL
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime

	err := r.db.QueryRow(ctx, query, id).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &user.Nickname, &user.Avatar,
		&user.Role, &regionID, &user.Status, &lastLoginAt, &user.LastLoginIP,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if regionID.Valid {
		user.RegionID = &regionID.Int64
	}
	if lastLoginAt.Valid {
		user.LastLoginAt = &lastLoginAt.Time
	}

	return &user, nil
}

func (r *UserRepository) GetByPhone(ctx context.Context, phone string) (*model.User, error) {
	query := `
		SELECT id, phone, COALESCE(email,''), password_hash, nickname, avatar, role, region_id, status,
			   last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE phone = $1 AND deleted_at IS NULL
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime
	var nickname, avatar, lastLoginIP sql.NullString

	err := r.db.QueryRow(ctx, query, phone).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &nickname, &avatar,
		&user.Role, &regionID, &user.Status, &lastLoginAt, &lastLoginIP,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if nickname.Valid {
		user.Nickname = nickname.String
	}
	if avatar.Valid {
		user.Avatar = avatar.String
	}
	if regionID.Valid {
		user.RegionID = &regionID.Int64
	}
	if lastLoginAt.Valid {
		user.LastLoginAt = &lastLoginAt.Time
	}
	if lastLoginIP.Valid {
		user.LastLoginIP = lastLoginIP.String
	}

	return &user, nil
}

func (r *UserRepository) Create(ctx context.Context, user *model.User) error {
	query := `
		INSERT INTO users (phone, email, password_hash, nickname, avatar, role, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`

	var email interface{}
	if user.Email != "" {
		email = user.Email
	}

	return r.db.QueryRow(ctx, query,
		user.Phone, email, user.PasswordHash, user.Nickname, user.Avatar, user.Role, user.Status,
	).Scan(&user.ID, &user.CreatedAt, &user.UpdatedAt)
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*model.User, error) {
	query := `
		SELECT id, phone, COALESCE(email,''), password_hash, nickname, avatar, role, region_id, status,
			   last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE email = $1 AND deleted_at IS NULL
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime
	var nickname, avatar, lastLoginIP sql.NullString

	err := r.db.QueryRow(ctx, query, email).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &nickname, &avatar,
		&user.Role, &regionID, &user.Status, &lastLoginAt, &lastLoginIP,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if nickname.Valid {
		user.Nickname = nickname.String
	}
	if avatar.Valid {
		user.Avatar = avatar.String
	}
	if regionID.Valid {
		user.RegionID = &regionID.Int64
	}
	if lastLoginAt.Valid {
		user.LastLoginAt = &lastLoginAt.Time
	}
	if lastLoginIP.Valid {
		user.LastLoginIP = lastLoginIP.String
	}

	return &user, nil
}

func (r *UserRepository) GetByNickname(ctx context.Context, nickname string) (*model.User, error) {
	query := `
		SELECT id, phone, COALESCE(email,''), password_hash, nickname, avatar, role, region_id, status,
			   last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE nickname = $1 AND deleted_at IS NULL LIMIT 1
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime
	var n, avatar, lastLoginIP sql.NullString

	err := r.db.QueryRow(ctx, query, nickname).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &n, &avatar,
		&user.Role, &regionID, &user.Status, &lastLoginAt, &lastLoginIP,
		&user.CreatedAt, &user.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if n.Valid {
		user.Nickname = n.String
	}
	if avatar.Valid {
		user.Avatar = avatar.String
	}
	if regionID.Valid {
		user.RegionID = &regionID.Int64
	}
	if lastLoginAt.Valid {
		user.LastLoginAt = &lastLoginAt.Time
	}
	if lastLoginIP.Valid {
		user.LastLoginIP = lastLoginIP.String
	}

	return &user, nil
}

func (r *UserRepository) UpdatePassword(ctx context.Context, userID int64, passwordHash string) error {
	query := `UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2`
	_, err := r.db.Exec(ctx, query, passwordHash, userID)
	return err
}

func (r *UserRepository) UpdateProfile(ctx context.Context, userID int64, nickname, avatar string) error {
	query := `UPDATE users SET nickname = $1, avatar = $2, updated_at = NOW() WHERE id = $3`
	_, err := r.db.Exec(ctx, query, nickname, avatar, userID)
	return err
}

func (r *UserRepository) UpdateLoginInfo(ctx context.Context, userID int64, ip string) error {
	query := `UPDATE users SET last_login_at = NOW(), last_login_ip = $1 WHERE id = $2`
	_, err := r.db.Exec(ctx, query, ip, userID)
	return err
}

func (r *UserRepository) Delete(ctx context.Context, userID int64) error {
	query := `UPDATE users SET deleted_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, query, userID)
	return err
}

type StationRepository struct {
	db *pgxpool.Pool
}

func NewStationRepository(db *pgxpool.Pool) *StationRepository {
	return &StationRepository{db: db}
}

func (r *StationRepository) Create(ctx context.Context, station *model.Station) error {
	query := `
		INSERT INTO stations (user_id, name, province, city, district, address, capacity,
							  panel_count, latitude, longitude, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`

	return r.db.QueryRow(ctx, query,
		station.UserID, station.Name, station.Province, station.City, station.District,
		station.Address, station.Capacity, station.PanelCount,
		station.Latitude, station.Longitude, station.Status,
	).Scan(&station.ID, &station.CreatedAt, &station.UpdatedAt)
}

func (r *StationRepository) Update(ctx context.Context, station *model.Station) error {
	query := `
		UPDATE stations SET name = $1, province = $2, city = $3, district = $4, address = $5,
							 capacity = $6, panel_count = $7,
							 latitude = $8, longitude = $9, updated_at = NOW()
		WHERE id = $10
	`

	_, err := r.db.Exec(ctx, query,
		station.Name, station.Province, station.City, station.District, station.Address,
		station.Capacity, station.PanelCount,
		station.Latitude, station.Longitude, station.ID,
	)
	return err
}

func (r *StationRepository) Delete(ctx context.Context, id int64) error {
	query := `UPDATE stations SET deleted_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, query, id)
	return err
}

func (r *StationRepository) GetByID(ctx context.Context, id int64) (*model.Station, error) {
	query := `
		SELECT id, user_id, name, province, city, district, address, capacity,
			   panel_count, latitude, longitude, status, created_at, updated_at
		FROM stations WHERE id = $1 AND deleted_at IS NULL
	`

	var station model.Station
	err := r.db.QueryRow(ctx, query, id).Scan(
		&station.ID, &station.UserID, &station.Name, &station.Province, &station.City,
		&station.District, &station.Address, &station.Capacity, &station.PanelCount,
		&station.Latitude, &station.Longitude,
		&station.Status, &station.CreatedAt, &station.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &station, nil
}

func (r *StationRepository) GetByUserID(ctx context.Context, userID int64, page, pageSize int) ([]*model.Station, int64, error) {
	offset := (page - 1) * pageSize

	countQuery := `SELECT COUNT(*) FROM stations WHERE user_id = $1 AND deleted_at IS NULL`
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, userID).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT id, user_id, name, province, city, district, address, capacity,
			   panel_count, latitude, longitude, status, created_at, updated_at
		FROM stations WHERE user_id = $1 AND deleted_at IS NULL
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := r.db.Query(ctx, query, userID, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	stations := make([]*model.Station, 0)
	for rows.Next() {
		var station model.Station
		if err := rows.Scan(
			&station.ID, &station.UserID, &station.Name, &station.Province, &station.City,
			&station.District, &station.Address, &station.Capacity, &station.PanelCount,
			&station.Latitude, &station.Longitude,
			&station.Status, &station.CreatedAt, &station.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		stations = append(stations, &station)
	}

	return stations, total, nil
}

func (r *StationRepository) GetDayData(ctx context.Context, stationID int64, date string) (*model.StationDayData, error) {
	query := `
		SELECT station_id, data_date, energy_produce, energy_consume, energy_sell, energy_buy,
			   max_power, device_count, online_count, fault_count, income
		FROM station_day_data WHERE station_id = $1 AND data_date = $2
	`

	var data model.StationDayData
	err := r.db.QueryRow(ctx, query, stationID, date).Scan(
		&data.StationID, &data.DataDate, &data.EnergyProduce, &data.EnergyConsume,
		&data.EnergySell, &data.EnergyBuy, &data.MaxPower, &data.DeviceCount,
		&data.OnlineCount, &data.FaultCount, &data.Income,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &data, nil
}

func (r *StationRepository) GetStatistics(ctx context.Context, stationID int64, startDate, endDate, period string) ([]map[string]interface{}, error) {
	// 获取该电站下所有设备的SN
	devicesQuery := `SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL`
	deviceRows, err := r.db.Query(ctx, devicesQuery, stationID)
	if err != nil {
		return nil, err
	}
	defer deviceRows.Close()

	var deviceSns []string
	for deviceRows.Next() {
		var sn string
		if err := deviceRows.Scan(&sn); err != nil {
			return nil, err
		}
		deviceSns = append(deviceSns, sn)
	}

	if len(deviceSns) == 0 {
		return []map[string]interface{}{}, nil
	}

	results := make([]map[string]interface{}, 0)

	switch period {
	case "hour":
		// 按日视图：查询当天24小时每个小时的平均功率
		query := `
			SELECT 
				DATE_TRUNC('hour', telem.time) as hour_time,
				AVG((telem.data->'pv'->>'pv_power')::float) as avg_pv_power,
				AVG((telem.data->'ac'->>'power')::float) as avg_ac_power,
				MAX((telem.data->'energy'->>'daily_pv')::float) as max_daily_pv,
				COUNT(DISTINCT telem.device_sn) as device_count
			FROM device_telemetry telem
			WHERE telem.device_sn = ANY($1)
				AND telem.time >= $2::timestamp
				AND telem.time <= $3::timestamp
				AND telem.data->'pv'->>'pv_power' IS NOT NULL
			GROUP BY DATE_TRUNC('hour', telem.time)
			ORDER BY hour_time
		`
		startTs := startDate + " 00:00:00"
		endTs := endDate + " 23:59:59"
		
		rows, err := r.db.Query(ctx, query, deviceSns, startTs, endTs)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		for rows.Next() {
			var hourTime time.Time
			var avgPvPower, avgAcPower, maxDailyPv float64
			var deviceCount int
			if err := rows.Scan(&hourTime, &avgPvPower, &avgAcPower, &maxDailyPv, &deviceCount); err != nil {
				return nil, err
			}
			results = append(results, map[string]interface{}{
				"time":            hourTime,
				"energy_produce":  avgPvPower,
				"energy_consume":  avgAcPower,
				"daily_pv":        maxDailyPv,
			})
		}

	default:
		// 按月/年视图：查询每天的累计发电量
		query := `
			SELECT 
				DATE(telem.time) as day_date,
				MAX((telem.data->'energy'->>'daily_pv')::float) as max_daily_pv,
				MAX((telem.data->'ac'->>'power')::float) as max_ac_power,
				COUNT(DISTINCT telem.device_sn) as device_count
			FROM device_telemetry telem
			WHERE telem.device_sn = ANY($1)
				AND telem.time >= $2::timestamp
				AND telem.time <= $3::timestamp
				AND telem.data->'energy'->>'daily_pv' IS NOT NULL
			GROUP BY DATE(telem.time)
			ORDER BY day_date
		`
		endTs := endDate + " 23:59:59"
		
		rows, err := r.db.Query(ctx, query, deviceSns, startDate, endTs)
		if err != nil {
			return nil, err
		}
		defer rows.Close()

		for rows.Next() {
			var dayDate time.Time
			var maxDailyPv, maxAcPower float64
			var deviceCount int
			if err := rows.Scan(&dayDate, &maxDailyPv, &maxAcPower, &deviceCount); err != nil {
				return nil, err
			}
			results = append(results, map[string]interface{}{
				"time":            dayDate,
				"energy_produce":  maxDailyPv,
				"energy_consume":  maxAcPower,
				"daily_pv":        maxDailyPv,
			})
		}
	}

	return results, nil
}

type DeviceRepository struct {
	db    *pgxpool.Pool
	cache *redis.Client
}

func NewDeviceRepository(db *pgxpool.Pool, cache *redis.Client) *DeviceRepository {
	return &DeviceRepository{db: db, cache: cache}
}

func (r *DeviceRepository) GetBySN(ctx context.Context, sn string) (*model.Device, error) {
	query := `
		SELECT id, sn, model, rated_power, firmware_version, hardware_version,
			   mac_address, station_id, user_id, status, last_online_at, created_at, updated_at
		FROM devices WHERE sn = $1 AND deleted_at IS NULL
	`

	var device model.Device
	var model sql.NullString
	var ratedPower sql.NullFloat64
	var firmwareVersion sql.NullString
	var hardwareVersion sql.NullString
	var macAddress sql.NullString
	var stationID sql.NullInt64
	var lastOnlineAt sql.NullTime

	err := r.db.QueryRow(ctx, query, sn).Scan(
		&device.ID, &device.SN, &model, &ratedPower,
		&firmwareVersion, &hardwareVersion, &macAddress,
		&stationID, &device.UserID, &device.Status, &lastOnlineAt,
		&device.CreatedAt, &device.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if model.Valid {
		device.Model = model.String
	}
	if ratedPower.Valid {
		device.RatedPower = ratedPower.Float64
	}
	if firmwareVersion.Valid {
		device.FirmwareVersion = firmwareVersion.String
	}
	if hardwareVersion.Valid {
		device.HardwareVersion = hardwareVersion.String
	}
	if macAddress.Valid {
		device.MACAddress = macAddress.String
	}
	if stationID.Valid {
		device.StationID = &stationID.Int64
	}
	if lastOnlineAt.Valid {
		device.LastOnlineAt = &lastOnlineAt.Time
	}

	return &device, nil
}

func (r *DeviceRepository) GetByUserID(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	offset := (page - 1) * pageSize

	baseQuery := `FROM devices WHERE user_id = $1 AND deleted_at IS NULL`
	args := []interface{}{userID}
	argIdx := 2

	if stationID > 0 {
		baseQuery += fmt.Sprintf(" AND station_id = $%d", argIdx)
		args = append(args, stationID)
		argIdx++
	}

	if status >= 0 {
		baseQuery += fmt.Sprintf(" AND status = $%d", argIdx)
		args = append(args, status)
		argIdx++
	}

	countQuery := `SELECT COUNT(*) ` + baseQuery
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT id, sn, model, rated_power, firmware_version, hardware_version,
			   mac_address, station_id, user_id, status, last_online_at, created_at, updated_at
	` + baseQuery + ` ORDER BY created_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)

	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	devices := make([]*model.Device, 0)
	for rows.Next() {
		var device model.Device
		var model sql.NullString
		var ratedPower sql.NullFloat64
		var firmwareVersion sql.NullString
		var hardwareVersion sql.NullString
		var macAddress sql.NullString
		var stationID sql.NullInt64
		var lastOnlineAt sql.NullTime
		if err := rows.Scan(
			&device.ID, &device.SN, &model, &ratedPower,
			&firmwareVersion, &hardwareVersion, &macAddress,
			&stationID, &device.UserID, &device.Status, &lastOnlineAt,
			&device.CreatedAt, &device.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		if model.Valid {
			device.Model = model.String
		}
		if ratedPower.Valid {
			device.RatedPower = ratedPower.Float64
		}
		if firmwareVersion.Valid {
			device.FirmwareVersion = firmwareVersion.String
		}
		if hardwareVersion.Valid {
			device.HardwareVersion = hardwareVersion.String
		}
		if macAddress.Valid {
			device.MACAddress = macAddress.String
		}
		if stationID.Valid {
			device.StationID = &stationID.Int64
		}
		if lastOnlineAt.Valid {
			device.LastOnlineAt = &lastOnlineAt.Time
		}
		devices = append(devices, &device)
	}

	return devices, total, nil
}

func (r *DeviceRepository) GetByStationID(ctx context.Context, stationID int64) ([]*model.Device, error) {
	query := `
		SELECT id, sn, model, rated_power, firmware_version, hardware_version,
			   mac_address, station_id, user_id, status, last_online_at, created_at, updated_at
		FROM devices WHERE station_id = $1 AND deleted_at IS NULL
	`

	rows, err := r.db.Query(ctx, query, stationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	devices := make([]*model.Device, 0)
	for rows.Next() {
		var device model.Device
		var model sql.NullString
		var ratedPower sql.NullFloat64
		var firmwareVersion sql.NullString
		var hardwareVersion sql.NullString
		var macAddress sql.NullString
		var stationID sql.NullInt64
		var lastOnlineAt sql.NullTime
		if err := rows.Scan(
			&device.ID, &device.SN, &model, &ratedPower,
			&firmwareVersion, &hardwareVersion, &macAddress,
			&stationID, &device.UserID, &device.Status, &lastOnlineAt,
			&device.CreatedAt, &device.UpdatedAt,
		); err != nil {
			return nil, err
		}
		if model.Valid {
			device.Model = model.String
		}
		if ratedPower.Valid {
			device.RatedPower = ratedPower.Float64
		}
		if firmwareVersion.Valid {
			device.FirmwareVersion = firmwareVersion.String
		}
		if hardwareVersion.Valid {
			device.HardwareVersion = hardwareVersion.String
		}
		if macAddress.Valid {
			device.MACAddress = macAddress.String
		}
		if stationID.Valid {
			device.StationID = &stationID.Int64
		}
		if lastOnlineAt.Valid {
			device.LastOnlineAt = &lastOnlineAt.Time
		}
		devices = append(devices, &device)
	}

	return devices, nil
}

func (r *DeviceRepository) GetStationRealtimeSummary(ctx context.Context, stationID int64) (float64, float64, error) {
	var dailyEnergy float64
	query := `
		SELECT COALESCE(SUM(energy_produce), 0)
		FROM device_day_data
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status = 1)
		AND data_date = CURRENT_DATE
	`
	r.db.QueryRow(ctx, query, stationID).Scan(&dailyEnergy)

	var totalPower float64
	sns, err := r.getStationDeviceSNs(ctx, stationID, true)
	if err == nil && r.cache != nil {
		for _, sn := range sns {
			raw, err := r.cache.Get(ctx, "realtime:latest:"+sn).Result()
			if err != nil || raw == "" {
				continue
			}
			var m map[string]interface{}
			if json.Unmarshal([]byte(raw), &m) != nil {
				continue
			}
			if ac, ok := m["ac"].(map[string]interface{}); ok {
				if p, ok := ac["power"].(float64); ok {
					totalPower += p
				}
			}
		}
	}

	return dailyEnergy, totalPower, nil
}

func (r *DeviceRepository) getStationDeviceSNs(ctx context.Context, stationID int64, onlineOnly bool) ([]string, error) {
	baseQuery := `SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL`
	if onlineOnly {
		baseQuery += ` AND status = 1`
	}
	rows, err := r.db.Query(ctx, baseQuery, stationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var sns []string
	for rows.Next() {
		var sn string
		if err := rows.Scan(&sn); err != nil {
			continue
		}
		sns = append(sns, sn)
	}
	return sns, nil
}

func (r *DeviceRepository) GetStationPowerBreakdown(ctx context.Context, stationID int64) (pvPower float64, loadPower float64, gridPower float64, battPower float64, battSoc float64) {
	sns, err := r.getStationDeviceSNs(ctx, stationID, true)
	if err != nil {
		return
	}

	var socSum float64
	var socCount int
	redisHit := false

	if r.cache != nil {
		for _, sn := range sns {
			raw, err := r.cache.Get(ctx, "realtime:latest:"+sn).Result()
			if err != nil || raw == "" {
				continue
			}
			var m map[string]interface{}
			if json.Unmarshal([]byte(raw), &m) != nil {
				continue
			}

			if pv, ok := m["pv"].(map[string]interface{}); ok {
				if p, ok := pv["pv_power"].(float64); ok {
					pvPower += p
					redisHit = true
				}
			}
			if ac, ok := m["ac"].(map[string]interface{}); ok {
				if p, ok := ac["power"].(float64); ok {
					loadPower += p
					redisHit = true
				}
			}
			if batt, ok := m["battery"].(map[string]interface{}); ok {
				v, _ := batt["voltage"].(float64)
				c, _ := batt["current"].(float64)
				battPower += v * c
				redisHit = true
				if s, ok := batt["soc"].(float64); ok {
					socSum += s
					socCount++
				}
			}
		}
	}

	if redisHit {
		if socCount > 0 {
			battSoc = socSum / float64(socCount)
		}
		gridPower = 0
		return
	}

	query := `
		SELECT COALESCE(SUM(COALESCE(pv1_power, 0)), 0),
			   COALESCE(SUM(COALESCE(output_power, COALESCE(total_active_power, 0))), 0),
			   COALESCE(SUM(COALESCE(battery_voltage, 0) * COALESCE(battery_current, 0)), 0),
			   COALESCE(AVG(NULLIF(battery_soc, 0)), 0)
		FROM device_realtime_data
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status = 1)
	`
	if err := r.db.QueryRow(ctx, query, stationID).Scan(&pvPower, &loadPower, &battPower, &battSoc); err != nil {
		return
	}
	gridPower = 0
	return
}

func (r *DeviceRepository) GetStationEnergySummary(ctx context.Context, stationID int64) (float64, float64) {
	query := `
		SELECT COALESCE(SUM(energy_produce), 0),
			   COALESCE(SUM(CASE WHEN data_date >= DATE_TRUNC('month', CURRENT_DATE) THEN energy_produce ELSE 0 END), 0)
		FROM device_day_data
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
	`
	var totalEnergy, monthEnergy float64
	r.db.QueryRow(ctx, query, stationID).Scan(&totalEnergy, &monthEnergy)
	return totalEnergy, monthEnergy
}

func (r *DeviceRepository) GetStationYearEnergy(ctx context.Context, stationID int64) float64 {
	query := `
		SELECT COALESCE(SUM(energy_produce), 0)
		FROM device_day_data
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
		AND data_date >= DATE_TRUNC('year', CURRENT_DATE)
	`
	var yearEnergy float64
	r.db.QueryRow(ctx, query, stationID).Scan(&yearEnergy)
	return yearEnergy
}

func (r *DeviceRepository) GetStationTodayEnergy(ctx context.Context, stationID int64) (float64, error) {
	query := `
		SELECT COALESCE(SUM(energy_produce), 0)
		FROM device_day_data
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
		AND data_date = CURRENT_DATE
	`
	var energy float64
	err := r.db.QueryRow(ctx, query, stationID).Scan(&energy)
	return energy, err
}

func (r *DeviceRepository) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	online := false
	var deviceStatus int
	err := r.db.QueryRow(ctx, `SELECT status FROM devices WHERE sn=$1 AND deleted_at IS NULL`, sn).Scan(&deviceStatus)
	if err == nil && deviceStatus == 1 {
		online = true
	}

	if r.cache != nil {
		for _, cacheKey := range []string{"realtime:latest:" + sn, "telemetry:latest:" + sn} {
			cached, err := r.cache.Get(ctx, cacheKey).Result()
			if err != nil || cached == "" {
				continue
			}
			var m map[string]interface{}
			if json.Unmarshal([]byte(cached), &m) == nil {
				fmt.Printf("[DEBUG] GetRealtimeData - Redis cache hit for key: %s, has ac field: %v\n", cacheKey, m["ac"] != nil)
				m["online"] = online
				m["data_source"] = "redis"
				return m, nil
			}
		}
	}

	var rawJSON []byte
	err = r.db.QueryRow(ctx, `SELECT data FROM device_telemetry WHERE device_sn = $1 ORDER BY time DESC LIMIT 1`, sn).Scan(&rawJSON)
	if err != nil {
		if err == pgx.ErrNoRows {
			return map[string]interface{}{"device_sn": sn, "online": online}, nil
		}
		return nil, err
	}

	var m map[string]interface{}
	if err := json.Unmarshal(rawJSON, &m); err != nil {
		return nil, err
	}

	fmt.Printf("[DEBUG] GetRealtimeData - DB query result, has ac field: %v, top-level keys: ", m["ac"] != nil)
	for k := range m {
		fmt.Printf("%s ", k)
	}
	fmt.Println()

	m["online"] = online
	m["data_source"] = "database"
	return m, nil
}

// DEPRECATED: flattenDeviceRealtime is no longer used.
// The API now returns the original nested MQTT JSON structure directly.
// This function was used to flatten the nested structure to a flat format,
// but it caused data mismatch issues with off-grid inverters.
// Kept here for reference only.
/*
func flattenDeviceRealtime(m map[string]interface{}) {
	copyNested := func(key string, fields map[string]string) {
		nested, ok := m[key]
		if !ok {
			return
		}
		nm, ok2 := nested.(map[string]interface{})
		if !ok2 {
			return
		}
		for from, to := range fields {
			if v, exists := nm[from]; exists {
				m[to] = v
			}
		}
	}

	copyNested("ac", map[string]string{
		"voltage": "ac_voltage", "current": "ac_current",
		"power": "ac_power", "frequency": "ac_frequency", "load_percent": "load_percent",
	})

	copyNested("battery", map[string]string{
		"voltage": "battery_voltage", "current": "battery_current",
		"soc": "battery_soc", "soh": "battery_soh", "charge_state": "charge_state",
	})

	copyNested("pv", map[string]string{
		"pv_voltage": "pv_voltage", "pv_current": "pv_current", "pv_power": "pv_power",
	})

	copyNested("sys_status", map[string]string{
		"state": "work_state", "fault_code": "fault_code",
		"temp_inv": "internal_temperature", "efficiency": "efficiency",
	})

	copyNested("energy", map[string]string{
		"daily_pv": "daily_power_yields", "total_pv": "total_power_yields",
		"runtime_hours": "total_running_time",
	})

	if v, ok := m["device_sn"]; ok {
		if _, exists := m["serial_number"]; !exists {
			m["serial_number"] = v
		}
	}
	if v, ok := m["updated_at"]; ok {
		if _, exists := m["data_time"]; !exists {
			m["data_time"] = v
		}
	}
}

// DEPRECATED: mapToRealtimeData is no longer used.
// The API now returns the original nested MQTT JSON structure directly.
// This function was used to map flattened data to DeviceRealtimeData struct,
// which was designed for grid-tied inverters with 60+ flat fields.
// Kept here for reference only.
func mapToRealtimeData(sn string, m map[string]interface{}) *model.DeviceRealtimeData {
	getFloat := func(k string) float64 {
		if v, ok := m[k]; ok {
			switch vv := v.(type) {
			case float64: return vv
			case string: var f float64; fmt.Sscanf(vv, "%f", &f); return f
			case json.Number: f, _ := vv.Float64(); return f
			}
		}
		return 0
	}
	getInt := func(k string) int {
		if v, ok := m[k]; ok {
			switch vv := v.(type) {
			case float64: return int(vv)
			case string: var n int; fmt.Sscanf(vv, "%d", &n); return n
			case json.Number: n, _ := vv.Int64(); return int(n)
			}
		}
		return 0
	}
	getStr := func(k string) string {
		if v, ok := m[k]; ok { return fmt.Sprint(v) }
		return ""
	}
	getFloatOr := func(fn func(string) float64, k1, k2 string) float64 {
		if v := fn(k1); v != 0 { return v }
		return fn(k2)
	}
	getStrOr := func(fn func(string) string, k1, k2 string) string {
		if v := fn(k1); v != "" { return v }
		return fn(k2)
	}

	return &model.DeviceRealtimeData{
		DeviceSN:             sn,
		DataTime:             time.Now(),
		Manufacturer:         getStr("manufacturer"),
		Model:                getStr("model"),
		DeviceTypeCode:       getInt("device_type_code"),
		ArmVersion:           getStr("arm_version"),
		DSPVersion:           getStr("dsp_version"),
		ProtocolNumber:       getInt("protocol_number"),
		ProtocolVersion:      getInt("protocol_version"),
		NominalActivePower:   getFloat("nominal_active_power"),
		NominalReactivePower: getFloat("nominal_reactive_power"),
		OutputType:           getInt("output_type"),
		DailyPowerYields:     getFloat("daily_power_yields"),
		TotalPowerYields:     getFloat("total_power_yields"),
		TotalPowerYields01:   getFloat("total_power_yields_01"),
		MonthlyPowerYields:   getFloat("monthly_power_yields"),
		TotalRunningTime:     getInt("total_running_time"),
		DailyRunningTime:     getInt("daily_running_time"),
		InternalTemperature:  getFloat("internal_temperature"),
		TotalDCPower:         getFloat("total_dc_power"),
		PhaseAVoltage:        getFloat("phase_a_voltage"),
		PhaseBVoltage:        getFloat("phase_b_voltage"),
		PhaseCVoltage:        getFloat("phase_c_voltage"),
		PhaseACurrent:        getFloat("phase_a_current"),
		PhaseBCurrent:        getFloat("phase_b_current"),
		PhaseCCurrent:        getFloat("phase_c_current"),
		TotalActivePower:     getFloat("total_active_power"),
		TotalReactivePower:   getFloat("total_reactive_power"),
		TotalApparentPower:   getFloat("total_apparent_power"),
		PowerFactor:          getFloat("power_factor"),
		GridFrequency:        getFloatOr(getFloat, "grid_frequency", "frequency"),
		WorkState1:           getStrOr(getStr, "work_state_1", "work_state"),
		WorkState1Code:       getInt("work_state_1_code"),
		WorkState2:           getInt("work_state_2"),
		InverterState1:       getInt("inverter_state_1"),
		InverterState2:       getInt("inverter_state_2"),
		InsulationResistance: getInt("insulation_resistance"),
		BusVoltage:           getFloat("bus_voltage"),
		NegativeGroundVoltage: getFloat("negative_ground_voltage"),
		PIDWorkState:         getInt("pid_work_state"),
		PIDAlarmCode:          getInt("pid_alarm_code"),
		CountryCode:           getInt("country_code"),
		MeterTotalPower:       getFloat("meter_total_power"),
		MeterPhaseAPower:      getFloat("meter_phase_a_power"),
		MeterPhaseBPower:      getFloat("meter_phase_b_power"),
		MeterPhaseCPower:      getFloat("meter_phase_c_power"),
		LoadPower:             getFloat("load_power"),
		DailyFeedEnergy:       getFloat("daily_feed_energy"),
		TotalFeedEnergy:        getFloat("total_feed_energy"),
		DailyGridImport:       getFloat("daily_grid_import"),
		TotalGridImport:        getFloat("total_grid_import"),
		ActivePowerSetting:    getFloat("active_power_setting"),
		ReactivePowerSetting:   getFloat("reactive_power_setting"),
		PowerFactorSetting:     getFloat("power_factor_setting"),
		ESP32Timestamp:         getInt("esp32_timestamp"),
	}
}
*/

func (r *DeviceRepository) EnsureDevice(ctx context.Context, sn string) error {
	query := `INSERT INTO devices (sn, model, rated_power, firmware_version, user_id, status, created_at, updated_at)
		VALUES ($1, 'INV-5000-TL', 0, '', 0, 0, NOW(), NOW())
		ON CONFLICT (sn) DO NOTHING`
	_, err := r.db.Exec(ctx, query, sn)
	return err
}

func (r *DeviceRepository) Bind(ctx context.Context, sn string, userID, stationID int64) error {
	query := `UPDATE devices SET user_id = $1, station_id = $2, updated_at = NOW() WHERE sn = $3`
	_, err := r.db.Exec(ctx, query, userID, stationID, sn)
	return err
}

func (r *DeviceRepository) Unbind(ctx context.Context, sn string) error {
	query := `UPDATE devices SET user_id = NULL, station_id = NULL, updated_at = NOW() WHERE sn = $1`
	_, err := r.db.Exec(ctx, query, sn)
	return err
}

func (r *DeviceRepository) AddToStation(ctx context.Context, sn string, stationID int64) error {
	query := `UPDATE devices SET station_id = $1, updated_at = NOW() WHERE sn = $2`
	_, err := r.db.Exec(ctx, query, stationID, sn)
	return err
}

func (r *DeviceRepository) MarkStaleDevicesOffline(ctx context.Context, timeoutSeconds int) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT sn FROM devices WHERE status=1 AND last_online_at < NOW() - MAKE_INTERVAL(secs => $1)`, timeoutSeconds)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sns []string
	for rows.Next() {
		var sn string
		if err := rows.Scan(&sn); err != nil {
			continue
		}
		sns = append(sns, sn)
	}

	if len(sns) > 0 {
		r.db.Exec(ctx, `UPDATE devices SET status=0, updated_at=NOW() WHERE status=1 AND last_online_at < NOW() - MAKE_INTERVAL(secs => $1)`, timeoutSeconds)
	}

	return sns, nil
}

func (r *DeviceRepository) SyncStationStatus(ctx context.Context) error {
	_, err := r.db.Exec(ctx, `
		UPDATE stations SET
			status = CASE
				WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status = 1 AND devices.deleted_at IS NULL) THEN 1
				ELSE 0
			END,
			updated_at = NOW()
		WHERE deleted_at IS NULL
	`)
	return err
}

func (r *DeviceRepository) GetShare(ctx context.Context, sn string, userID int64) (*model.DeviceShare, error) {
	query := `
		SELECT id, device_sn, owner_id, share_to_user_id, permission, created_at
		FROM device_shares WHERE device_sn = $1 AND share_to_user_id = $2
	`

	var share model.DeviceShare
	err := r.db.QueryRow(ctx, query, sn, userID).Scan(
		&share.ID, &share.DeviceSN, &share.OwnerID, &share.ShareToUserID, &share.Permission, &share.CreatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	return &share, nil
}

func (r *DeviceRepository) GetParams(ctx context.Context, sn string) (map[string]interface{}, error) {
	query := `SELECT * FROM device_params WHERE device_sn = $1`

	rows, err := r.db.Query(ctx, query, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	if !rows.Next() {
		return make(map[string]interface{}), nil
	}

	fields := rows.FieldDescriptions()
	values := make([]interface{}, len(fields))
	valuePtrs := make([]interface{}, len(fields))
	for i := range values {
		valuePtrs[i] = &values[i]
	}

	if err := rows.Scan(valuePtrs...); err != nil {
		return nil, err
	}

	result := make(map[string]interface{})
	for i, field := range fields {
		result[string(field.Name)] = values[i]
	}

	return result, nil
}

func (r *DeviceRepository) UpdateParams(ctx context.Context, sn string, params map[string]interface{}) error {
	query := `
		INSERT INTO device_params (device_sn, updated_at)
		VALUES ($1, NOW())
		ON CONFLICT (device_sn) DO UPDATE SET updated_at = NOW()
	`
	_, err := r.db.Exec(ctx, query, sn)
	return err
}

func (r *DeviceRepository) SendCommand(ctx context.Context, sn, cmdType string, params map[string]interface{}) error {
	cmdData, _ := json.Marshal(map[string]interface{}{
		"cmd_type": cmdType,
		"params":   params,
		"req_id":   fmt.Sprintf("%d", time.Now().UnixNano()),
	})

	return r.cache.Publish(ctx, "device:cmd:"+sn, cmdData).Err()
}

func (r *DeviceRepository) GetHistoryData(ctx context.Context, sn, startDate, endDate, period string) ([]map[string]interface{}, error) {
	var query string
	switch period {
	case "hour":
		query = `
			SELECT data_time, avg_power, max_power, energy_produce, energy_consume, energy_sell, energy_buy, avg_soc
			FROM device_hour_data WHERE device_sn = $1 AND data_time >= $2 AND data_time <= $3
			ORDER BY data_time
		`
	default:
		query = `
			SELECT data_date, max_power, energy_produce, energy_consume, energy_sell, energy_buy, avg_soc, income
			FROM device_day_data WHERE device_sn = $1 AND data_date >= $2 AND data_date <= $3
			ORDER BY data_date
		`
	}

	rows, err := r.db.Query(ctx, query, sn, startDate, endDate)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := make([]map[string]interface{}, 0)
	for rows.Next() {
		result := make(map[string]interface{})
		var dataTime time.Time
		var avgPower, maxPower, energyProduce, energyConsume, energySell, energyBuy, income float64
		var avgSOC int

		if period == "hour" {
			if err := rows.Scan(&dataTime, &avgPower, &maxPower, &energyProduce, &energyConsume, &energySell, &energyBuy, &avgSOC); err != nil {
				return nil, err
			}
			result["avg_power"] = avgPower
		} else {
			if err := rows.Scan(&dataTime, &maxPower, &energyProduce, &energyConsume, &energySell, &energyBuy, &avgSOC, &income); err != nil {
				return nil, err
			}
			result["income"] = income
		}

		result["time"] = dataTime
		result["max_power"] = maxPower
		result["energy_produce"] = energyProduce
		result["energy_consume"] = energyConsume
		result["energy_sell"] = energySell
		result["energy_buy"] = energyBuy
		result["avg_soc"] = avgSOC

		results = append(results, result)
	}

	return results, nil
}

func (r *DeviceRepository) GetStatistics(ctx context.Context, sn, startDate, endDate, period string) (map[string]interface{}, error) {
	query := `
		SELECT COALESCE(SUM(energy_produce), 0), COALESCE(SUM(energy_consume), 0),
			   COALESCE(SUM(energy_sell), 0), COALESCE(SUM(energy_buy), 0), COALESCE(SUM(income), 0)
		FROM device_day_data WHERE device_sn = $1 AND data_date >= $2 AND data_date <= $3
	`

	var energyProduce, energyConsume, energySell, energyBuy, income float64
	err := r.db.QueryRow(ctx, query, sn, startDate, endDate).Scan(
		&energyProduce, &energyConsume, &energySell, &energyBuy, &income,
	)

	if err != nil {
		return nil, err
	}

	return map[string]interface{}{
		"energy_produce": energyProduce,
		"energy_consume": energyConsume,
		"energy_sell":    energySell,
		"energy_buy":     energyBuy,
		"income":         income,
	}, nil
}

func (r *DeviceRepository) Share(ctx context.Context, sn string, ownerID int64, phone, permission string) error {
	var shareToUserID int64
	err := r.db.QueryRow(ctx, `SELECT id FROM users WHERE phone = $1`, phone).Scan(&shareToUserID)
	if err != nil {
		return fmt.Errorf("user not found")
	}

	query := `
		INSERT INTO device_shares (device_sn, owner_id, share_to_user_id, permission, created_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (device_sn, share_to_user_id) DO UPDATE SET permission = $4
	`

	_, err = r.db.Exec(ctx, query, sn, ownerID, shareToUserID, permission)
	return err
}

func (r *DeviceRepository) CancelShare(ctx context.Context, shareID, ownerID int64) error {
	query := `DELETE FROM device_shares WHERE id = $1 AND owner_id = $2`
	_, err := r.db.Exec(ctx, query, shareID, ownerID)
	return err
}

func (r *DeviceRepository) GetShares(ctx context.Context, sn string) ([]*model.DeviceShare, error) {
	query := `
		SELECT ds.id, ds.device_sn, ds.owner_id, ds.share_to_user_id, ds.permission, ds.created_at
		FROM device_shares ds WHERE ds.device_sn = $1
	`

	rows, err := r.db.Query(ctx, query, sn)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	shares := make([]*model.DeviceShare, 0)
	for rows.Next() {
		var share model.DeviceShare
		if err := rows.Scan(
			&share.ID, &share.DeviceSN, &share.OwnerID, &share.ShareToUserID, &share.Permission, &share.CreatedAt,
		); err != nil {
			return nil, err
		}
		shares = append(shares, &share)
	}

	return shares, nil
}

func (r *DeviceRepository) GetOverview(ctx context.Context, userID int64) (map[string]interface{}, error) {
	query := `
		SELECT COUNT(DISTINCT d.id) as device_count,
			   COUNT(DISTINCT CASE WHEN d.status = 1 THEN d.id END) as online_count,
			   COUNT(DISTINCT CASE WHEN d.status = 2 THEN d.id END) as fault_count,
			   COALESCE(SUM(dd.energy_produce), 0) as today_energy,
			   COALESCE(SUM(dd.income), 0) as today_income
		FROM devices d
		LEFT JOIN device_day_data dd ON dd.device_sn = d.sn AND dd.data_date = CURRENT_DATE
		WHERE d.user_id = $1 AND d.deleted_at IS NULL
	`

	result := make(map[string]interface{})
	var deviceCount, onlineCount, faultCount int
	var todayEnergy, todayIncome float64

	err := r.db.QueryRow(ctx, query, userID).Scan(&deviceCount, &onlineCount, &faultCount, &todayEnergy, &todayIncome)
	if err != nil {
		return nil, err
	}

	result["device_count"] = deviceCount
	result["online_count"] = onlineCount
	result["fault_count"] = faultCount
	result["today_energy"] = todayEnergy
	result["today_income"] = todayIncome

	return result, nil
}

func (r *DeviceRepository) GetTrend(ctx context.Context, userID int64, period string) ([]map[string]interface{}, error) {
	query := `
		SELECT dd.data_date, SUM(dd.energy_produce) as energy_produce, SUM(dd.income) as income
		FROM device_day_data dd
		JOIN devices d ON d.sn = dd.device_sn
		WHERE d.user_id = $1 AND d.deleted_at IS NULL
		AND dd.data_date >= CURRENT_DATE - INTERVAL '30 days'
		GROUP BY dd.data_date ORDER BY dd.data_date
	`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := make([]map[string]interface{}, 0)
	for rows.Next() {
		var dataDate time.Time
		var energyProduce, income float64
		if err := rows.Scan(&dataDate, &energyProduce, &income); err != nil {
			return nil, err
		}
		results = append(results, map[string]interface{}{
			"date":           dataDate,
			"energy_produce": energyProduce,
			"income":         income,
		})
	}

	return results, nil
}

func (r *DeviceRepository) StartOTA(ctx context.Context, sn string, firmwareID int64) error {
	query := `
		INSERT INTO ota_records (device_sn, firmware_id, status, created_at)
		VALUES ($1, $2, 'pending', NOW())
	`
	_, err := r.db.Exec(ctx, query, sn, firmwareID)
	return err
}

func (r *DeviceRepository) GetOTAStatus(ctx context.Context, sn string) (map[string]interface{}, error) {
	query := `
		SELECT id, firmware_id, status, progress, error_message, started_at, completed_at
		FROM ota_records WHERE device_sn = $1 ORDER BY created_at DESC LIMIT 1
	`

	var id, firmwareID int64
	var status string
	var progress int
	var errorMsg sql.NullString
	var startedAt, completedAt sql.NullTime

	err := r.db.QueryRow(ctx, query, sn).Scan(&id, &firmwareID, &status, &progress, &errorMsg, &startedAt, &completedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return map[string]interface{}{"status": "none"}, nil
		}
		return nil, err
	}

	result := map[string]interface{}{
		"id":          id,
		"firmware_id": firmwareID,
		"status":      status,
		"progress":    progress,
	}

	if errorMsg.Valid {
		result["error_message"] = errorMsg.String
	}
	if startedAt.Valid {
		result["started_at"] = startedAt.Time
	}
	if completedAt.Valid {
		result["completed_at"] = completedAt.Time
	}

	return result, nil
}

type AlarmRepository struct {
	db *pgxpool.Pool
}

func NewAlarmRepository(db *pgxpool.Pool) *AlarmRepository {
	return &AlarmRepository{db: db}
}

func (r *AlarmRepository) List(ctx context.Context, userID int64, stationID int64, status, page, pageSize int) ([]*model.Alarm, int64, error) {
	offset := (page - 1) * pageSize

	baseQuery := `FROM alarms WHERE user_id = $1`
	args := []interface{}{userID}
	argIdx := 2

	if stationID > 0 {
		baseQuery += fmt.Sprintf(" AND station_id = $%d", argIdx)
		args = append(args, stationID)
		argIdx++
	}

	if status >= 0 {
		baseQuery += fmt.Sprintf(" AND status = $%d", argIdx)
		args = append(args, status)
		argIdx++
	}

	countQuery := `SELECT COUNT(*) ` + baseQuery
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT id, device_sn, station_id, user_id, alarm_level, fault_code, fault_message,
			   fault_detail, status, occurred_at, recovered_at, handled_at, handled_by, created_at
	` + baseQuery + ` ORDER BY occurred_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)

	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	alarms := make([]*model.Alarm, 0)
	for rows.Next() {
		var alarm model.Alarm
		var stationID, handledBy sql.NullInt64
		var recoveredAt, handledAt sql.NullTime
		var faultDetail sql.NullString

		if err := rows.Scan(
			&alarm.ID, &alarm.DeviceSN, &stationID, &alarm.UserID, &alarm.AlarmLevel,
			&alarm.FaultCode, &alarm.FaultMessage, &faultDetail, &alarm.Status,
			&alarm.OccurredAt, &recoveredAt, &handledAt, &handledBy, &alarm.CreatedAt,
		); err != nil {
			return nil, 0, err
		}

		if stationID.Valid {
			alarm.StationID = &stationID.Int64
		}
		if handledBy.Valid {
			alarm.HandledBy = &handledBy.Int64
		}
		if recoveredAt.Valid {
			alarm.RecoveredAt = &recoveredAt.Time
		}
		if handledAt.Valid {
			alarm.HandledAt = &handledAt.Time
		}
		if faultDetail.Valid {
			alarm.FaultDetail = faultDetail.String
		}

		alarms = append(alarms, &alarm)
	}

	return alarms, total, nil
}

func (r *AlarmRepository) GetByDeviceSN(ctx context.Context, sn string, page, pageSize int) ([]*model.Alarm, int64, error) {
	offset := (page - 1) * pageSize

	countQuery := `SELECT COUNT(*) FROM alarms WHERE device_sn = $1`
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, sn).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT id, device_sn, station_id, user_id, alarm_level, fault_code, fault_message,
			   fault_detail, status, occurred_at, recovered_at, handled_at, handled_by, created_at
		FROM alarms WHERE device_sn = $1 ORDER BY occurred_at DESC LIMIT $2 OFFSET $3
	`

	rows, err := r.db.Query(ctx, query, sn, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	alarms := make([]*model.Alarm, 0)
	for rows.Next() {
		var alarm model.Alarm
		var stationID, handledBy sql.NullInt64
		var recoveredAt, handledAt sql.NullTime
		var faultDetail sql.NullString

		if err := rows.Scan(
			&alarm.ID, &alarm.DeviceSN, &stationID, &alarm.UserID, &alarm.AlarmLevel,
			&alarm.FaultCode, &alarm.FaultMessage, &faultDetail, &alarm.Status,
			&alarm.OccurredAt, &recoveredAt, &handledAt, &handledBy, &alarm.CreatedAt,
		); err != nil {
			return nil, 0, err
		}

		if stationID.Valid {
			alarm.StationID = &stationID.Int64
		}
		if handledBy.Valid {
			alarm.HandledBy = &handledBy.Int64
		}
		if recoveredAt.Valid {
			alarm.RecoveredAt = &recoveredAt.Time
		}
		if handledAt.Valid {
			alarm.HandledAt = &handledAt.Time
		}
		if faultDetail.Valid {
			alarm.FaultDetail = faultDetail.String
		}

		alarms = append(alarms, &alarm)
	}

	return alarms, total, nil
}

func (r *AlarmRepository) GetByID(ctx context.Context, id int64) (*model.Alarm, error) {
	query := `
		SELECT id, device_sn, station_id, user_id, alarm_level, fault_code, fault_message,
			   fault_detail, status, occurred_at, recovered_at, handled_at, handled_by, created_at
		FROM alarms WHERE id = $1
	`

	var alarm model.Alarm
	var stationID, handledBy sql.NullInt64
	var recoveredAt, handledAt sql.NullTime
	var faultDetail sql.NullString

	err := r.db.QueryRow(ctx, query, id).Scan(
		&alarm.ID, &alarm.DeviceSN, &stationID, &alarm.UserID, &alarm.AlarmLevel,
		&alarm.FaultCode, &alarm.FaultMessage, &faultDetail, &alarm.Status,
		&alarm.OccurredAt, &recoveredAt, &handledAt, &handledBy, &alarm.CreatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}

	if stationID.Valid {
		alarm.StationID = &stationID.Int64
	}
	if handledBy.Valid {
		alarm.HandledBy = &handledBy.Int64
	}
	if recoveredAt.Valid {
		alarm.RecoveredAt = &recoveredAt.Time
	}
	if handledAt.Valid {
		alarm.HandledAt = &handledAt.Time
	}
	if faultDetail.Valid {
		alarm.FaultDetail = faultDetail.String
	}

	return &alarm, nil
}

func (r *AlarmRepository) MarkHandled(ctx context.Context, id int64, userID int64) error {
	query := `UPDATE alarms SET status = 1, handled_at = NOW(), handled_by = $1 WHERE id = $2`
	_, err := r.db.Exec(ctx, query, userID, id)
	return err
}

func (r *AlarmRepository) MarkRead(ctx context.Context, ids []int64, userID int64) error {
	query := `UPDATE alarms SET status = 1, handled_at = NOW(), handled_by = $1 WHERE id = ANY($2)`
	_, err := r.db.Exec(ctx, query, userID, ids)
	return err
}

type NotifyRepository struct {
	db *pgxpool.Pool
}

func NewNotifyRepository(db *pgxpool.Pool) *NotifyRepository {
	return &NotifyRepository{db: db}
}

func (r *NotifyRepository) GetSettings(ctx context.Context, userID int64) (*model.UserNotifySetting, error) {
	query := `
		SELECT id, user_id, push_enabled, alarm_push, offline_push, system_push,
			   quiet_hours_start, quiet_hours_end, created_at, updated_at
		FROM user_notify_settings WHERE user_id = $1
	`

	var settings model.UserNotifySetting
	var quietStart, quietEnd sql.NullString

	err := r.db.QueryRow(ctx, query, userID).Scan(
		&settings.ID, &settings.UserID, &settings.PushEnabled, &settings.AlarmPush,
		&settings.OfflinePush, &settings.SystemPush, &quietStart, &quietEnd,
		&settings.CreatedAt, &settings.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return &model.UserNotifySetting{
				UserID:      userID,
				PushEnabled: true,
				AlarmPush:   true,
				OfflinePush: true,
				SystemPush:  true,
			}, nil
		}
		return nil, err
	}

	if quietStart.Valid {
		settings.QuietHoursStart = quietStart.String
	}
	if quietEnd.Valid {
		settings.QuietHoursEnd = quietEnd.String
	}

	return &settings, nil
}

func (r *NotifyRepository) UpdateSettings(ctx context.Context, userID int64, settings map[string]interface{}) error {
	query := `
		INSERT INTO user_notify_settings (user_id, push_enabled, alarm_push, offline_push, system_push, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
		ON CONFLICT (user_id) DO UPDATE SET
			push_enabled = $2, alarm_push = $3, offline_push = $4, system_push = $5, updated_at = NOW()
	`

	pushEnabled := settings["push_enabled"].(bool)
	alarmPush := settings["alarm_push"].(bool)
	offlinePush := settings["offline_push"].(bool)
	systemPush := settings["system_push"].(bool)

	_, err := r.db.Exec(ctx, query, userID, pushEnabled, alarmPush, offlinePush, systemPush)
	return err
}

func (r *NotifyRepository) GetMessages(ctx context.Context, userID int64, msgType string, page, pageSize int) ([]*model.Message, int64, error) {
	offset := (page - 1) * pageSize

	baseQuery := `FROM messages WHERE user_id = $1`
	args := []interface{}{userID}

	if msgType != "" {
		baseQuery += " AND type = $2"
		args = append(args, msgType)
	}

	countQuery := `SELECT COUNT(*) ` + baseQuery
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `SELECT id, user_id, title, content, type, is_read, extra_data, created_at ` + baseQuery + ` ORDER BY created_at DESC LIMIT $` + fmt.Sprintf("%d", len(args)+1) + ` OFFSET $` + fmt.Sprintf("%d", len(args)+2)
	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	messages := make([]*model.Message, 0)
	for rows.Next() {
		var msg model.Message
		var extraData sql.NullString
		if err := rows.Scan(
			&msg.ID, &msg.UserID, &msg.Title, &msg.Content, &msg.Type, &msg.IsRead, &extraData, &msg.CreatedAt,
		); err != nil {
			return nil, 0, err
		}
		if extraData.Valid {
			msg.ExtraData = extraData.String
		}
		messages = append(messages, &msg)
	}

	return messages, total, nil
}

func (r *NotifyRepository) MarkMessageRead(ctx context.Context, ids []int64, userID int64) error {
	query := `UPDATE messages SET is_read = true WHERE id = ANY($1) AND user_id = $2`
	_, err := r.db.Exec(ctx, query, ids, userID)
	return err
}

func (r *NotifyRepository) GetUnreadCount(ctx context.Context, userID int64) (int64, error) {
	query := `SELECT COUNT(*) FROM messages WHERE user_id = $1 AND is_read = false`
	var count int64
	err := r.db.QueryRow(ctx, query, userID).Scan(&count)
	return count, err
}
