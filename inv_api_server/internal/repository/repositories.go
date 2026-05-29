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

func (r *UserRepository) ListAll(ctx context.Context) ([]model.User, error) {
	query := `
		SELECT id, phone, COALESCE(email,''), password_hash, nickname, avatar, role, region_id, status,
		       last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE deleted_at IS NULL ORDER BY id DESC
	`
	return r.queryUsers(ctx, query)
}

func (r *UserRepository) UpdateRole(ctx context.Context, userID int64, role int) error {
	_, err := r.db.Exec(ctx, "UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2", role, userID)
	return err
}

func (r *UserRepository) UpdateStatus(ctx context.Context, userID int64, status int) error {
	_, err := r.db.Exec(ctx, "UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2", status, userID)
	return err
}

func (r *UserRepository) UpsertPermission(ctx context.Context, role int, resource string, action string, isAllowed bool) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO role_permissions (role, resource, action, is_allowed, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (role, resource, action) DO UPDATE SET is_allowed = $4, updated_at = NOW()
	`, role, resource, action, isAllowed)
	return err
}

func (r *UserRepository) queryUsers(ctx context.Context, query string) ([]model.User, error) {
	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var user model.User
		var regionID sql.NullInt64
		var lastLoginAt sql.NullTime
		err := rows.Scan(&user.ID, &user.Phone, &user.Email, &user.PasswordHash,
			&user.Nickname, &user.Avatar, &user.Role, &regionID, &user.Status,
			&lastLoginAt, &user.LastLoginIP, &user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			continue
		}
		if regionID.Valid {
			user.RegionID = &regionID.Int64
		}
		if lastLoginAt.Valid {
			user.LastLoginAt = &lastLoginAt.Time
		}
		users = append(users, user)
	}
	return users, nil
}

func (r *UserRepository) GetUserRoleIDs(ctx context.Context, userID int64) ([]int64, error) {
	rows, err := r.db.Query(ctx,
		"SELECT role_id FROM sys_user_role WHERE user_id = $1", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var roleIDs []int64
	for rows.Next() {
		var roleID int64
		if err := rows.Scan(&roleID); err != nil {
			continue
		}
		roleIDs = append(roleIDs, roleID)
	}

	if len(roleIDs) == 0 {
		return []int64{}, nil
	}
	return roleIDs, nil
}

type PermissionEntry struct {
	Resource string `json:"resource"`
	Action   string `json:"action"`
}

func (r *UserRepository) GetRolePermissions(ctx context.Context, roleID int64) ([]PermissionEntry, error) {
	rows, err := r.db.Query(ctx, `
		SELECT p.resource, p.action
		FROM sys_role_permission rp
		JOIN sys_permission p ON p.id = rp.permission_id
		WHERE rp.role_id = $1
	`, roleID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var perms []PermissionEntry
	for rows.Next() {
		var p PermissionEntry
		if err := rows.Scan(&p.Resource, &p.Action); err != nil {
			continue
		}
		perms = append(perms, p)
	}
	return perms, nil
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

func (r *DeviceRepository) HasDataPermission(ctx context.Context, userID int64, sn string) bool {
	var deviceUserID int64
	err := r.db.QueryRow(ctx, `SELECT COALESCE(user_id, 0) FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn).Scan(&deviceUserID)
	if err != nil {
		return false
	}

	if deviceUserID == userID {
		return true
	}

	var count int
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM user_device_rel WHERE user_id = $1 AND device_sn = $2`, userID, sn).Scan(&count)
	if err != nil {
		return false
	}

	return count > 0
}

func (r *DeviceRepository) GetAllowedDeviceSNs(ctx context.Context, userID int64) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT DISTINCT sn FROM (
			SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL
			UNION
			SELECT d.sn FROM user_device_rel udr
			JOIN devices d ON d.sn = udr.device_sn AND d.deleted_at IS NULL
			WHERE udr.user_id = $1
		) allowed ORDER BY sn`, userID)
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

