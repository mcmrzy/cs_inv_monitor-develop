"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var DashboardService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.DashboardService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const device_entity_1 = require("../../entities/device.entity");
const station_entity_1 = require("../../entities/station.entity");
const user_entity_1 = require("../../entities/user.entity");
const alert_entity_1 = require("../../entities/alert.entity");
const device_telemetry_entity_1 = require("../../entities/device-telemetry.entity");
const ota_task_entity_1 = require("../../entities/ota-task.entity");
const role_enum_1 = require("../../common/enums/role.enum");
let DashboardService = DashboardService_1 = class DashboardService {
    constructor(deviceRepo, stationRepo, userRepo, alertRepo, telemetryRepo, otaTaskRepo) {
        this.deviceRepo = deviceRepo;
        this.stationRepo = stationRepo;
        this.userRepo = userRepo;
        this.alertRepo = alertRepo;
        this.telemetryRepo = telemetryRepo;
        this.otaTaskRepo = otaTaskRepo;
        this.logger = new common_1.Logger(DashboardService_1.name);
    }
    applyRoleFilterForDevice(qb, user) {
        if (user.role === role_enum_1.Role.SUPER_ADMIN)
            return;
        if (user.role === role_enum_1.Role.AGENT) {
            qb.andWhere('device.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.INSTALLER) {
            qb.andWhere('(device.user_id = :userId OR device.installer_id = :userId)', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.END_USER) {
            qb.andWhere('device.user_id = :userId', { userId: user.id });
        }
    }
    applyRoleFilterForAlert(qb, user) {
        if (user.role === role_enum_1.Role.SUPER_ADMIN)
            return;
        if (user.role === role_enum_1.Role.END_USER) {
            qb.andWhere('alert.user_id = :userId', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.INSTALLER) {
            qb.leftJoin(device_entity_1.Device, 'd', 'd.sn = alert.device_sn')
                .andWhere('(alert.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.AGENT) {
            qb.andWhere('alert.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
        }
    }
    applyRoleFilterForTelemetry(qb, user) {
        if (user.role === role_enum_1.Role.SUPER_ADMIN)
            return;
        if (user.role === role_enum_1.Role.END_USER) {
            qb.leftJoin(device_entity_1.Device, 'd', 'd.sn = telem.device_sn')
                .andWhere('d.user_id = :userId', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.INSTALLER) {
            qb.leftJoin(device_entity_1.Device, 'd', 'd.sn = telem.device_sn')
                .andWhere('(d.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.AGENT) {
            qb.leftJoin(device_entity_1.Device, 'd', 'd.sn = telem.device_sn')
                .andWhere('d.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
        }
    }
    buildTelemetryRoleClause(user, idx) {
        switch (user.role) {
            case role_enum_1.Role.SUPER_ADMIN:
                return { join: '', where: '' };
            case role_enum_1.Role.END_USER:
                return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND d.user_id = $${idx}` };
            case role_enum_1.Role.INSTALLER:
                return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND (d.user_id = $${idx} OR d.installer_id = $${idx})` };
            case role_enum_1.Role.AGENT:
                return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND d.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = $${idx} OR u.id = $${idx})` };
            default:
                return { join: '', where: '' };
        }
    }
    async getStatistics(currentUser) {
        const deviceQb = this.deviceRepo.createQueryBuilder('device');
        this.applyRoleFilterForDevice(deviceQb, currentUser);
        const total = await deviceQb.clone().getCount();
        const online = await deviceQb.clone().andWhere('device.status = 1').getCount();
        const offline = await deviceQb.clone().andWhere('device.status = 0').getCount();
        const fault = await deviceQb.clone().andWhere('device.status = 2').getCount();
        let stationTotal;
        if (currentUser.role === role_enum_1.Role.SUPER_ADMIN) {
            stationTotal = await this.stationRepo.count();
        }
        else if (currentUser.role === role_enum_1.Role.AGENT) {
            stationTotal = await this.stationRepo
                .createQueryBuilder('station')
                .where('station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: currentUser.id })
                .getCount();
        }
        else {
            stationTotal = await this.stationRepo.count({ where: { user_id: currentUser.id } });
        }
        let userTotal;
        if (currentUser.role === role_enum_1.Role.SUPER_ADMIN) {
            userTotal = await this.userRepo.count();
        }
        else if (currentUser.role === role_enum_1.Role.AGENT) {
            userTotal = await this.userRepo
                .createQueryBuilder('user')
                .where('user.parent_id = :userId OR user.id = :userId', { userId: currentUser.id })
                .getCount();
        }
        else {
            userTotal = 1;
        }
        const alertQb = this.alertRepo.createQueryBuilder('alert');
        this.applyRoleFilterForAlert(alertQb, currentUser);
        const alertTotal = await alertQb.clone().getCount();
        const unhandled = await alertQb.clone().andWhere('alert.status = 0').getCount();
        const critical = await alertQb.clone().andWhere('alert.alarm_level = 1').getCount();
        const warning = await alertQb.clone().andWhere('alert.alarm_level = 2').getCount();
        const info = await alertQb.clone().andWhere('alert.alarm_level = 3').getCount();
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const { join, where } = this.buildTelemetryRoleClause(currentUser, 2);
        const params = [todayStart];
        if (currentUser.role !== role_enum_1.Role.SUPER_ADMIN) {
            params.push(currentUser.id);
        }
        const todayResult = await this.telemetryRepo.manager.query(`
      SELECT COALESCE(SUM(max_val), 0) as energy FROM (
        SELECT MAX(telem.daily_energy) as max_val
        FROM device_telemetry telem
        ${join}
        WHERE telem.time >= $1 ${where}
        GROUP BY telem.device_sn
      ) sub
    `, params);
        const todayEnergy = Number(todayResult[0]?.energy ?? 0);
        const { join: totalJoin, where: totalWhere } = this.buildTelemetryRoleClause(currentUser, 1);
        const totalParams = currentUser.role !== role_enum_1.Role.SUPER_ADMIN ? [currentUser.id] : [];
        const totalResult = await this.telemetryRepo.manager.query(`
      SELECT COALESCE(SUM(max_val), 0) as energy FROM (
        SELECT MAX(CAST(telem.data->'energy'->>'total_pv' AS DECIMAL)) as max_val
        FROM device_telemetry telem
        ${totalJoin}
        WHERE 1=1 ${totalWhere}
        GROUP BY telem.device_sn
      ) sub
    `, totalParams);
        const totalEnergy = Number(totalResult[0]?.energy ?? 0);
        const onlineRate = total > 0 ? Math.round((online / total) * 10000) / 100 : 0;
        const recentAlerts = await alertQb
            .clone()
            .andWhere('alert.status = 0')
            .orderBy('alert.occurred_at', 'DESC')
            .take(5)
            .getMany();
        return {
            deviceStats: { total, online, offline, fault },
            stationStats: { total: stationTotal },
            userStats: { total: userTotal },
            alertStats: { total: alertTotal, unhandled, critical, warning, info },
            todayEnergy,
            totalEnergy,
            onlineRate,
            recentAlerts,
        };
    }
    async getTrend(type, currentUser) {
        const now = new Date();
        let startDate;
        let bucketExpr;
        let labelExpr;
        switch (type) {
            case 'month':
                startDate = new Date(now.getFullYear(), now.getMonth(), 1);
                bucketExpr = 'DATE(telem.time)';
                labelExpr = "TO_CHAR(sub.bucket, 'MM-DD')";
                break;
            case 'year':
                startDate = new Date(now.getFullYear(), 0, 1);
                bucketExpr = "DATE_TRUNC('month', telem.time)";
                labelExpr = "TO_CHAR(sub.bucket, 'YYYY-MM')";
                break;
            case 'day':
            default:
                startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
                bucketExpr = "TO_CHAR(telem.time, 'HH24')";
                labelExpr = 'sub.bucket';
                break;
        }
        const { join, where } = this.buildTelemetryRoleClause(currentUser, 2);
        const params = [startDate];
        if (currentUser.role !== role_enum_1.Role.SUPER_ADMIN) {
            params.push(currentUser.id);
        }
        const result = await this.telemetryRepo.manager.query(`
      SELECT ${labelExpr} as label, COALESCE(SUM(sub.max_val), 0) as energy
      FROM (
        SELECT ${bucketExpr} as bucket, MAX(telem.daily_energy) as max_val
        FROM device_telemetry telem
        ${join}
        WHERE telem.time >= $1 ${where}
        GROUP BY telem.device_sn, bucket
      ) sub
      GROUP BY sub.bucket
      ORDER BY sub.bucket ASC
    `, params);
        return {
            type,
            data: result.map((row) => ({
                label: type === 'day' ? row.label + ':00' : row.label,
                energy: Number(row.energy),
            })),
        };
    }
    async getDeviceStatusDistribution(currentUser) {
        const qb = this.deviceRepo.createQueryBuilder('device');
        this.applyRoleFilterForDevice(qb, currentUser);
        const total = await qb.clone().getCount();
        const online = await qb.clone().andWhere('device.status = 1').getCount();
        const offline = await qb.clone().andWhere('device.status = 0').getCount();
        const fault = await qb.clone().andWhere('device.status = 2').getCount();
        return [
            { name: '在线', value: online, status: 1 },
            { name: '离线', value: offline, status: 0 },
            { name: '故障', value: fault, status: 2 },
            { name: '总计', value: total, status: -1 },
        ];
    }
    async compareDevices(devices, metric, startTime, endTime, currentUser) {
        const deviceSns = devices.split(',').filter((s) => s.trim());
        if (deviceSns.length === 0 || deviceSns.length > 4) {
            return { devices: [], metric, series: [] };
        }
        const allowedMetrics = [
            'total_active_power',
            'daily_energy',
            'internal_temperature',
            'work_state',
            'fault_code',
        ];
        const metricField = allowedMetrics.includes(metric) ? metric : 'total_active_power';
        const qb = this.telemetryRepo.createQueryBuilder('t')
            .where('t.device_sn IN (:...sns)', { sns: deviceSns })
            .orderBy('t.time', 'ASC');
        if (startTime) {
            qb.andWhere('t.time >= :startTime', { startTime: new Date(startTime) });
        }
        if (endTime) {
            qb.andWhere('t.time <= :endTime', { endTime: new Date(endTime) });
        }
        const rows = await qb.getMany();
        const timeMap = new Map();
        for (const row of rows) {
            const timeKey = row.time.toISOString();
            if (!timeMap.has(timeKey)) {
                timeMap.set(timeKey, {});
            }
            const entry = timeMap.get(timeKey);
            const d = row.data;
            let value = 0;
            if (d) {
                if (metric === 'total_active_power' || metric === '')
                    value = Number(d?.ac?.power ?? 0);
                else if (metric === 'daily_energy')
                    value = Number(d?.energy?.daily_pv ?? 0);
                else if (metric === 'internal_temperature')
                    value = Number(d?.sys_status?.temp_inv ?? 0);
                else if (metric === 'work_state')
                    value = row.work_state ? 1 : 0;
                else if (metric === 'fault_code')
                    value = Number(d?.sys_status?.fault_code ?? 0);
            }
            entry[row.device_sn] = value;
        }
        const series = Array.from(timeMap.entries())
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([time, values]) => ({
            time,
            ...values,
        }));
        return {
            devices: deviceSns,
            metric: metricField,
            series,
        };
    }
    async getBigScreen(currentUser) {
        const deviceQb = this.deviceRepo.createQueryBuilder('device');
        this.applyRoleFilterForDevice(deviceQb, currentUser);
        const total = await deviceQb.clone().getCount();
        const online = await deviceQb.clone().andWhere('device.status = 1').getCount();
        const offline = await deviceQb.clone().andWhere('device.status = 0').getCount();
        const fault = await deviceQb.clone().andWhere('device.status = 2').getCount();
        const onlineRate = total > 0 ? Math.round((online / total) * 10000) / 100 : 0;
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const { join, where } = this.buildTelemetryRoleClause(currentUser, 2);
        const params = [todayStart];
        if (currentUser.role !== role_enum_1.Role.SUPER_ADMIN) {
            params.push(currentUser.id);
        }
        const todayResult = await this.telemetryRepo.manager.query(`
      SELECT COALESCE(SUM(max_val), 0) as energy FROM (
        SELECT MAX(telem.daily_energy) as max_val
        FROM device_telemetry telem
        ${join}
        WHERE telem.time >= $1 ${where}
        GROUP BY telem.device_sn
      ) sub
    `, params);
        const todayEnergy = Number(todayResult[0]?.energy ?? 0);
        const { join: totalJoin, where: totalWhere } = this.buildTelemetryRoleClause(currentUser, 1);
        const totalParams = currentUser.role !== role_enum_1.Role.SUPER_ADMIN ? [currentUser.id] : [];
        const totalResult = await this.telemetryRepo.manager.query(`
      SELECT COALESCE(SUM(max_val), 0) as energy FROM (
        SELECT MAX(CAST(telem.data->'energy'->>'total_pv' AS DECIMAL)) as max_val
        FROM device_telemetry telem
        ${totalJoin}
        WHERE 1=1 ${totalWhere}
        GROUP BY telem.device_sn
      ) sub
    `, totalParams);
        const totalEnergy = Number(totalResult[0]?.energy ?? 0);
        const co2 = Math.round(totalEnergy * 0.997 * 100) / 100;
        const trees = Math.round(totalEnergy * 0.045);
        let stationsQuery = this.stationRepo.createQueryBuilder('station');
        if (currentUser.role !== role_enum_1.Role.SUPER_ADMIN) {
            if (currentUser.role === role_enum_1.Role.AGENT) {
                stationsQuery = stationsQuery.where('station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: currentUser.id });
            }
            else {
                stationsQuery = stationsQuery.where('station.user_id = :userId', { userId: currentUser.id });
            }
        }
        const stations = await stationsQuery.getMany();
        const stationList = await Promise.all(stations
            .filter((s) => s.latitude != null && s.longitude != null)
            .map(async (station) => {
            const deviceCount = await this.deviceRepo.count({
                where: this.buildStationDeviceWhere(station.id, currentUser),
            });
            const onlineCount = await this.deviceRepo.count({
                where: { ...this.buildStationDeviceWhere(station.id, currentUser), status: 1 },
            });
            let power = 0;
            try {
                const latestTelem = await this.telemetryRepo
                    .createQueryBuilder('telem')
                    .leftJoin(device_entity_1.Device, 'd', 'd.sn = telem.device_sn')
                    .where('d.station_id = :stationId', { stationId: station.id })
                    .orderBy('telem.time', 'DESC')
                    .limit(1)
                    .getOne();
                if (latestTelem && latestTelem.data) {
                    const d = latestTelem.data;
                    power = Number(d?.ac?.power ?? 0);
                }
            }
            catch {
                power = 0;
            }
            return {
                id: station.id,
                name: station.name,
                lat: station.latitude,
                lng: station.longitude,
                deviceCount,
                onlineCount,
                power,
            };
        }));
        const alertQb = this.alertRepo.createQueryBuilder('alert');
        this.applyRoleFilterForAlert(alertQb, currentUser);
        const recentAlerts = await alertQb
            .clone()
            .orderBy('alert.occurred_at', 'DESC')
            .take(10)
            .getMany();
        const formattedAlerts = recentAlerts.map((a) => ({
            id: a.id,
            deviceSn: a.device_sn,
            alarmLevel: this.mapAlarmLevel(a.alarm_level),
            faultCode: a.fault_code,
            faultMessage: a.fault_message,
            status: a.status === 0 ? 'unhandled' : a.status === 1 ? 'handled' : 'recovered',
            occurredAt: a.occurred_at?.toISOString(),
        }));
        let pvPower = 0;
        let gridPower = 0;
        let batteryPower = 0;
        let loadPower = 0;
        try {
            const telemetryQb = this.telemetryRepo.createQueryBuilder('telem');
            this.applyRoleFilterForTelemetry(telemetryQb, currentUser);
            const latestTelems = await telemetryQb
                .clone()
                .orderBy('telem.time', 'DESC')
                .limit(100)
                .getMany();
            for (const t of latestTelems) {
                const d = t.data;
                pvPower += Number(d?.pv_power ?? d?.pvPower ?? 0);
                gridPower += Number(d?.grid_power ?? d?.gridPower ?? 0);
                batteryPower += Number(d?.battery_power ?? d?.batteryPower ?? 0);
                loadPower += Number(d?.load_power ?? d?.loadPower ?? 0);
            }
        }
        catch {
        }
        const trendResult = await this.telemetryRepo.manager.query(`
      SELECT sub.hour as label, COALESCE(SUM(sub.max_val), 0) as energy
      FROM (
        SELECT TO_CHAR(telem.time, 'HH24') as hour, MAX(telem.daily_energy) as max_val
        FROM device_telemetry telem
        ${join}
        WHERE telem.time >= $1 ${where}
        GROUP BY telem.device_sn, hour
      ) sub
      GROUP BY sub.hour
      ORDER BY sub.hour ASC
    `, params);
        const trendData = trendResult.map((row) => ({
            label: row.label,
            energy: Number(row.energy),
        }));
        const otaTasks = await this.otaTaskRepo.find({
            order: { created_at: 'DESC' },
            take: 5,
        });
        const formattedOtaTasks = otaTasks.map((t) => ({
            id: t.id,
            name: t.name,
            status: t.status,
            totalDevices: t.total_devices,
            successCount: t.success_count,
            failedCount: t.failed_count,
            progress: t.total_devices > 0
                ? Math.round(((t.success_count + t.failed_count) / t.total_devices) * 100)
                : 0,
            createdAt: t.created_at?.toISOString(),
        }));
        const uptime = process.uptime();
        const uptimeDays = Math.floor(uptime / 86400);
        const uptimeStr = uptimeDays > 0 ? `${uptimeDays}d` : `${Math.floor(uptime / 3600)}h`;
        return {
            totals: { devices: total, online, offline, fault },
            energy: { today: todayEnergy, total: totalEnergy, todayIncome: Math.round(todayEnergy * 0.6 * 100) / 100 },
            carbonReduction: { co2, trees },
            onlineRate,
            stations: stationList,
            recentAlerts: formattedAlerts,
            powerFlow: { pv: Math.round(pvPower * 100) / 100, grid: Math.round(gridPower * 100) / 100, battery: Math.round(batteryPower * 100) / 100, load: Math.round(loadPower * 100) / 100 },
            trend: trendData,
            otaTasks: formattedOtaTasks,
            systemHealth: { uptime: uptimeStr, db: true, redis: true, mqtt: true },
        };
    }
    buildStationDeviceWhere(stationId, user) {
        if (user.role === role_enum_1.Role.SUPER_ADMIN)
            return { station_id: stationId };
        if (user.role === role_enum_1.Role.AGENT)
            return { station_id: stationId };
        if (user.role === role_enum_1.Role.END_USER)
            return { station_id: stationId, user_id: user.id };
        if (user.role === role_enum_1.Role.INSTALLER)
            return { station_id: stationId };
        return { station_id: stationId };
    }
    mapAlarmLevel(level) {
        switch (level) {
            case 1: return 'critical';
            case 2: return 'major';
            case 3: return 'minor';
            default: return 'warning';
        }
    }
};
exports.DashboardService = DashboardService;
exports.DashboardService = DashboardService = DashboardService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(1, (0, typeorm_1.InjectRepository)(station_entity_1.Station)),
    __param(2, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __param(3, (0, typeorm_1.InjectRepository)(alert_entity_1.Alert)),
    __param(4, (0, typeorm_1.InjectRepository)(device_telemetry_entity_1.DeviceTelemetry)),
    __param(5, (0, typeorm_1.InjectRepository)(ota_task_entity_1.OtaTask)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository])
], DashboardService);
//# sourceMappingURL=dashboard.service.js.map