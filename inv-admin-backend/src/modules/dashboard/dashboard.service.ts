import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder } from 'typeorm';
import { Device } from '../../entities/device.entity';
import { Station } from '../../entities/station.entity';
import { User } from '../../entities/user.entity';
import { Alert } from '../../entities/alert.entity';
import { DeviceTelemetry } from '../../entities/device-telemetry.entity';
import { OtaTask } from '../../entities/ota-task.entity';
import { Role } from '../../common/enums/role.enum';

interface CurrentUser {
  id: number;
  role: Role;
}

@Injectable()
export class DashboardService {
  private readonly logger = new Logger(DashboardService.name);

  constructor(
    @InjectRepository(Device)
    private deviceRepo: Repository<Device>,
    @InjectRepository(Station)
    private stationRepo: Repository<Station>,
    @InjectRepository(User)
    private userRepo: Repository<User>,
    @InjectRepository(Alert)
    private alertRepo: Repository<Alert>,
    @InjectRepository(DeviceTelemetry)
    private telemetryRepo: Repository<DeviceTelemetry>,
    @InjectRepository(OtaTask)
    private otaTaskRepo: Repository<OtaTask>,
  ) {}

  private applyRoleFilterForDevice(qb: SelectQueryBuilder<Device>, user: CurrentUser): void {
    if (user.role === Role.SUPER_ADMIN) return;
    if (user.role === Role.AGENT) {
      qb.andWhere(
        'device.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
        { userId: user.id },
      );
    } else if (user.role === Role.INSTALLER) {
      qb.andWhere('(device.user_id = :userId OR device.installer_id = :userId)', { userId: user.id });
    } else if (user.role === Role.END_USER) {
      qb.andWhere('device.user_id = :userId', { userId: user.id });
    }
  }

