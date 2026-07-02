package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strconv"
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
		SELECT id, phone, COALESCE(email,''), password_hash, COALESCE(nickname,''), COALESCE(avatar,''), role, region_id, status,
			   COALESCE(timezone,'Asia/Shanghai'), last_login_at, COALESCE(last_login_ip,''), created_at, updated_at
		FROM users WHERE id = $1 AND deleted_at IS NULL
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime

	err := r.db.QueryRow(ctx, query, id).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &user.Nickname, &user.Avatar,
		&user.Role, &regionID, &user.Status, &user.Timezone, &lastLoginAt, &user.LastLoginIP,
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
			   COALESCE(timezone,'Asia/Shanghai'), last_login_at, last_login_ip, created_at, updated_at
		FROM users WHERE email = $1 AND deleted_at IS NULL
	`

	var user model.User
	var regionID sql.NullInt64
	var lastLoginAt sql.NullTime
	var nickname, avatar, lastLoginIP sql.NullString

	err := r.db.QueryRow(ctx, query, email).Scan(
		&user.ID, &user.Phone, &user.Email, &user.PasswordHash, &nickname, &avatar,
		&user.Role, &regionID, &user.Status, &user.Timezone, &lastLoginAt, &lastLoginIP,
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

func (r *UserRepository) UpdateProfile(ctx context.Context, userID int64, nickname, avatar, tz string) error {
	if tz != "" {
		query := `UPDATE users SET nickname = $1, avatar = $2, timezone = $3, updated_at = NOW() WHERE id = $4`
		_, err := r.db.Exec(ctx, query, nickname, avatar, tz, userID)
		return err
	}
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
		SELECT id, phone, COALESCE(email,''), password_hash, COALESCE(nickname,''), COALESCE(avatar,''), role, region_id, status,
		       last_login_at, COALESCE(last_login_ip,''), created_at, updated_at
		FROM users WHERE deleted_at IS NULL ORDER BY id DESC
	`
	return r.queryUsers(ctx, query)
}

type ListUsersParams struct {
	Page     int
	PageSize int
	Keyword  string
	Role     int
	Status   int
}

type ListUsersResult struct {
	Items []model.User
	Total int64
}

func (r *UserRepository) List(ctx context.Context, params ListUsersParams) (*ListUsersResult, error) {
	offset := (params.Page - 1) * params.PageSize

	baseQuery := `
		SELECT id, phone, COALESCE(email,''), password_hash, COALESCE(nickname,''), COALESCE(avatar,''), role, region_id, status,
		       last_login_at, COALESCE(last_login_ip,''), created_at, updated_at
		FROM users WHERE deleted_at IS NULL
	`
	countQuery := `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`
	args := []interface{}{}

	if params.Keyword != "" {
		baseQuery += ` AND (phone ILIKE $1 OR email ILIKE $1 OR nickname ILIKE $1)`
		countQuery += ` AND (phone ILIKE $1 OR email ILIKE $1 OR nickname ILIKE $1)`
		args = append(args, "%"+params.Keyword+"%")
	}

	if params.Role >= 0 {
		baseQuery += fmt.Sprintf(" AND role = $%d", len(args)+1)
		countQuery += fmt.Sprintf(" AND role = $%d", len(args)+1)
		args = append(args, params.Role)
	}

	if params.Status >= 0 {
		baseQuery += fmt.Sprintf(" AND status = $%d", len(args)+1)
		countQuery += fmt.Sprintf(" AND status = $%d", len(args)+1)
		args = append(args, params.Status)
	}

	var total int64
	countArgs := make([]interface{}, len(args))
	copy(countArgs, args)
	if err := r.db.QueryRow(ctx, countQuery, countArgs...).Scan(&total); err != nil {
		return nil, err
	}

	baseQuery += ` ORDER BY id DESC LIMIT $` + fmt.Sprintf("%d", len(args)+1) + ` OFFSET $` + fmt.Sprintf("%d", len(args)+2)
	args = append(args, params.PageSize, offset)

	rows, err := r.db.Query(ctx, baseQuery, args...)
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
			return nil, err
		}
		if regionID.Valid {
			user.RegionID = &regionID.Int64
		}
		if lastLoginAt.Valid {
			user.LastLoginAt = &lastLoginAt.Time
		}
		user.PasswordHash = ""
		users = append(users, user)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if users == nil {
		users = []model.User{}
	}

	return &ListUsersResult{
		Items: users,
		Total: total,
	}, nil
}

func (r *UserRepository) UpdateRole(ctx context.Context, userID int64, role int) error {
	_, err := r.db.Exec(ctx, "UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2", role, userID)
	if err == nil {
		r.invalidateUserPermissionCache(ctx, userID)
	}
	return err
}

func (r *UserRepository) UpdateStatus(ctx context.Context, userID int64, status int) error {
	_, err := r.db.Exec(ctx, "UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2", status, userID)
	if err == nil {
		r.invalidateUserPermissionCache(ctx, userID)
	}
	return err
}

func (r *UserRepository) UpsertPermission(ctx context.Context, role int, resource string, action string, isAllowed bool) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO role_permissions (role, resource, action, is_allowed, updated_at)
		VALUES ($1, $2, $3, $4, NOW())
		ON CONFLICT (role, resource, action) DO UPDATE SET is_allowed = $4, updated_at = NOW()
	`, role, resource, action, isAllowed)
	if err == nil {
		r.invalidateRolePermissionCache(ctx, int64(role))
	}
	return err
}

func (r *UserRepository) invalidateUserPermissionCache(ctx context.Context, userID int64) {
	if r.cache == nil {
		return
	}
	r.cache.Del(ctx, fmt.Sprintf("rbac:user:%d", userID))
}

func (r *UserRepository) invalidateRolePermissionCache(ctx context.Context, roleID int64) {
	if r.cache == nil {
		return
	}
	r.cache.Del(ctx, fmt.Sprintf("rbac:role:%d", roleID))
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
							  panel_count, latitude, longitude, timezone, status, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`

	return r.db.QueryRow(ctx, query,
		station.UserID, station.Name, station.Province, station.City, station.District,
		station.Address, station.Capacity, station.PanelCount,
		station.Latitude, station.Longitude, station.Timezone, station.Status,
	).Scan(&station.ID, &station.CreatedAt, &station.UpdatedAt)
}

func (r *StationRepository) Update(ctx context.Context, station *model.Station) error {
	query := `
		UPDATE stations SET name = $1, province = $2, city = $3, district = $4, address = $5,
							 capacity = $6, panel_count = $7,
							 peak_price = $8, valley_price = $9,
							 latitude = $10, longitude = $11, timezone = $12, updated_at = NOW()
		WHERE id = $13
	`

	_, err := r.db.Exec(ctx, query,
		station.Name, station.Province, station.City, station.District, station.Address,
		station.Capacity, station.PanelCount,
		station.PeakPrice, station.ValleyPrice,
		station.Latitude, station.Longitude, station.Timezone, station.ID,
	)
	return err
}