func (r *DeviceRepository) GetBySN(ctx context.Context, sn string) (*model.Device, error) {
	query := `
		SELECT d.id, d.sn, d.model, COALESCE(d.manufacturer,''), COALESCE(d.firmware_arm,''), COALESCE(d.firmware_esp,''),
			   COALESCE(d.device_type,''), COALESCE(d.rated_power,0), COALESCE(d.rated_voltage,0), COALESCE(d.rated_freq,0),
			   COALESCE(d.battery_voltage,0), COALESCE(d.battery_type,''), COALESCE(d.cell_count,0),
			   d.station_id, d.user_id, d.status,
			   COALESCE(rd.total_active_power, 0), COALESCE(rd.daily_energy, 0),
			   d.last_online_at, d.created_at, d.updated_at
		FROM devices d
		LEFT JOIN v_device_latest rd ON rd.device_sn = d.sn
		WHERE d.sn = $1 AND d.deleted_at IS NULL
	`

	var device model.Device
	var stationID sql.NullInt64
	var lastOnlineAt sql.NullTime

	err := r.db.QueryRow(ctx, query, sn).Scan(
		&device.ID, &device.SN, &device.Model, &device.Manufacturer,
		&device.FirmwareArm, &device.FirmwareEsp, &device.DeviceType,
		&device.RatedPower, &device.RatedVoltage, &device.RatedFreq,
		&device.BatteryVoltage, &device.BatteryType, &device.CellCount,
		&stationID, &device.UserID, &device.Status,
		&device.CurrentPower, &device.DailyEnergy,
		&lastOnlineAt,
		&device.CreatedAt, &device.UpdatedAt,
	)

	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
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

	selectCols := `d.id, d.sn, d.model, COALESCE(d.manufacturer,''), COALESCE(d.firmware_arm,''), COALESCE(d.firmware_esp,''),
		COALESCE(d.device_type,''), COALESCE(d.rated_power,0), COALESCE(d.rated_voltage,0), COALESCE(d.rated_freq,0),
		COALESCE(d.battery_voltage,0), COALESCE(d.battery_type,''), COALESCE(d.cell_count,0),
		d.station_id, d.user_id, d.status,
		COALESCE(rd.total_active_power, 0), COALESCE(rd.daily_energy, 0),
		d.last_online_at, d.created_at, d.updated_at`

	allowedSNsSubquery := `(SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id = $1)`

	baseQuery := fmt.Sprintf(` FROM devices d LEFT JOIN v_device_latest rd ON rd.device_sn = d.sn WHERE d.deleted_at IS NULL AND d.sn IN %s`, allowedSNsSubquery)
	args := []interface{}{userID}
	argIdx := 2

	if stationID > 0 {
		baseQuery += fmt.Sprintf(" AND d.station_id = $%d", argIdx)
		args = append(args, stationID)
		argIdx++
	}

	if status >= 0 {
		baseQuery += fmt.Sprintf(" AND d.status = $%d", argIdx)
		args = append(args, status)
		argIdx++
	}

	countQuery := fmt.Sprintf(`SELECT COUNT(*) FROM devices d WHERE d.deleted_at IS NULL AND d.sn IN %s`, allowedSNsSubquery)
	countArgs := []interface{}{userID}
	countIdx := 2
	if stationID > 0 {
		countQuery += fmt.Sprintf(" AND d.station_id = $%d", countIdx)
		countArgs = append(countArgs, stationID)
		countIdx++
	}
	if status >= 0 {
		countQuery += fmt.Sprintf(" AND d.status = $%d", countIdx)
		countArgs = append(countArgs, status)
		countIdx++
	}
	var total int64
	if err := r.db.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `SELECT ` + selectCols + baseQuery + ` ORDER BY d.created_at DESC LIMIT $` + fmt.Sprintf("%d", argIdx) + ` OFFSET $` + fmt.Sprintf("%d", argIdx+1)

	args = append(args, pageSize, offset)

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	devices := make([]*model.Device, 0)
	for rows.Next() {
		var device model.Device
		var stationID sql.NullInt64
		var lastOnlineAt sql.NullTime
		if err := rows.Scan(
			&device.ID, &device.SN, &device.Model, &device.Manufacturer,
			&device.FirmwareArm, &device.FirmwareEsp, &device.DeviceType,
			&device.RatedPower, &device.RatedVoltage, &device.RatedFreq,
			&device.BatteryVoltage, &device.BatteryType, &device.CellCount,
			&stationID, &device.UserID, &device.Status,
			&device.CurrentPower, &device.DailyEnergy,
			&lastOnlineAt,
			&device.CreatedAt, &device.UpdatedAt,
		); err != nil {
			return nil, 0, err
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
		SELECT d.id, d.sn, d.model, COALESCE(d.manufacturer,''), COALESCE(d.firmware_arm,''), COALESCE(d.firmware_esp,''),
			   COALESCE(d.device_type,''), COALESCE(d.rated_power,0), COALESCE(d.rated_voltage,0), COALESCE(d.rated_freq,0),
			   COALESCE(d.battery_voltage,0), COALESCE(d.battery_type,''), COALESCE(d.cell_count,0),
			   d.station_id, d.user_id, d.status,
			   COALESCE(rd.total_active_power, 0), COALESCE(rd.daily_energy, 0),
			   d.last_online_at, d.created_at, d.updated_at
		FROM devices d
		LEFT JOIN v_device_latest rd ON rd.device_sn = d.sn
		WHERE d.station_id = $1 AND d.deleted_at IS NULL
	`

	rows, err := r.db.Query(ctx, query, stationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	devices := make([]*model.Device, 0)
	for rows.Next() {
		var device model.Device
		var stationID sql.NullInt64
		var lastOnlineAt sql.NullTime
		if err := rows.Scan(
			&device.ID, &device.SN, &device.Model, &device.Manufacturer,
			&device.FirmwareArm, &device.FirmwareEsp, &device.DeviceType,
			&device.RatedPower, &device.RatedVoltage, &device.RatedFreq,
			&device.BatteryVoltage, &device.BatteryType, &device.CellCount,
			&stationID, &device.UserID, &device.Status,
			&device.CurrentPower, &device.DailyEnergy,
			&lastOnlineAt,
			&device.CreatedAt, &device.UpdatedAt,
		); err != nil {
			return nil, err
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
	// 从 device_telemetry 获取今日能量
	var dailyEnergy float64
	query := `
		SELECT COALESCE(MAX(daily_energy) - MIN(daily_energy), 0)
		FROM device_telemetry
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status = 1)
		AND time::date = CURRENT_DATE
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

	// 从 device_telemetry 获取最新数据
	query := `
		SELECT 
			COALESCE(SUM((data->'pv'->>'pv_power')::float), 0),
			COALESCE(SUM((data->'ac'->>'power')::float), 0),
			COALESCE(SUM(((data->'battery'->>'voltage')::float * (data->'battery'->>'current')::float)), 0),
			COALESCE(AVG(NULLIF((data->'battery'->>'soc')::float, 0)), 0)
		FROM (
			SELECT DISTINCT ON (device_sn) data
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status = 1)
			ORDER BY device_sn, time DESC
		) latest
	`
	if err := r.db.QueryRow(ctx, query, stationID).Scan(&pvPower, &loadPower, &battPower, &battSoc); err != nil {
		return
	}
	gridPower = 0
	return
}

func (r *DeviceRepository) GetStationEnergySummary(ctx context.Context, stationID int64) (float64, float64) {
	// 从 device_telemetry 计算累计发电和月能量

	// 累计发电：所有有记录的设备每天 daily_energy 最大值之和（从数据库第一条记录开始）
	totalQuery := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, device_sn, MAX(daily_energy) as daily_max
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND daily_energy > 0
			GROUP BY DATE(time), device_sn
		) per_device_daily
	`
	var totalEnergy float64
	r.db.QueryRow(ctx, totalQuery, stationID).Scan(&totalEnergy)

	// 当月发电：当月每个设备每天的 daily_energy 最大值之和
	monthQuery := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, device_sn, MAX(daily_energy) as daily_max
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND time >= DATE_TRUNC('month', CURRENT_DATE)
			AND daily_energy > 0
			GROUP BY DATE(time), device_sn
		) per_device_daily
	`
	var monthEnergy float64
	r.db.QueryRow(ctx, monthQuery, stationID).Scan(&monthEnergy)

	return totalEnergy, monthEnergy
}

