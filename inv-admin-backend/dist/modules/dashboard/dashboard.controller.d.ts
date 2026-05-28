import { DashboardService } from './dashboard.service';
import { Role } from '../../common/enums/role.enum';
export declare class DashboardController {
    private readonly dashboardService;
    constructor(dashboardService: DashboardService);
    getStatistics(user: {
        id: number;
        role: Role;
    }): Promise<{
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
        recentAlerts: import("../../entities/alert.entity").Alert[];
    }>;
    getTrend(type: string | undefined, user: {
        id: number;
        role: Role;
    }): Promise<{
        type: "year" | "day" | "month";
        data: any;
    }>;
    getDeviceDistribution(user: {
        id: number;
        role: Role;
    }): Promise<{
        name: string;
        value: number;
        status: number;
    }[]>;
    getBigScreen(user: {
        id: number;
        role: Role;
    }): Promise<{
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
    compareDevices(devices: string, metric: string, user: {
        id: number;
        role: Role;
    }, startTime?: string, endTime?: string): Promise<{
        devices: string[];
        metric: string;
        series: {
            time: string;
        }[];
    }>;
}
