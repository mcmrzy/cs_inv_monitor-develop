import { Repository } from 'typeorm';
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
export declare class DashboardService {
    private deviceRepo;
    private stationRepo;
    private userRepo;
    private alertRepo;
    private telemetryRepo;
    private otaTaskRepo;
    private readonly logger;
    constructor(deviceRepo: Repository<Device>, stationRepo: Repository<Station>, userRepo: Repository<User>, alertRepo: Repository<Alert>, telemetryRepo: Repository<DeviceTelemetry>, otaTaskRepo: Repository<OtaTask>);
    private applyRoleFilterForDevice;
    private applyRoleFilterForAlert;
    private applyRoleFilterForTelemetry;
    private buildTelemetryRoleClause;
    getStatistics(currentUser: CurrentUser): Promise<{
        deviceStats: {
            total: number;
            online: number;
            offline: number;
            fault: number;
        };
        stationStats: {
            total: number;
        };
        userStats: {
            total: number;
        };
        alertStats: {
            total: number;
            unhandled: number;
            critical: number;
            warning: number;
            info: number;
        };
        todayEnergy: number;
        totalEnergy: number;
        onlineRate: number;
        recentAlerts: Alert[];
    }>;
    getTrend(type: 'day' | 'month' | 'year', currentUser: CurrentUser): Promise<{
        type: "year" | "day" | "month";
        data: any;
    }>;
    getDeviceStatusDistribution(currentUser: CurrentUser): Promise<{
        name: string;
        value: number;
        status: number;
    }[]>;
    compareDevices(devices: string, metric: string, startTime: string, endTime: string, currentUser: CurrentUser): Promise<{
        devices: string[];
        metric: string;
        series: {
            time: string;
        }[];
    }>;
    getBigScreen(currentUser: CurrentUser): Promise<{
        totals: {
            devices: number;
            online: number;
            offline: number;
            fault: number;
        };
        energy: {
            today: number;
            total: number;
            todayIncome: number;
        };
        carbonReduction: {
            co2: number;
            trees: number;
        };
        onlineRate: number;
        stations: {
            id: number;
            name: string;
            lat: number;
            lng: number;
            deviceCount: number;
            onlineCount: number;
            power: number;
        }[];
        recentAlerts: {
            id: number;
            deviceSn: string;
            alarmLevel: string;
            faultCode: string;
            faultMessage: string;
            status: string;
            occurredAt: string;
        }[];
        powerFlow: {
            pv: number;
            grid: number;
            battery: number;
            load: number;
        };
        trend: any;
        otaTasks: {
            id: string;
            name: string;
            status: import("../../entities/ota-task.entity").OtaTaskStatus;
            totalDevices: number;
            successCount: number;
            failedCount: number;
            progress: number;
            createdAt: string;
        }[];
        systemHealth: {
            uptime: string;
            db: boolean;
            redis: boolean;
            mqtt: boolean;
        };
    }>;
    private buildStationDeviceWhere;
    private mapAlarmLevel;
}
export {};