func (r *DeviceRepository) GetStationYearEnergy(ctx context.Context, stationID int64) float64 {
	// 当年发电：当年每个设备每天的 daily_energy 最大值之和
	query := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, device_sn, MAX(daily_energy) as daily_max
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND time >= DATE_TRUNC('year', CURRENT_DATE)
			AND daily_energy > 0
			GROUP BY DATE(time), device_sn
		) per_device_daily
	`
	var yearEnergy float64
	r.db.QueryRow(ctx, query, stationID).Scan(&yearEnergy)
	return yearEnergy
}

func (r *DeviceRepository) GetStationTodayEnergy(ctx context.Context, stationID int64) (float64, error) {
	query := `
		SELECT COALESCE(MAX(daily_energy) - MIN(daily_energy), 0)
		FROM device_telemetry
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
		AND time::date = CURRENT_DATE
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

	m["online"] = online
	m["data_source"] = "database"
	return m, nil
}

func (r *DeviceRepository) EnsureDevice(ctx context.Context, sn string) error {
	query := `INSERT INTO devices (sn, model, rated_power, user_id, status, created_at, updated_at)
		VALUES ($1, '', 0, 0, 0, NOW(), NOW())
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

// DEPRECATED: Device sharing feature removed.
// func (r *DeviceRepository) GetShare(ctx context.Context, sn string, userID int64) (*model.DeviceShare, error) {
// 	// Device sharing feature has been removed.
// 	return nil, nil
// }

// DEPRECATED: Device params table removed. Use MQTT direct configuration.
// func (r *DeviceRepository) GetParams(ctx context.Context, sn string) (map[string]interface{}, error) {
// 	// Device params table has been removed.
// 	return make(map[string]interface{}), nil
// }

// DEPRECATED: Device params table removed. Use MQTT direct configuration.
// func (r *DeviceRepository) UpdateParams(ctx context.Context, sn string, params map[string]interface{}) error {
// 	// Device params table has been removed.
// 	return nil
// }

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
		// 使用 TimescaleDB 1 小时连续聚合视图
		query = `
			SELECT bucket, avg_active_power, max_active_power, energy_delta, avg_temperature
			FROM device_telemetry_1hour 
			WHERE device_sn = $1 AND bucket >= $2 AND bucket <= $3
			ORDER BY bucket
		`
	default:
		// 使用 TimescaleDB 1 天连续聚合视图
		query = `
			SELECT bucket, avg_active_power, max_active_power, daily_energy, run_minutes
			FROM device_telemetry_1day 
			WHERE device_sn = $1 AND bucket >= $2 AND bucket <= $3
			ORDER BY bucket
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
		var avgPower, maxPower, energy, tempOrMinutes float64

		if period == "hour" {
			if err := rows.Scan(&dataTime, &avgPower, &maxPower, &energy, &tempOrMinutes); err != nil {
				return nil, err
			}
			result["avg_temperature"] = tempOrMinutes
		} else {
			if err := rows.Scan(&dataTime, &avgPower, &maxPower, &energy, &tempOrMinutes); err != nil {
				return nil, err
			}
			result["run_minutes"] = tempOrMinutes
		}

		result["time"] = dataTime
		result["avg_power"] = avgPower
		result["max_power"] = maxPower
		result["energy_produce"] = energy

		results = append(results, result)
	}

	return results, nil
}