func (r *StationRepository) Delete(ctx context.Context, id int64) error {
	query := `UPDATE stations SET deleted_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, query, id)
	return err
}

func (r *StationRepository) Assign(ctx context.Context, id int64, userID int64) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `UPDATE stations SET user_id = $1, updated_at = NOW() WHERE id = $2 AND deleted_at IS NULL`, userID, id)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `UPDATE devices SET user_id = $1, updated_at = NOW() WHERE station_id = $2 AND deleted_at IS NULL`, userID, id)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *StationRepository) GetByID(ctx context.Context, id int64) (*model.Station, error) {
	query := `
		SELECT id, user_id, name, province, city, district, address, capacity,
			   panel_count, latitude, longitude, timezone, status, created_at, updated_at
		FROM stations WHERE id = $1 AND deleted_at IS NULL
	`

	var station model.Station
	err := r.db.QueryRow(ctx, query, id).Scan(
		&station.ID, &station.UserID, &station.Name, &station.Province, &station.City,
		&station.District, &station.Address, &station.Capacity, &station.PanelCount,
		&station.Latitude, &station.Longitude, &station.Timezone,
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
			   panel_count, latitude, longitude, timezone, status, created_at, updated_at
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
			&station.Latitude, &station.Longitude, &station.Timezone,
			&station.Status, &station.CreatedAt, &station.UpdatedAt,
		); err != nil {
			return nil, 0, err
		}
		stations = append(stations, &station)
	}

	return stations, total, nil
}

func (r *StationRepository) GetAll(ctx context.Context, page, pageSize int) ([]*model.Station, int64, error) {
	offset := (page - 1) * pageSize

	countQuery := `SELECT COUNT(*) FROM stations WHERE deleted_at IS NULL`
	var total int64
	if err := r.db.QueryRow(ctx, countQuery).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := `
		SELECT id, user_id, name, province, city, district, address, capacity,
			   panel_count, latitude, longitude, timezone, status, created_at, updated_at
		FROM stations WHERE deleted_at IS NULL
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2
	`

	rows, err := r.db.Query(ctx, query, pageSize, offset)
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
			&station.Latitude, &station.Longitude, &station.Timezone,
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
		query := `
			SELECT
				DATE_TRUNC('hour', telem.time) as hour_time,
				AVG(COALESCE((telem.data->>'pv_power_total')::float, (telem.data->'pv_data'->>'pv_power_total')::float, (telem.data->'data'->>'pv_power_total')::float)) FILTER (WHERE telem.topic = 'data/pv') as avg_pv_power,
				AVG(COALESCE((telem.data->>'power')::float, (telem.data->'ac_data'->>'power')::float, (telem.data->'data'->>'power')::float)) FILTER (WHERE telem.topic = 'data/ac') as avg_ac_power,
				AVG(COALESCE(
					(telem.data->>'voltage')::float * (telem.data->>'current')::float,
					(telem.data->'batt_data'->>'voltage')::float * (telem.data->'batt_data'->>'current')::float,
					(telem.data->'data'->>'voltage')::float * (telem.data->'data'->>'current')::float,
					0
				)) FILTER (WHERE telem.topic = 'data/battery') as avg_batt_power,
				MAX(COALESCE((telem.data->>'daily_pv')::float, (telem.data->'energy_data'->>'daily_pv')::float, (telem.data->'data'->>'daily_pv')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_pv,
				MAX(COALESCE((telem.data->>'daily_charge')::float, (telem.data->'energy_data'->>'daily_charge')::float, (telem.data->'data'->>'daily_charge')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_charge,
				MAX(COALESCE((telem.data->>'daily_discharge')::float, (telem.data->'energy_data'->>'daily_discharge')::float, (telem.data->'data'->>'daily_discharge')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_discharge,
				MAX(COALESCE((telem.data->>'daily_load')::float, (telem.data->'energy_data'->>'daily_load')::float, (telem.data->'data'->>'daily_load')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_load,
				COUNT(DISTINCT telem.device_sn) FILTER (WHERE telem.topic IN ('data/pv', 'data/ac')) as device_count
			FROM device_telemetry telem
			WHERE telem.device_sn = ANY($1)
				AND telem.time >= $2::timestamp
				AND telem.time <= $3::timestamp
				AND telem.topic IN ('data/pv', 'data/ac', 'data/battery', 'data/energy')
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
			var avgPvPower, avgAcPower, avgBattPower sql.NullFloat64
			var maxDailyPv, maxDailyCharge, maxDailyDischarge, maxDailyLoad sql.NullFloat64
			var deviceCount int
			if err := rows.Scan(&hourTime, &avgPvPower, &avgAcPower, &avgBattPower, &maxDailyPv, &maxDailyCharge, &maxDailyDischarge, &maxDailyLoad, &deviceCount); err != nil {
				return nil, err
			}
			// 电池功率：正数为充电，负数为放电
			battPower := avgBattPower.Float64
			batteryCharge := 0.0
			batteryDischarge := 0.0
			if battPower > 0 {
				batteryCharge = battPower
			} else if battPower < 0 {
				batteryDischarge = -battPower
			}
			results = append(results, map[string]interface{}{
				"time":              hourTime,
				"energy_produce":    avgPvPower.Float64,
				"energy_consume":    avgAcPower.Float64,
				"battery_charge":    batteryCharge,
				"battery_discharge": batteryDischarge,
				"daily_pv":          maxDailyPv.Float64,
				"daily_charge":      maxDailyCharge.Float64,
				"daily_discharge":   maxDailyDischarge.Float64,
				"daily_load":        maxDailyLoad.Float64,
			})
		}

	default:
		query := `
			SELECT 
				DATE(telem.time) as day_date,
				MAX(COALESCE((telem.data->>'daily_pv')::float, (telem.data->'energy_data'->>'daily_pv')::float, (telem.data->'data'->>'daily_pv')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_pv,
				MAX(COALESCE((telem.data->>'power')::float, (telem.data->'ac_data'->>'power')::float, (telem.data->'data'->>'power')::float)) FILTER (WHERE telem.topic = 'data/ac') as max_ac_power,
				MAX(COALESCE((telem.data->>'daily_charge')::float, (telem.data->'energy_data'->>'daily_charge')::float, (telem.data->'data'->>'daily_charge')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_charge,
				MAX(COALESCE((telem.data->>'daily_discharge')::float, (telem.data->'energy_data'->>'daily_discharge')::float, (telem.data->'data'->>'daily_discharge')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_discharge,
				MAX(COALESCE((telem.data->>'daily_load')::float, (telem.data->'energy_data'->>'daily_load')::float, (telem.data->'data'->>'daily_load')::float)) FILTER (WHERE telem.topic = 'data/energy') as max_daily_load,
				COUNT(DISTINCT telem.device_sn) FILTER (WHERE telem.topic IN ('data/pv', 'data/ac')) as device_count
			FROM device_telemetry telem
			WHERE telem.device_sn = ANY($1)
				AND telem.time >= $2::timestamp
				AND telem.time <= $3::timestamp
				AND telem.topic IN ('data/pv', 'data/ac', 'data/energy')
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
			var maxDailyPv, maxAcPower sql.NullFloat64
			var maxDailyCharge, maxDailyDischarge, maxDailyLoad sql.NullFloat64
			var deviceCount int
			if err := rows.Scan(&dayDate, &maxDailyPv, &maxAcPower, &maxDailyCharge, &maxDailyDischarge, &maxDailyLoad, &deviceCount); err != nil {
				return nil, err
			}
			results = append(results, map[string]interface{}{
				"time":              dayDate,
				"energy_produce":    maxDailyPv.Float64,
				"energy_consume":    maxDailyLoad.Float64,
				"ac_power":          maxAcPower.Float64,
				"daily_pv":          maxDailyPv.Float64,
				"battery_charge":    maxDailyCharge.Float64,
				"battery_discharge": maxDailyDischarge.Float64,
				"daily_load":        maxDailyLoad.Float64,
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
			   COALESCE(d.firmware_dsp,''), COALESCE(d.firmware_bms,''), COALESCE(d.main_version,''),
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
		&device.FirmwareArm, &device.FirmwareEsp,
		&device.FirmwareDSP, &device.FirmwareBMS, &device.MainVersion,
		&device.DeviceType,
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
		COALESCE(d.firmware_dsp,''), COALESCE(d.firmware_bms,''), COALESCE(d.main_version,''),
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
			&device.FirmwareArm, &device.FirmwareEsp,
			&device.FirmwareDSP, &device.FirmwareBMS, &device.MainVersion,
			&device.DeviceType,
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

func (r *DeviceRepository) GetAll(ctx context.Context, stationID int64, status, page, pageSize int) ([]*model.Device, int64, error) {
	offset := (page - 1) * pageSize

	selectCols := `d.id, d.sn, d.model, COALESCE(d.manufacturer,''), COALESCE(d.firmware_arm,''), COALESCE(d.firmware_esp,''),
		COALESCE(d.firmware_dsp,''), COALESCE(d.firmware_bms,''), COALESCE(d.main_version,''),
		COALESCE(d.device_type,''), COALESCE(d.rated_power,0), COALESCE(d.rated_voltage,0), COALESCE(d.rated_freq,0),
		COALESCE(d.battery_voltage,0), COALESCE(d.battery_type,''), COALESCE(d.cell_count,0),
		d.station_id, d.user_id, d.status,
		COALESCE(rd.total_active_power, 0), COALESCE(rd.daily_energy, 0),
		d.last_online_at, d.created_at, d.updated_at`

	baseQuery := ` FROM devices d LEFT JOIN v_device_latest rd ON rd.device_sn = d.sn WHERE d.deleted_at IS NULL`
	args := []interface{}{}
	argIdx := 1

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

	countQuery := `SELECT COUNT(*) FROM devices d WHERE d.deleted_at IS NULL`
	countArgs := []interface{}{}
	countIdx := 1
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
			&device.FirmwareArm, &device.FirmwareEsp,
			&device.FirmwareDSP, &device.FirmwareBMS, &device.MainVersion,
			&device.DeviceType,
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
			   COALESCE(d.firmware_dsp,''), COALESCE(d.firmware_bms,''), COALESCE(d.main_version,''),
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
			&device.FirmwareArm, &device.FirmwareEsp,
			&device.FirmwareDSP, &device.FirmwareBMS, &device.MainVersion,
			&device.DeviceType,
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
	var dailyEnergy float64
	query := `
		SELECT COALESCE(MAX(COALESCE(
			(data->'data'->>'daily_pv')::float,
			(data->>'daily_pv')::float,
			(data->'data'->>'energy_daily_pv')::float,
			(data->>'energy_daily_pv')::float,
			daily_energy
		)), 0)
		FROM device_telemetry
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status IN (1, 2))
		AND time::date = CURRENT_DATE
		AND topic = 'data/energy'
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
		baseQuery += ` AND status IN (1, 2)`
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

			// 处理 pv 数据 - 支持 {"pv": {...}} 和 {"pv": {"data": {...}}} 两种格式
			if pvRaw, ok := m["pv"].(map[string]interface{}); ok {
				pvData := pvRaw
				if innerData, ok := pvRaw["data"].(map[string]interface{}); ok {
					pvData = innerData
				}
				// 优先使用 pv_power_total（完整数据格式），其次使用 pv_power（兼容旧格式）
				if p, ok := pvData["pv_power_total"].(float64); ok {
					pvPower += p
					redisHit = true
				} else if p, ok := pvData["pv_power"].(float64); ok {
					pvPower += p
					redisHit = true
				}
			}
			// 处理 ac 数据 - 支持 {"ac": {...}} 和 {"ac": {"data": {...}}} 两种格式
			if acRaw, ok := m["ac"].(map[string]interface{}); ok {
				acData := acRaw
				if innerData, ok := acRaw["data"].(map[string]interface{}); ok {
					acData = innerData
				}
				if p, ok := acData["power"].(float64); ok {
					loadPower += p
					redisHit = true
				}
			}
			// 兼容 Redis 缓存中的 key 别名: batt / battery
			battRaw, _ := m["batt"].(map[string]interface{})
			if battRaw == nil {
				battRaw, _ = m["battery"].(map[string]interface{})
			}
			if battRaw != nil {
				battData := battRaw
				if innerData, ok := battRaw["data"].(map[string]interface{}); ok {
					battData = innerData
				}
				v, _ := battData["voltage"].(float64)
				c, _ := battData["current"].(float64)
				battPower += v * c
				redisHit = true
				if s, ok := battData["soc"].(float64); ok {
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

	// 从 device_telemetry 获取最新数据（按 topic 分别取每个设备的最新值）
	query := `
		SELECT
			COALESCE(SUM(CASE WHEN telem.topic = 'data/pv' THEN COALESCE((telem.data->'pv_data'->>'pv_power_total')::float, (telem.data->'data'->>'pv_power_total')::float) END), 0),
			COALESCE(SUM(CASE WHEN telem.topic = 'data/ac' THEN COALESCE((telem.data->'ac_data'->>'power')::float, (telem.data->'data'->>'power')::float) END), 0),
			COALESCE(SUM(CASE WHEN telem.topic = 'data/battery' 
				THEN COALESCE((telem.data->'batt_data'->>'voltage')::float, (telem.data->'data'->>'voltage')::float, 0) 
					* COALESCE((telem.data->'batt_data'->>'current')::float, (telem.data->'data'->>'current')::float, 0) 
			END), 0),
			COALESCE(AVG(CASE WHEN telem.topic = 'data/battery' THEN NULLIF(COALESCE((telem.data->'batt_data'->>'soc')::float, (telem.data->'data'->>'soc')::float), 0) END), 0)
		FROM (
			SELECT device_sn, telem.topic, telem.data,
				ROW_NUMBER() OVER (PARTITION BY device_sn, telem.topic ORDER BY telem.time DESC) as rn
			FROM device_telemetry telem
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL AND status IN (1, 2))
				AND telem.topic IN ('data/pv', 'data/ac', 'data/battery')
		) telem
		WHERE telem.rn = 1
	`
	if err := r.db.QueryRow(ctx, query, stationID).Scan(&pvPower, &loadPower, &battPower, &battSoc); err != nil {
		return
	}
	gridPower = 0
	return
}

func (r *DeviceRepository) GetStationEnergySummary(ctx context.Context, stationID int64) (float64, float64) {
	// 累计发电量：直接取每个设备最新的 total_pv 值，然后求和
	var totalEnergy float64
	rows, err := r.db.Query(ctx, `
		SELECT COALESCE(
			(data->>'total_pv')::float,
			(data->'data'->>'total_pv')::float,
			0
		) as total_pv
		FROM (
			SELECT DISTINCT ON (device_sn) device_sn, data
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND topic = 'data/energy'
			ORDER BY device_sn, time DESC
		) latest
		WHERE COALESCE((data->>'total_pv')::float, (data->'data'->>'total_pv')::float, 0) > 0
	`, stationID)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var pv float64
			if rows.Scan(&pv) == nil {
				totalEnergy += pv
			}
		}
	}

	// 本月发电量：用 daily_pv 按天汇总
	monthQuery := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, device_sn, MAX(COALESCE(
				(data->>'daily_pv')::float,
				(data->'data'->>'daily_pv')::float,
				0
			)) as daily_max
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND time >= DATE_TRUNC('month', CURRENT_DATE)
			AND topic = 'data/energy'
			GROUP BY DATE(time), device_sn
		) per_device_daily
		WHERE daily_max > 0
	`
	var monthEnergy float64
	r.db.QueryRow(ctx, monthQuery, stationID).Scan(&monthEnergy)

	return totalEnergy, monthEnergy
}

func (r *DeviceRepository) GetStationYearEnergy(ctx context.Context, stationID int64) float64 {
	query := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, device_sn,
				MAX(COALESCE(
					(data->'data'->>'daily_pv')::float,
					(data->>'daily_pv')::float,
					(data->'data'->>'energy_daily_pv')::float,
					(data->>'energy_daily_pv')::float,
					daily_energy
				)) as daily_max
			FROM device_telemetry
			WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
			AND time >= DATE_TRUNC('year', CURRENT_DATE)
			AND topic = 'data/energy'
			GROUP BY DATE(time), device_sn
		) per_device_daily
		WHERE daily_max > 0
	`
	var yearEnergy float64
	r.db.QueryRow(ctx, query, stationID).Scan(&yearEnergy)
	return yearEnergy
}

func (r *DeviceRepository) GetStationTodayEnergy(ctx context.Context, stationID int64) (float64, error) {
	query := `
		SELECT COALESCE(MAX(COALESCE(
			(data->'data'->>'daily_pv')::float,
			(data->>'daily_pv')::float,
			(data->'data'->>'energy_daily_pv')::float,
			(data->>'energy_daily_pv')::float,
			daily_energy
		)), 0)
		FROM device_telemetry
		WHERE device_sn IN (SELECT sn FROM devices WHERE station_id = $1 AND deleted_at IS NULL)
		AND time::date = CURRENT_DATE
		AND topic = 'data/energy'
	`
	var energy float64
	err := r.db.QueryRow(ctx, query, stationID).Scan(&energy)
	return energy, err
}

// normalizeRealtimeData 将 Redis 缓存的原始数据转换为前端期望的格式
// 同时将嵌套的 ac/pv/battery/system 数据展平到顶层，供监控页面直接读取
func normalizeRealtimeData(data map[string]interface{}) map[string]interface{} {
	// batt → battery (前端期望 battery)，并展平到顶层
	if batt, ok := data["batt"]; ok {
		if battMap, ok := batt.(map[string]interface{}); ok {
			data["battery"] = battMap
			if tempBat, exists := battMap["temp_battery"]; exists {
				battMap["temp"] = tempBat
			}
			// 展平电池字段 (监控页面期望 rt.battery_soc, rt.battery_voltage 等)
			if v, exists := battMap["soc"]; exists {
				data["battery_soc"] = v
			}
			if v, exists := battMap["voltage"]; exists {
				data["battery_voltage"] = v
			}
			// 充放电功率：power > 0 充电, power < 0 放电
			if v, exists := battMap["power"]; exists {
				if power, ok := v.(float64); ok {
					if power >= 0 {
						data["charge_power"] = v
						data["discharge_power"] = float64(0)
					} else {
						data["charge_power"] = float64(0)
						data["discharge_power"] = -power
					}
				}
			}
			if v, exists := battMap["charge_state"]; exists {
				data["charge_state"] = v
			}
		}
	}

	// sys → system (前端期望 system)，并展平到顶层
	if sys, ok := data["sys"]; ok {
		if sysMap, ok := sys.(map[string]interface{}); ok {
			data["system"] = sysMap
			if v, exists := sysMap["temp_inv"]; exists {
				data["inverter_temp"] = v
			}
			if v, exists := sysMap["dc_bus_voltage"]; exists {
				data["vbus1"] = v
			}
			if v, exists := sysMap["state"]; exists {
				data["work_state"] = v
			}
		}
	}

	// pv: 展平所有 PV 字段到顶层 (rt.pv1_voltage, rt.pv2_voltage 等)
	if pv, ok := data["pv"]; ok {
		if pvMap, ok := pv.(map[string]interface{}); ok {
			for k, v := range pvMap {
				data[k] = v
			}
			if v, exists := pvMap["pv_power_total"]; exists {
				data["pv_total_power"] = v
			}
		}
	}

	// ac: 展平到顶层 (rt.ac_voltage, rt.ac_power 等)
	if ac, ok := data["ac"]; ok {
		if acMap, ok := ac.(map[string]interface{}); ok {
			if v, exists := acMap["voltage"]; exists {
				data["ac_voltage"] = v
			}
			if v, exists := acMap["current"]; exists {
				data["ac_current"] = v
			}
			if v, exists := acMap["power"]; exists {
				data["ac_power"] = v
			}
			if v, exists := acMap["frequency"]; exists {
				data["ac_frequency"] = v
			}
			if v, exists := acMap["pf"]; exists {
				data["power_factor"] = v
			}
		}
	}

	// energy: 展平到顶层
	if energy, ok := data["energy"]; ok {
		if energyMap, ok := energy.(map[string]interface{}); ok {
			for k, v := range energyMap {
				data[k] = v
			}
		}
	}

	return data
}

func (r *DeviceRepository) GetRealtimeData(ctx context.Context, sn string) (map[string]interface{}, error) {
	online := false
	var deviceStatus int
	err := r.db.QueryRow(ctx, `SELECT status FROM devices WHERE sn=$1 AND deleted_at IS NULL`, sn).Scan(&deviceStatus)
	if err == nil && deviceStatus == 1 {
		online = true
	}

	// 优先使用 Redis 中的实时在线标记（Device Server 通过 MarkDeviceOnline 写入）
	// 使用独立 Key device:heartbeat:{sn} + TTL，key 存在即在线
	if r.cache != nil {
		if r.cache.Exists(ctx, "device:heartbeat:"+sn).Val() > 0 {
			online = true
		}
	}

	if r.cache != nil {
		result := make(map[string]interface{})
		result["online"] = online

		mainKey := "realtime:latest:" + sn
		cached, err := r.cache.Get(ctx, mainKey).Result()
		if err == nil && cached != "" {
			var m map[string]interface{}
			if json.Unmarshal([]byte(cached), &m) == nil {
				for k, v := range m {
					// 处理嵌套格式 {"data": {...}, "timestamp": ...}
					if nested, ok := v.(map[string]interface{}); ok {
						if innerData, exists := nested["data"].(map[string]interface{}); exists {
							result[k] = innerData
						} else {
							result[k] = v
						}
					} else {
						result[k] = v
					}
				}
			}
		}

		pattern := "realtime:latest:" + sn + ":*"
		var cursor uint64
		for {
			keys, nextCursor, err := r.cache.Scan(ctx, cursor, pattern, 100).Result()
			if err != nil {
				break
			}
			cursor = nextCursor
			if len(keys) > 0 {
				vals, err := r.cache.MGet(ctx, keys...).Result()
				if err == nil {
					for i, key := range keys {
						if i < len(vals) && vals[i] != nil {
							fieldName := key[len("realtime:latest:"+sn+":"):]
							if valStr, ok := vals[i].(string); ok {
								var fieldData map[string]interface{}
								if json.Unmarshal([]byte(valStr), &fieldData) == nil {
									if v, exists := fieldData["v"]; exists {
										result[fieldName] = v
									}
								}
							}
						}
					}
				}
			}
			if cursor == 0 {
				break
			}
		}

		if len(result) > 3 {
			return normalizeRealtimeData(result), nil
		}

		for _, cacheKey := range []string{"telemetry:latest:" + sn} {
			cached, err := r.cache.Get(ctx, cacheKey).Result()
			if err != nil || cached == "" {
				continue
			}
			var m map[string]interface{}
			if json.Unmarshal([]byte(cached), &m) == nil {
				m["online"] = online
				return normalizeRealtimeData(m), nil
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
	return normalizeRealtimeData(m), nil
}

func (r *DeviceRepository) EnsureDevice(ctx context.Context, sn string) error {
	query := `INSERT INTO devices (sn, model, rated_power, user_id, status, created_at, updated_at)
		VALUES ($1, '', 0, 0, 0, NOW(), NOW())
		ON CONFLICT (sn) DO NOTHING`
	_, err := r.db.Exec(ctx, query, sn)
	return err
}

func (r *DeviceRepository) Bind(ctx context.Context, sn string, userID, stationID int64) error {
	query := `UPDATE devices SET user_id = $1, station_id = $2, updated_at = NOW() WHERE sn = $3 AND user_id = 0`
	tag, err := r.db.Exec(ctx, query, userID, stationID, sn)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("device already bound")
	}
	r.invalidateDeviceCache(ctx, sn)
	return nil
}

func (r *DeviceRepository) Unbind(ctx context.Context, sn string) error {
	// 先获取设备原来的 station_id
	var stationID int64
	_ = r.db.QueryRow(ctx, `SELECT COALESCE(station_id, 0) FROM devices WHERE sn = $1`, sn).Scan(&stationID)

	query := `UPDATE devices SET user_id = 0, station_id = NULL, updated_at = NOW() WHERE sn = $1`
	_, err := r.db.Exec(ctx, query, sn)
	if err == nil {
		r.invalidateDeviceCache(ctx, sn)
		// 更新原电站的容量
		if stationID > 0 {
			r.updateStationCapacity(ctx, stationID)
		}
	}
	return err
}

func (r *DeviceRepository) AddToStation(ctx context.Context, sn string, stationID int64) error {
	query := `UPDATE devices SET station_id = $1, updated_at = NOW() WHERE sn = $2`
	_, err := r.db.Exec(ctx, query, stationID, sn)
	if err == nil {
		r.invalidateDeviceCache(ctx, sn)
		r.updateStationCapacity(ctx, stationID)
	}
	return err
}

// updateStationCapacity 根据关联设备的逆变器额定功率自动更新电站容量
func (r *DeviceRepository) updateStationCapacity(ctx context.Context, stationID int64) {
	// 计算该电站下所有设备的额定功率之和
	var totalCapacity float64
	err := r.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(dm.rated_power_kw), 0)
		FROM devices d
		JOIN device_models dm ON d.model_id = dm.id
		WHERE d.station_id = $1 AND d.deleted_at IS NULL
	`, stationID).Scan(&totalCapacity)
	if err != nil {
		return
	}

	// 更新电站容量
	_, _ = r.db.Exec(ctx, `
		UPDATE stations SET capacity = $1, updated_at = NOW() WHERE id = $2
	`, totalCapacity, stationID)
}

func (r *DeviceRepository) invalidateDeviceCache(ctx context.Context, sn string) {
	if r.cache == nil {
		return
	}
	keys := []string{
		"realtime:latest:" + sn,
		"telemetry:latest:" + sn,
	}
	r.cache.Del(ctx, keys...)
}

func (r *DeviceRepository) MarkStaleDevicesOffline(ctx context.Context, timeoutSeconds int) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT sn FROM devices WHERE status IN (1, 2) AND last_online_at < NOW() - MAKE_INTERVAL(secs => $1)`, timeoutSeconds)
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

	// 双重校验：检查 Redis device:heartbeat:{sn} key 是否存在，如果存在则不标记离线
	if len(sns) > 0 && r.cache != nil {
		var stale []string
		for _, sn := range sns {
			if r.cache.Exists(ctx, "device:heartbeat:"+sn).Val() > 0 {
				continue // Redis 心跳 key 仍存在，跳过
			}
			stale = append(stale, sn)
		}
		sns = stale
	}

	if len(sns) > 0 {
		r.db.Exec(ctx, `UPDATE devices SET status=0, updated_at=NOW() WHERE sn = ANY($1)`, sns)
	}

	return sns, nil
}

func (r *DeviceRepository) SyncStationStatus(ctx context.Context) error {
	_, err := r.db.Exec(ctx, `
		UPDATE stations SET
			status = CASE
				WHEN EXISTS (SELECT 1 FROM devices WHERE devices.station_id = stations.id AND devices.status IN (1, 2) AND devices.deleted_at IS NULL) THEN 1
				ELSE 0
			END,
			updated_at = NOW()
		WHERE deleted_at IS NULL
	`)
	return err
}

// MarkDeviceOfflineBySN 将指定设备标记为离线（事件驱动离线检测调用）
// 返回 true 表示设备状态确实发生了变化（从在线/故障变为离线）
func (r *DeviceRepository) MarkDeviceOfflineBySN(ctx context.Context, sn string) (bool, error) {
	// 先检查设备当前状态，只处理在线(1)或故障(2)的设备
	var currentStatus int
	err := r.db.QueryRow(ctx, `SELECT status FROM devices WHERE sn = $1 AND deleted_at IS NULL`, sn).Scan(&currentStatus)
	if err != nil {
		return false, err
	}
	if currentStatus == 0 {
		return false, nil // 已经是离线状态，无需更新
	}

	// 再次确认 Redis 心跳 key 确实不存在（防止竞态：设备刚好上线）
	if r.cache != nil {
		if r.cache.Exists(ctx, "device:heartbeat:"+sn).Val() > 0 {
			return false, nil // key 又出现了，不标记离线
		}
	}

	result, err := r.db.Exec(ctx, `UPDATE devices SET status=0, updated_at=NOW() WHERE sn = $1 AND status IN (1, 2)`, sn)
	if err != nil {
		return false, err
	}
	return result.RowsAffected() > 0, nil
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

// Deprecated: SendCommand via Redis Pub/Sub is no longer used.
// DeviceService.SendCommand now calls Device Server via HTTP directly.
func (r *DeviceRepository) SendCommand(ctx context.Context, sn, cmdType string, params map[string]interface{}) error {
	cmdData, _ := json.Marshal(map[string]interface{}{
		"cmd_type": cmdType,
		"params":   params,
		"req_id":   fmt.Sprintf("%d", time.Now().UnixNano()),
	})

	return r.cache.Publish(ctx, "device:cmd:"+sn, cmdData).Err()
}

// InsertCommandLog 插入命令日志（发送时调用，status=pending）
func (r *DeviceRepository) InsertCommandLog(ctx context.Context, sn, taskID, cmdType, paramsJSON string) error {
	if r.db == nil {
		return nil
	}
	_, err := r.db.Exec(ctx, `
		INSERT INTO device_cmd_logs (device_sn, task_id, cmd, params, status, sent_at)
		VALUES ($1, $2, $3, $4::jsonb, 'pending', NOW())
	`, sn, taskID, cmdType, paramsJSON)
	return err
}

// UpdateCommandLogStatus 更新命令状态（failed/queued）
func (r *DeviceRepository) UpdateCommandLogStatus(ctx context.Context, taskID, status, message string) error {
	if r.db == nil {
		return nil
	}
	_, err := r.db.Exec(ctx, `
		UPDATE device_cmd_logs SET status = $2, result = $3
		WHERE task_id = $1
	`, taskID, status, message)
	return err
}

// UpdateCommandLogResult 设备回复后更新命令结果
func (r *DeviceRepository) UpdateCommandLogResult(ctx context.Context, taskID, result, message string, data []byte) error {
	if r.db == nil {
		return nil
	}
	_, err := r.db.Exec(ctx, `
		UPDATE device_cmd_logs
		SET status = $2, result = $3, message = $4, data = $5::jsonb
		WHERE task_id = $1
	`, taskID, result, result, message, data)
	return err
}

// InsertNotification 插入通知记录
func (r *DeviceRepository) InsertNotification(ctx context.Context, sn string, stationID, userID int64, notifyType, title, content string) error {
	if r.db == nil {
		return nil
	}
	// 冷却期：60秒内同设备同类型通知不重复
	var exists bool
	_ = r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM notifications WHERE device_sn=$1 AND notify_type=$2 AND created_at > NOW() - INTERVAL '60 seconds')`,
		sn, notifyType,
	).Scan(&exists)
	if exists {
		return nil
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO notifications (device_sn, station_id, user_id, notify_type, title, content, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
	`, sn, stationID, userID, notifyType, title, content)
	return err
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
	// JSONB 数据可能是嵌套格式 {"data": {"daily_pv": ...}} 或扁平格式 {"daily_pv": ...}
	// 使用 COALESCE 兼容两种格式

	// 今日发电量：取今天 data/energy topic 中 daily_pv 的最大值
	dailyQuery := `
		SELECT COALESCE(MAX(COALESCE(
			(data->'data'->>'daily_pv')::float,
			(data->>'daily_pv')::float,
			(data->'data'->>'energy_daily_pv')::float,
			(data->>'energy_daily_pv')::float
		)), 0)
		FROM device_telemetry
		WHERE device_sn = $1 AND time::date = CURRENT_DATE AND topic = 'data/energy'
	`
	var dailyEnergy float64
	r.db.QueryRow(ctx, dailyQuery, sn).Scan(&dailyEnergy)

	// 月发电量：本月每天 daily_pv 最大值之和
	monthlyQuery := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, MAX(COALESCE(
				(data->'data'->>'daily_pv')::float,
				(data->>'daily_pv')::float,
				(data->'data'->>'energy_daily_pv')::float,
				(data->>'energy_daily_pv')::float
			)) as daily_max
			FROM device_telemetry
			WHERE device_sn = $1
			  AND time >= DATE_TRUNC('month', CURRENT_DATE)
			  AND topic = 'data/energy'
			GROUP BY DATE(time)
			HAVING MAX(COALESCE(
				(data->'data'->>'daily_pv')::float,
				(data->>'daily_pv')::float,
				(data->'data'->>'energy_daily_pv')::float,
				(data->>'energy_daily_pv')::float
			)) > 0
		) daily
	`
	var monthlyEnergy float64
	r.db.QueryRow(ctx, monthlyQuery, sn).Scan(&monthlyEnergy)

	// 总发电量：历史每天 daily_pv 最大值之和
	totalQuery := `
		SELECT COALESCE(SUM(daily_max), 0)
		FROM (
			SELECT DATE(time) as day, MAX(COALESCE(
				(data->'data'->>'daily_pv')::float,
				(data->>'daily_pv')::float,
				(data->'data'->>'energy_daily_pv')::float,
				(data->>'energy_daily_pv')::float
			)) as daily_max
			FROM device_telemetry
			WHERE device_sn = $1 AND topic = 'data/energy'
			GROUP BY DATE(time)
			HAVING MAX(COALESCE(
				(data->'data'->>'daily_pv')::float,
				(data->>'daily_pv')::float,
				(data->'data'->>'energy_daily_pv')::float,
				(data->>'energy_daily_pv')::float
			)) > 0
		) daily
	`
	var totalEnergy float64
	r.db.QueryRow(ctx, totalQuery, sn).Scan(&totalEnergy)

	// 今日放电量
	dischargeQuery := `
		SELECT COALESCE(MAX(COALESCE(
			(data->'data'->>'daily_discharge')::float,
			(data->>'daily_discharge')::float,
			(data->'data'->>'energy_daily_discharge')::float,
			(data->>'energy_daily_discharge')::float
		)), 0)
		FROM device_telemetry
		WHERE device_sn = $1 AND time::date = CURRENT_DATE AND topic = 'data/energy'
	`
	var dailyDischarge float64
	r.db.QueryRow(ctx, dischargeQuery, sn).Scan(&dailyDischarge)

	return map[string]interface{}{
		"daily_energy":    dailyEnergy,
		"monthly_energy":  monthlyEnergy,
		"total_energy":    totalEnergy,
		"daily_discharge": dailyDischarge,
		"daily_grid_sell": 0.0,
		"daily_grid_buy":  0.0,
	}, nil
}

// getJSONFloat 从 map 中按优先级取第一个存在的 float64 值
func getJSONFloat(data map[string]interface{}, keys ...string) float64 {
	for _, key := range keys {
		if v, ok := data[key]; ok {
			switch val := v.(type) {
			case float64:
				return val
			case json.Number:
				f, _ := val.Float64()
				return f
			}
		}
	}
	return 0
}

func getJSONString(data map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if v, ok := data[key]; ok {
			if s, ok := v.(string); ok && s != "" {
				return s
			}
		}
	}
	return ""
}

func getJSONInt(data map[string]interface{}, keys ...string) int64 {
	for _, key := range keys {
		if v, ok := data[key]; ok {
			switch val := v.(type) {
			case float64:
				return int64(val)
			case json.Number:
				i, _ := val.Int64()
				return i
			case int64:
				return val
			case int:
				return int64(val)
			}
		}
	}
	return 0
}

func getJSONBool(data map[string]interface{}, keys ...string) (bool, bool) {
	for _, key := range keys {
		if v, ok := data[key]; ok {
			switch val := v.(type) {
			case bool:
				return val, true
			case float64:
				return val != 0, true
			}
		}
	}
	return false, false
}

// skipRawFields 非遥测字段集合，这些字段不应出现在遥测数据表格中
var skipRawFields = map[string]bool{
	// 设备信息（通过 info topic 注册到 devices 表，不在遥测流中）
	"sn": true, "model": true, "manufacturer": true,
	"firmware_arm": true, "firmware_esp": true, "firmware_dsp": true, "firmware_bms": true,
	"type": true, "rated_power": true, "rated_voltage": true, "rated_freq": true,
	"battery_voltage": true, "battery_type": true, "cell_count": true,
	// 通用非数据字段
	"timestamp": true, "topic": true, "device_sn": true,
	"created_at": true, "updated_at": true, "time": true,
	// 数组类型字段（不适合表格列展示）
	"voltages": true, "temps": true, "machines": true,
	// OTA 相关
	"progress": true, "status_message": true, "ack": true,
	"file_md5": true, "file_sha256": true, "file_size": true,
	"target": true, "task_id": true, "url": true, "version": true,
	// 命令/消息相关
	"error_message": true, "message": true, "cmd": true,
	"current_version": true, "device_id": true,
}

func (r *DeviceRepository) GetTelemetryData(ctx context.Context, sn, startTime, endTime, granularity string) ([]map[string]interface{}, error) {
	query := `
		SELECT time, topic, data
		FROM device_telemetry
		WHERE device_sn = $1 AND time >= $2 AND time <= $3
		ORDER BY time ASC
	`

	rows, err := r.db.Query(ctx, query, sn, startTime, endTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// 按时间窗口聚合，将不同 topic 的数据合并到同一时间槽
	type timeSlot struct {
		time              time.Time
		data              map[string]interface{}
		maxDailyPV        float64
		maxDailyDischarge float64
	}

	slots := make(map[string]*timeSlot)
	var orderedKeys []string

	for rows.Next() {
		var dataTime time.Time
		var topic string
		var dataJSON []byte

		if err := rows.Scan(&dataTime, &topic, &dataJSON); err != nil {
			return nil, err
		}

		var rawData map[string]interface{}
		if len(dataJSON) > 0 {
			json.Unmarshal(dataJSON, &rawData)
		}
		if rawData == nil {
			continue
		}

		// 数据可能是嵌套格式 {"data": {...}, "timestamp": ...}，需要提取内层 data
		if nestedData, ok := rawData["data"].(map[string]interface{}); ok {
			rawData = nestedData
		}

		// 根据 granularity 选择聚合粒度
		var key string
		var rounded time.Time
		switch granularity {
		case "hour":
			rounded = dataTime.Truncate(time.Minute)
			key = rounded.Format(time.RFC3339)
		case "week", "month":
			rounded = time.Date(dataTime.Year(), dataTime.Month(), dataTime.Day(), 0, 0, 0, 0, dataTime.Location())
			key = rounded.Format("2006-01-02")
		default: // "day" or empty
			// 判断时间跨度，超过2天按天聚合
			startT, _ := time.Parse(time.RFC3339, startTime)
			endT, _ := time.Parse(time.RFC3339, endTime)
			if !startT.IsZero() && !endT.IsZero() && endT.Sub(startT) > 48*time.Hour {
				rounded = time.Date(dataTime.Year(), dataTime.Month(), dataTime.Day(), 0, 0, 0, 0, dataTime.Location())
				key = rounded.Format("2006-01-02")
			} else {
				rounded = dataTime.Truncate(time.Minute)
				key = rounded.Format(time.RFC3339)
			}
		}

		if _, exists := slots[key]; !exists {
			slots[key] = &timeSlot{time: rounded, data: make(map[string]interface{})}
			orderedKeys = append(orderedKeys, key)
		}
		slot := slots[key]

		// mappedKeys 记录已被标准化映射的原始字段名，避免 pass-through 产生重复列
		mappedKeys := make(map[string]bool)

		// setFloat 设置浮点字段，值为 0 时跳过（减少空列）
		setFloat := func(stdKey string, val float64, rawKeys ...string) {
			if val != 0 {
				slot.data[stdKey] = val
			}
			for _, rk := range rawKeys {
				mappedKeys[rk] = true
			}
		}

		// setString 设置字符串字段
		setString := func(stdKey string, val string, rawKeys ...string) {
			if val != "" {
				slot.data[stdKey] = val
			}
			for _, rk := range rawKeys {
				mappedKeys[rk] = true
			}
		}

		// setInt 设置整数字段
		setInt := func(stdKey string, val int64, rawKeys ...string) {
			if val != 0 {
				slot.data[stdKey] = val
			}
			for _, rk := range rawKeys {
				mappedKeys[rk] = true
			}
		}

		// 根据 topic 提取对应字段，映射为前端标准化的字段名
		switch topic {
		case "data/ac":
			setFloat("ac_voltage", getJSONFloat(rawData, "ac_voltage", "voltage"), "ac_voltage", "voltage")
			setFloat("ac_current", getJSONFloat(rawData, "ac_current", "current"), "ac_current", "current")
			setFloat("ac_power", getJSONFloat(rawData, "ac_power", "power"), "ac_power", "power")
			setFloat("ac_frequency", getJSONFloat(rawData, "ac_frequency", "frequency"), "ac_frequency", "frequency")
			setFloat("apparent_power", getJSONFloat(rawData, "apparent_power", "apparent"), "apparent_power", "apparent")
			setFloat("power_factor", getJSONFloat(rawData, "power_factor", "pf"), "power_factor", "pf")
			setFloat("load_rate", getJSONFloat(rawData, "load_rate", "load_percent"), "load_rate", "load_percent")
			setFloat("voltage_thd", getJSONFloat(rawData, "voltage_thd", "thd_v"), "voltage_thd", "thd_v")

		case "data/battery":
			setFloat("battery_soc", getJSONFloat(rawData, "batt_soc", "soc", "battery_soc"), "batt_soc", "soc", "battery_soc")
			setFloat("battery_voltage", getJSONFloat(rawData, "batt_voltage", "voltage", "battery_voltage"), "batt_voltage", "voltage", "battery_voltage")
			setFloat("battery_current", getJSONFloat(rawData, "batt_current", "current", "battery_current"), "batt_current", "current", "battery_current")
			setFloat("battery_capacity", getJSONFloat(rawData, "batt_capacity", "capacity_remain", "remaining_capacity", "battery_capacity"), "batt_capacity", "capacity_remain", "remaining_capacity", "battery_capacity")
			setFloat("battery_health", getJSONFloat(rawData, "batt_soh", "soh", "battery_health"), "batt_soh", "soh", "battery_health")
			setFloat("rated_capacity", getJSONFloat(rawData, "capacity_total", "rated_capacity"), "capacity_total", "rated_capacity")
			setFloat("charge_discharge_power", getJSONFloat(rawData, "batt_power", "power", "charge_discharge_power"), "batt_power", "power", "charge_discharge_power")
			setInt("cycle_count", getJSONInt(rawData, "cycle_count"), "cycle_count")
			setFloat("cell_max_temp", getJSONFloat(rawData, "temp_max", "cell_max_temp"), "temp_max", "cell_max_temp")
			setFloat("cell_min_temp", getJSONFloat(rawData, "temp_min", "cell_min_temp"), "temp_min", "cell_min_temp")
			setFloat("cell_max_voltage", getJSONFloat(rawData, "cell_volt_max"), "cell_volt_max")
			setFloat("cell_min_voltage", getJSONFloat(rawData, "cell_volt_min"), "cell_volt_min")
			setFloat("cell_voltage_diff", getJSONFloat(rawData, "cell_volt_diff"), "cell_volt_diff")
			setString("charge_status", getJSONString(rawData, "charge_state", "charge_status"), "charge_state", "charge_status")
			setFloat("battery_avg_temp", getJSONFloat(rawData, "temp_battery", "battery_avg_temp"), "temp_battery", "battery_avg_temp")
			setInt("bms_fault_code", getJSONInt(rawData, "bms_fault_code"), "bms_fault_code")
			setFloat("protect_status", getJSONFloat(rawData, "protect_status"), "protect_status")
			// remaining_capacity 已映射到 battery_capacity
			setFloat("max_chg_current", getJSONFloat(rawData, "max_chg_current"), "max_chg_current")
			setFloat("max_dischg_current", getJSONFloat(rawData, "max_dischg_current"), "max_dischg_current")
			setFloat("charge_volt_ref", getJSONFloat(rawData, "charge_volt_ref"), "charge_volt_ref")
			setFloat("dischg_cut_volt", getJSONFloat(rawData, "dischg_cut_volt"), "dischg_cut_volt")

		case "data/pv":
			setFloat("pv1_voltage", getJSONFloat(rawData, "pv1_voltage", "pv_voltage"), "pv1_voltage", "pv_voltage")
			setFloat("pv1_current", getJSONFloat(rawData, "pv1_current", "pv_current"), "pv1_current", "pv_current")
			setFloat("pv1_power", getJSONFloat(rawData, "pv1_power", "pv_power"), "pv1_power", "pv_power")
			setFloat("pv2_voltage", getJSONFloat(rawData, "pv2_voltage"), "pv2_voltage")
			setFloat("pv2_current", getJSONFloat(rawData, "pv2_current"), "pv2_current")
			setFloat("pv2_power", getJSONFloat(rawData, "pv2_power"), "pv2_power")
			setFloat("pv_total_power", getJSONFloat(rawData, "pv_power_total", "pv_total_power"), "pv_power_total", "pv_total_power")
			setString("mppt_status", getJSONString(rawData, "mppt_state", "mppt_status"), "mppt_state", "mppt_status")
			setFloat("pv1_voltage_max", getJSONFloat(rawData, "pv1_voltage_max"), "pv1_voltage_max")
			setFloat("pv1_power_max", getJSONFloat(rawData, "pv1_power_max"), "pv1_power_max")
			setFloat("pv2_voltage_max", getJSONFloat(rawData, "pv2_voltage_max"), "pv2_voltage_max")
			setFloat("pv2_power_max", getJSONFloat(rawData, "pv2_power_max"), "pv2_power_max")

		case "data/status":
			setString("run_status", getJSONString(rawData, "state", "run_status"), "state", "run_status")
			setInt("fault_code", getJSONInt(rawData, "fault_code"), "fault_code")
			setInt("alarm_code", getJSONInt(rawData, "alarm_code"), "alarm_code")
			setFloat("inverter_temp", getJSONFloat(rawData, "temp_inv", "sys_temp_inv", "inverter_temp"), "temp_inv", "sys_temp_inv", "inverter_temp")
			setFloat("heatsink_temp", getJSONFloat(rawData, "temp_mos", "heatsink_temp"), "temp_mos", "heatsink_temp")
			setFloat("ambient_temp", getJSONFloat(rawData, "temp_ambient", "ambient_temp"), "temp_ambient", "ambient_temp")
			setFloat("dc_bus_voltage", getJSONFloat(rawData, "dc_bus_voltage"), "dc_bus_voltage")
			setFloat("vbus1", getJSONFloat(rawData, "vbus1"), "vbus1")
			setFloat("vbus2", getJSONFloat(rawData, "vbus2"), "vbus2")
			setFloat("efficiency", getJSONFloat(rawData, "efficiency", "sys_efficiency"), "efficiency", "sys_efficiency")
			setFloat("run_time", getJSONFloat(rawData, "runtime_hours", "run_time"), "runtime_hours", "run_time")
			setFloat("fan_speed", getJSONFloat(rawData, "fan_speed"), "fan_speed")

		case "data/energy":
			dailyPV := getJSONFloat(rawData, "daily_pv", "energy_daily_pv")
			if dailyPV > slot.maxDailyPV {
				slot.maxDailyPV = dailyPV
			}
			mappedKeys["daily_pv"] = true
			mappedKeys["energy_daily_pv"] = true
			dailyDischarge := getJSONFloat(rawData, "daily_discharge", "energy_daily_discharge")
			if dailyDischarge > slot.maxDailyDischarge {
				slot.maxDailyDischarge = dailyDischarge
			}
			mappedKeys["daily_discharge"] = true
			mappedKeys["energy_daily_discharge"] = true
			setFloat("total_energy", getJSONFloat(rawData, "total_pv", "energy_total_pv"), "total_pv", "energy_total_pv")
			setFloat("daily_charge", getJSONFloat(rawData, "daily_charge", "energy_daily_charge"), "daily_charge", "energy_daily_charge")
			setFloat("total_charge", getJSONFloat(rawData, "total_charge", "energy_total_charge"), "total_charge", "energy_total_charge")
			setFloat("total_discharge", getJSONFloat(rawData, "total_discharge", "energy_total_discharge"), "total_discharge", "energy_total_discharge")
			setFloat("daily_consumption", getJSONFloat(rawData, "daily_load", "energy_daily_load"), "daily_load", "energy_daily_load")
			setFloat("total_consumption", getJSONFloat(rawData, "total_load", "energy_total_load"), "total_load", "energy_total_load")
			setFloat("total_run_time", getJSONFloat(rawData, "runtime_hours", "total_run_time"), "runtime_hours", "total_run_time")

		case "data/control":
			setFloat("power_limit", getJSONFloat(rawData, "power_limit"), "power_limit")
			if v, ok := getJSONBool(rawData, "charge_enable"); ok {
				slot.data["charge_enable"] = v
			}
			mappedKeys["charge_enable"] = true
			if v, ok := getJSONBool(rawData, "discharge_enable"); ok {
				slot.data["discharge_enable"] = v
			}
			mappedKeys["discharge_enable"] = true
			if v, ok := getJSONBool(rawData, "grid_charge_enable"); ok {
				slot.data["grid_charge_enable"] = v
			}
			mappedKeys["grid_charge_enable"] = true
			setFloat("max_charge_current", getJSONFloat(rawData, "max_charge_current"), "max_charge_current")
			setFloat("max_discharge_current", getJSONFloat(rawData, "max_discharge_current"), "max_discharge_current")
		}

		// 透传原始数据中未被映射且非元数据的字段（如 data/cells 的 cell_count 等）
		for rawKey, rawVal := range rawData {
			if mappedKeys[rawKey] || skipRawFields[rawKey] {
				continue
			}
			if _, exists := slot.data[rawKey]; !exists {
				switch v := rawVal.(type) {
				case float64:
					if v != 0 {
						slot.data[rawKey] = v
					}
				case string:
					if v != "" {
						slot.data[rawKey] = v
					}
				case bool:
					slot.data[rawKey] = v
				case nil:
					// skip nil
				default:
					// 跳过数组、嵌套对象等复杂类型
				}
			}
		}
	}

	// 构建结果数组
	results := make([]map[string]interface{}, 0, len(orderedKeys))
	for _, key := range orderedKeys {
		slot := slots[key]
		// 对于按天/周/月聚合的场景，填充能量字段
		if slot.maxDailyPV > 0 {
			slot.data["energy"] = slot.maxDailyPV
		}
		if slot.maxDailyDischarge > 0 {
			slot.data["discharge"] = slot.maxDailyDischarge
		}
		slot.data["time"] = slot.time
		slot.data["timestamp"] = slot.time
		results = append(results, slot.data)
	}

	return results, nil
}

func (r *DeviceRepository) GetLifecycleHistory(ctx context.Context, sn string, page, pageSize int) ([]map[string]interface{}, int64, error) {
	var total int64
	countQuery := `SELECT COUNT(*) FROM device_lifecycle WHERE device_sn = $1`
	if err := r.db.QueryRow(ctx, countQuery, sn).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	query := `
		SELECT id, device_sn, event_type, description, triggered_by, metadata, created_at
		FROM device_lifecycle
		WHERE device_sn = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`

	rows, err := r.db.Query(ctx, query, sn, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	results := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id int64
		var deviceSN, eventType string
		var description *string
		var triggeredBy *int64
		var metadata []byte
		var createdAt time.Time

		if err := rows.Scan(&id, &deviceSN, &eventType, &description, &triggeredBy, &metadata, &createdAt); err != nil {
			return nil, 0, err
		}

		item := map[string]interface{}{
			"id":         id,
			"device_sn":  deviceSN,
			"event_type": eventType,
			"created_at": createdAt,
		}

		if description != nil {
			item["description"] = *description
		}

		if triggeredBy != nil {
			item["triggered_by"] = *triggeredBy
		}

		if len(metadata) > 0 {
			var meta map[string]interface{}
			json.Unmarshal(metadata, &meta)
			item["metadata"] = meta
		}

		results = append(results, item)
	}

	return results, total, nil
}

func (r *DeviceRepository) GetOverview(ctx context.Context, userID int64) (map[string]interface{}, error) {
	query := `
		SELECT COUNT(DISTINCT d.id) as device_count,
			   COUNT(DISTINCT CASE WHEN d.status IN (1, 2) THEN d.id END) as online_count,
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

func (r *DeviceRepository) GetCommandHistory(ctx context.Context, sn string, page, pageSize int) ([]map[string]interface{}, int64, error) {
	offset := (page - 1) * pageSize

	var total int64
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM device_cmd_logs WHERE device_sn = $1`, sn).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	rows, err := r.db.Query(ctx, `
		SELECT id, device_sn, cmd, task_id, params, status, result, message, data, sent_at
		FROM device_cmd_logs 
		WHERE device_sn = $1 
		ORDER BY sent_at DESC 
		LIMIT $2 OFFSET $3
	`, sn, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var commands []map[string]interface{}
	for rows.Next() {
		var id int64
		var deviceSn, cmdName, taskID, status string
		var paramsJSON, dataJSON []byte
		var result, msg *string
		var sentAt *time.Time

		if err := rows.Scan(&id, &deviceSn, &cmdName, &taskID, &paramsJSON, &status, &result, &msg, &dataJSON, &sentAt); err != nil {
			continue
		}

		item := map[string]interface{}{
			"id":            id,
			"device_sn":     deviceSn,
			"command_name":  cmdName,
			"command_label": cmdName,
			"task_id":       taskID,
			"req_id":        taskID,
			"status":        status,
			"created_at":    sentAt,
		}

		if len(paramsJSON) > 0 {
			var p map[string]interface{}
			json.Unmarshal(paramsJSON, &p)
			item["params"] = p
		}
		if msg != nil {
			item["result_message"] = *msg
		}
		if result != nil {
			item["result"] = *result
		}
		if len(dataJSON) > 0 {
			var d map[string]interface{}
			json.Unmarshal(dataJSON, &d)
			item["data"] = d
		}

		commands = append(commands, item)
	}

	return commands, total, nil
}

func (r *DeviceRepository) Delete(ctx context.Context, sn string) error {
	_, err := r.db.Exec(ctx, `UPDATE devices SET deleted_at = NOW() WHERE sn = $1`, sn)
	if err == nil {
		r.invalidateDeviceCache(ctx, sn)
	}
	return err
}

type AlarmRepository struct {
	db *pgxpool.Pool
}

func NewAlarmRepository(db *pgxpool.Pool) *AlarmRepository {
	return &AlarmRepository{db: db}
}

type AlarmListParams struct {
	UserID     int64
	StationID  int64
	Status     int
	AlarmLevel int
	Keyword    string
	Page       int
	PageSize   int
	Role       int
}

func (r *AlarmRepository) List(ctx context.Context, params AlarmListParams) ([]*model.Alarm, int64, error) {
	offset := (params.Page - 1) * params.PageSize

	// 管理员角色 (role <= 1) 可查看所有告警，普通用户只能查看自己的
	isAdmin := params.Role <= 1

	var baseQuery string
	var args []interface{}
	argIdx := 1

	if isAdmin {
		baseQuery = `FROM alarms WHERE 1=1`
	} else {
		baseQuery = `FROM alarms WHERE user_id = $1`
		args = append(args, params.UserID)
		argIdx = 2
	}

	if params.StationID > 0 {
		baseQuery += fmt.Sprintf(" AND station_id = $%d", argIdx)
		args = append(args, params.StationID)
		argIdx++
	}

	if params.Status >= 0 {
		baseQuery += fmt.Sprintf(" AND status = $%d", argIdx)
		args = append(args, params.Status)
		argIdx++
	}

	if params.AlarmLevel > 0 {
		baseQuery += fmt.Sprintf(" AND alarm_level = $%d", argIdx)
		args = append(args, params.AlarmLevel)
		argIdx++
	}

	if params.Keyword != "" {
		baseQuery += fmt.Sprintf(" AND (device_sn ILIKE $%d OR fault_message ILIKE $%d OR fault_code ILIKE $%d)", argIdx, argIdx, argIdx)
		args = append(args, "%"+params.Keyword+"%")
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

	args = append(args, params.PageSize, offset)

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
	query := `UPDATE alarms SET status = 1 WHERE id = ANY($1) AND status = 0`
	_, err := r.db.Exec(ctx, query, ids)
	return err
}

func (r *AlarmRepository) MarkIgnored(ctx context.Context, id int64) error {
	query := `UPDATE alarms SET status = 2 WHERE id = $1`
	_, err := r.db.Exec(ctx, query, id)
	return err
}

func (r *AlarmRepository) Delete(ctx context.Context, id int64) error {
	query := `DELETE FROM alarms WHERE id = $1`
	_, err := r.db.Exec(ctx, query, id)
	return err
}

func (r *AlarmRepository) ClearAll(ctx context.Context) error {
	query := `DELETE FROM alarms`
	_, err := r.db.Exec(ctx, query)
	return err
}

func (r *AlarmRepository) GetStats(ctx context.Context, userID int64, role ...int) (map[string]interface{}, error) {
	isAdmin := len(role) > 0 && role[0] <= 1

	var query string
	if isAdmin {
		query = `
			SELECT COUNT(*) as total,
				   COUNT(CASE WHEN status = 0 THEN 1 END) as unhandled,
				   COUNT(CASE WHEN status = 1 THEN 1 END) as handled,
				   COUNT(CASE WHEN alarm_level = 3 THEN 1 END) as critical
			FROM alarms
		`
	} else {
		query = `
			SELECT COUNT(*) as total,
				   COUNT(CASE WHEN status = 0 THEN 1 END) as unhandled,
				   COUNT(CASE WHEN status = 1 THEN 1 END) as handled,
				   COUNT(CASE WHEN alarm_level = 3 THEN 1 END) as critical
			FROM alarms
			WHERE user_id = $1
		`
	}

	var total, unhandled, handled, critical int
	if isAdmin {
		if err := r.db.QueryRow(ctx, query).Scan(&total, &unhandled, &handled, &critical); err != nil {
			return nil, err
		}
	} else {
		if err := r.db.QueryRow(ctx, query, userID).Scan(&total, &unhandled, &handled, &critical); err != nil {
			return nil, err
		}
	}
	return map[string]interface{}{
		"total":     total,
		"unhandled": unhandled,
		"handled":   handled,
		"critical":  critical,
	}, nil
}

func (r *DeviceRepository) GetUnbindRequests(ctx context.Context, page, pageSize int) ([]map[string]interface{}, int64, error) {
	var total int64
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM device_unbind_requests`).Scan(&total); err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	query := `
		SELECT id, device_sn, requested_by, reason, status, reviewed_by, review_comment, reviewed_at, created_at
		FROM device_unbind_requests
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2
	`
	rows, err := r.db.Query(ctx, query, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	results := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id int64
		var deviceSN string
		var requestedBy int64
		var reason, status *string
		var reviewedBy *int64
		var reviewComment *string
		var reviewedAt, createdAt *time.Time

		if err := rows.Scan(&id, &deviceSN, &requestedBy, &reason, &status, &reviewedBy, &reviewComment, &reviewedAt, &createdAt); err != nil {
			return nil, 0, err
		}

		item := map[string]interface{}{
			"id":           id,
			"device_sn":    deviceSN,
			"requested_by": requestedBy,
		}
		if reason != nil {
			item["reason"] = *reason
		}
		if status != nil {
			item["status"] = *status
		}
		if reviewedBy != nil {
			item["reviewed_by"] = *reviewedBy
		}
		if reviewComment != nil {
			item["review_comment"] = *reviewComment
		}
		if reviewedAt != nil {
			item["reviewed_at"] = *reviewedAt
		}
		if createdAt != nil {
			item["created_at"] = *createdAt
		}
		results = append(results, item)
	}
	return results, total, nil
}

func (r *DeviceRepository) ApproveUnbind(ctx context.Context, id int64, reviewerID int64, comment string) error {
	query := `UPDATE device_unbind_requests SET status = 'approved', reviewed_by = $1, review_comment = $2, reviewed_at = NOW() WHERE id = $3 AND status = 'pending'`
	tag, err := r.db.Exec(ctx, query, reviewerID, comment, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("request not found or already processed")
	}

	var deviceSN string
	if err := r.db.QueryRow(ctx, `SELECT device_sn FROM device_unbind_requests WHERE id = $1`, id).Scan(&deviceSN); err == nil {
		r.db.Exec(ctx, `UPDATE devices SET user_id = 0, station_id = NULL WHERE sn = $1`, deviceSN)
	}
	return nil
}

func (r *DeviceRepository) RejectUnbind(ctx context.Context, id int64, reviewerID int64, comment string) error {
	query := `UPDATE device_unbind_requests SET status = 'rejected', reviewed_by = $1, review_comment = $2, reviewed_at = NOW() WHERE id = $3 AND status = 'pending'`
	tag, err := r.db.Exec(ctx, query, reviewerID, comment, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("request not found or already processed")
	}
	return nil
}

func (r *UserRepository) LogAudit(ctx context.Context, operatorID int64, operatorName, action, resourceType, resourceID, detail, ip string) {
	// resource_id 为 bigint 类型，空字符串会导致类型转换错误
	var resID *int64
	if resourceID != "" {
		if v, err := strconv.ParseInt(resourceID, 10, 64); err == nil {
			resID = &v
		}
	}
	query := `INSERT INTO audit_logs (operator_id, operator_name, action, resource_type, resource_id, detail, ip, created_at)
			  VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())`
	_, err := r.db.Exec(ctx, query, operatorID, operatorName, action, resourceType, resID, detail, ip)
	if err != nil {
		// 审计日志写入失败不影响主业务，仅记录警告
		fmt.Printf("Failed to write audit log: %v\n", err)
	}
}
