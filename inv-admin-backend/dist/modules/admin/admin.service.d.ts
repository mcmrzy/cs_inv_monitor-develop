import { Repository } from 'typeorm';
import { AuditLog } from '../../entities/audit-log.entity';
import { User } from '../../entities/user.entity';
import { Device } from '../../entities/device.entity';
import { SystemConfig } from '../../entities/system-config.entity';
interface QueryAuditLogDto {
    page?: number;
    pageSize?: number;
    userId?: number;
    action?: string;
    startTime?: string;
    endTime?: string;
}
interface CreateTenantDto {
    phone: string;
    password: string;
    nickname?: string;
    email?: string;
    deviceLimit?: number;
    userLimit?: number;
}
interface UpdateTenantDto {
    deviceLimit?: number;
    userLimit?: number;
}
export declare class AdminService {
    private auditLogRepo;
    private userRepo;
    private deviceRepo;
    private systemConfigRepo;
    constructor(auditLogRepo: Repository<AuditLog>, userRepo: Repository<User>, deviceRepo: Repository<Device>, systemConfigRepo: Repository<SystemConfig>);
    getAuditLogs(query: QueryAuditLogDto): Promise<{
        list: AuditLog[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    getSystemHealth(): Promise<{
        uptime: string;
        memory: {
            used: string;
            total: string;
        };
        database: string;
        redis: string;
        version: string;
    }>;
    private getTenantConfig;
    private setTenantConfig;
    createTenant(dto: CreateTenantDto): Promise<{
        agent: {
            id: number;
            phone: string;
            nickname: string | null;
            email: string | null;
            status: number;
            deviceLimit: number;
            userLimit: number;
            createdAt: Date;
        };
        demoAccounts: {
            installer: {
                id: number;
                phone: string;
                nickname: string | null;
            };
            endUser: {
                id: number;
                phone: string;
                nickname: string | null;
            };
        };
    }>;
    getTenants(page?: number, pageSize?: number): Promise<{
        items: {
            id: number;
            phone: string;
            nickname: string | null;
            email: string | null;
            status: number;
            subUserCount: number;
            deviceCount: number;
            deviceLimit: number | null;
            userLimit: number | null;
            createdAt: Date;
            lastLoginAt: Date;
        }[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    updateTenant(id: number, dto: UpdateTenantDto): Promise<{
        id: number;
        nickname: string | null;
        deviceLimit: number | null;
        userLimit: number | null;
    }>;
    toggleTenant(id: number): Promise<{
        id: number;
        nickname: string | null;
        status: number;
        enabled: boolean;
    }>;
    getSystemConfig(): Promise<any>;
    updateSystemConfig(data: Record<string, unknown>): Promise<{
        success: boolean;
    }>;
}
export {};