func (r *DeviceRepository) GetStatistics(ctx context.Context, sn, startDate, endDate, period string) (map[string]interface{}, error) {
	// 从 device_telemetry 计算统计数据
	query := `
		SELECT 
			COALESCE(MAX(daily_energy) - MIN(daily_energy), 0) as total_energy
		FROM device_telemetry 
		WHERE device_sn = $1 AND time >= $2 AND time <= $3
	`

	var energyProduce float64
	err := r.db.QueryRow(ctx, query, sn, startDate, endDate).Scan(&energyProduce)

	if err != nil {
		return nil, err
	}

	return map[string]interface{}{
		"energy_produce": energyProduce,
		"energy_consume": 0.0,
		"energy_sell":    0.0,
		"energy_buy":     0.0,
		"income":         0.0,
	}, nil
}

func (r *DeviceRepository) GetOverview(ctx context.Context, userID int64) (map[string]interface{}, error) {
	query := `
		SELECT COUNT(DISTINCT d.id) as device_count,
			   COUNT(DISTINCT CASE WHEN d.status = 1 THEN d.id END) as online_count,
			   COUNT(DISTINCT CASE WHEN d.status = 2 THEN d.id END) as fault_count
		FROM devices d
		WHERE d.deleted_at IS NULL
		AND d.sn IN (SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id = $1)
	`

	result := make(map[string]interface{})
	var deviceCount, onlineCount, faultCount int

	err := r.db.QueryRow(ctx, query, userID).Scan(&deviceCount, &onlineCount, &faultCount)
	if err != nil {
		return nil, err
	}

	var todayEnergy float64
	energyQuery := `
		SELECT COALESCE(SUM(today_energy), 0)
		FROM (
			SELECT DISTINCT ON (d.sn) (dt.data->>'daily_energy')::float as today_energy
			FROM devices d
			LEFT JOIN device_telemetry dt ON dt.device_sn = d.sn AND dt.time::date = CURRENT_DATE
			WHERE d.deleted_at IS NULL
			AND d.sn IN (SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id = $1)
			ORDER BY d.sn, dt.time DESC
		) latest
	`
	r.db.QueryRow(ctx, energyQuery, userID).Scan(&todayEnergy)

	result["device_count"] = deviceCount
	result["online_count"] = onlineCount
	result["fault_count"] = faultCount
	result["today_energy"] = todayEnergy
	result["today_income"] = 0.0

	return result, nil
}

func (r *DeviceRepository) GetTrend(ctx context.Context, userID int64, period string) ([]map[string]interface{}, error) {
	query := `
		SELECT bucket, SUM(daily_energy) as energy_produce
		FROM device_telemetry_1day dd
		JOIN devices d ON d.sn = dd.device_sn
		WHERE d.deleted_at IS NULL
		AND d.sn IN (SELECT sn FROM devices WHERE user_id = $1 AND deleted_at IS NULL UNION SELECT device_sn FROM user_device_rel WHERE user_id = $1)
		AND bucket >= CURRENT_DATE - INTERVAL '30 days'
		GROUP BY bucket ORDER BY bucket
	`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := make([]map[string]interface{}, 0)
	for rows.Next() {
		var dataDate time.Time
		var energyProduce float64
		if err := rows.Scan(&dataDate, &energyProduce); err != nil {
			return nil, err
		}
		results = append(results, map[string]interface{}{
			"date":           dataDate,
			"energy_produce": energyProduce,
			"income":         0.0,
		})
	}

	return results, nil
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