  private applyRoleFilterForAlert(qb: SelectQueryBuilder<Alert>, user: CurrentUser): void {
    if (user.role === Role.SUPER_ADMIN) return;
    if (user.role === Role.END_USER) {
      qb.andWhere('alert.user_id = :userId', { userId: user.id });
    } else if (user.role === Role.INSTALLER) {
      qb.leftJoin(Device, 'd', 'd.sn = alert.device_sn')
        .andWhere('(alert.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
    } else if (user.role === Role.AGENT) {
      qb.andWhere(
        'alert.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
        { userId: user.id },
      );
    }
  }

  private applyRoleFilterForTelemetry(qb: SelectQueryBuilder<DeviceTelemetry>, user: CurrentUser): void {
    if (user.role === Role.SUPER_ADMIN) return;
    if (user.role === Role.END_USER) {
      qb.leftJoin(Device, 'd', 'd.sn = telem.device_sn')
        .andWhere('d.user_id = :userId', { userId: user.id });
    } else if (user.role === Role.INSTALLER) {
      qb.leftJoin(Device, 'd', 'd.sn = telem.device_sn')
        .andWhere('(d.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
    } else if (user.role === Role.AGENT) {
      qb.leftJoin(Device, 'd', 'd.sn = telem.device_sn')
        .andWhere(
          'd.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
          { userId: user.id },
        );
    }
  }

  private buildTelemetryRoleClause(user: CurrentUser, idx: number): { join: string; where: string } {
    switch (user.role) {
      case Role.SUPER_ADMIN:
        return { join: '', where: '' };
      case Role.END_USER:
        return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND d.user_id = $${idx}` };
      case Role.INSTALLER:
        return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND (d.user_id = $${idx} OR d.installer_id = $${idx})` };
      case Role.AGENT:
        return { join: 'LEFT JOIN devices d ON d.sn = telem.device_sn', where: `AND d.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = $${idx} OR u.id = $${idx})` };
      default:
        return { join: '', where: '' };
    }
  }

  async getStatistics(currentUser: CurrentUser) {
    const deviceQb = this.deviceRepo.createQueryBuilder('device');
    this.applyRoleFilterForDevice(deviceQb, currentUser);

    const total = await deviceQb.clone().getCount();
    const online = await deviceQb.clone().andWhere('device.status = 1').getCount();
    const offline = await deviceQb.clone().andWhere('device.status = 0').getCount();
    const fault = await deviceQb.clone().andWhere('device.status = 2').getCount();

    let stationTotal: number;
    if (currentUser.role === Role.SUPER_ADMIN) {
      stationTotal = await this.stationRepo.count();
    } else if (currentUser.role === Role.AGENT) {
      stationTotal = await this.stationRepo
        .createQueryBuilder('station')
        .where(
          'station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
          { userId: currentUser.id },
        )
        .getCount();
    } else {
      stationTotal = await this.stationRepo.count({ where: { user_id: currentUser.id } });
    }

    let userTotal: number;
    if (currentUser.role === Role.SUPER_ADMIN) {
      userTotal = await this.userRepo.count();
    } else if (currentUser.role === Role.AGENT) {
      userTotal = await this.userRepo
        .createQueryBuilder('user')
        .where('user.parent_id = :userId OR user.id = :userId', { userId: currentUser.id })
        .getCount();
    } else {
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
    const params: any[] = [todayStart];
    if (currentUser.role !== Role.SUPER_ADMIN) {
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
    const totalParams: any[] = currentUser.role !== Role.SUPER_ADMIN ? [currentUser.id] : [];

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

  async getTrend(type: 'day' | 'month' | 'year', currentUser: CurrentUser) {
    const now = new Date();
    let startDate: Date;
    let bucketExpr: string;
    let labelExpr: string;

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
    const params: any[] = [startDate];
    if (currentUser.role !== Role.SUPER_ADMIN) {
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
      data: result.map((row: any) => ({
        label: type === 'day' ? row.label + ':00' : row.label,
        energy: Number(row.energy),
      })),
    };
  }

  async getDeviceStatusDistribution(currentUser: CurrentUser) {
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

  async compareDevices(
    devices: string,
    metric: string,
    startTime: string,
    endTime: string,
    currentUser: CurrentUser,
  ) {
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

    const timeMap = new Map<string, Record<string, number | string>>();

    for (const row of rows) {
      const timeKey = row.time.toISOString();
      if (!timeMap.has(timeKey)) {
        timeMap.set(timeKey, {});
      }
      const entry = timeMap.get(timeKey)!;
      const d = row.data as Record<string, any> | null;
      let value: number = 0;
      if (d) {
        if (metric === 'total_active_power' || metric === '') value = Number(d?.ac?.power ?? 0);
        else if (metric === 'daily_energy') value = Number(d?.energy?.daily_pv ?? 0);
        else if (metric === 'internal_temperature') value = Number(d?.sys_status?.temp_inv ?? 0);
        else if (metric === 'work_state') value = row.work_state ? 1 : 0;
        else if (metric === 'fault_code') value = Number(d?.sys_status?.fault_code ?? 0);
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

  async getBigScreen(currentUser: CurrentUser) {
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
    const params: any[] = [todayStart];
    if (currentUser.role !== Role.SUPER_ADMIN) {
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
    const totalParams: any[] = currentUser.role !== Role.SUPER_ADMIN ? [currentUser.id] : [];

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
    if (currentUser.role !== Role.SUPER_ADMIN) {
      if (currentUser.role === Role.AGENT) {
        stationsQuery = stationsQuery.where(
          'station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
          { userId: currentUser.id },
        );
      } else {
        stationsQuery = stationsQuery.where('station.user_id = :userId', { userId: currentUser.id });
      }
    }
    const stations = await stationsQuery.getMany();

    const stationList = await Promise.all(
      stations
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
              .leftJoin(Device, 'd', 'd.sn = telem.device_sn')
              .where('d.station_id = :stationId', { stationId: station.id })
              .orderBy('telem.time', 'DESC')
              .limit(1)
              .getOne();
            if (latestTelem && latestTelem.data) {
              const d = latestTelem.data as Record<string, any>;
              power = Number(d?.ac?.power ?? 0);
            }
          } catch {
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
        }),
    );

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
        const d = t.data as Record<string, unknown>;
        pvPower += Number(d?.pv_power ?? d?.pvPower ?? 0);
        gridPower += Number(d?.grid_power ?? d?.gridPower ?? 0);
        batteryPower += Number(d?.battery_power ?? d?.batteryPower ?? 0);
        loadPower += Number(d?.load_power ?? d?.loadPower ?? 0);
      }
    } catch {
      // ignore
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
    const trendData = trendResult.map((row: any) => ({
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

  private buildStationDeviceWhere(stationId: number, user: CurrentUser): Record<string, any> {
    if (user.role === Role.SUPER_ADMIN) return { station_id: stationId };
    if (user.role === Role.AGENT) return { station_id: stationId };
    if (user.role === Role.END_USER) return { station_id: stationId, user_id: user.id };
    if (user.role === Role.INSTALLER) return { station_id: stationId };
    return { station_id: stationId };
  }

  private mapAlarmLevel(level: number): string {
    switch (level) {
      case 1: return 'critical';
      case 2: return 'major';
      case 3: return 'minor';
      default: return 'warning';
    }
  }
}
