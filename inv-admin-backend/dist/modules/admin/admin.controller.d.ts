import { AdminService } from './admin.service';
import { PermissionService } from './permission.service';
export declare class AdminController {
    private readonly adminService;
    private readonly permissionService;
    constructor(adminService: AdminService, permissionService: PermissionService);
    getAuditLogs(query: any): Promise<{
        list: import("../../entities/audit-log.entity").AuditLog[];
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
    createTenant(body: any): Promise<{
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
    updateTenant(id: number, body: any): Promise<{
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
    updateSystemConfig(body: any): Promise<{
        success: boolean;
    }>;
    getAllPermissions(): Promise<Record<number, Record<string, string[]>>>;
    getRolePermissions(role: number): Promise<{
        resource: string;
        action: string;
        is_allowed: boolean;
    }[]>;
    updateRolePermissions(role: number, body: {
        permissions: {
            resource: string;
            action: string;
            is_allowed: boolean;
        }[];
    }): Promise<{
        success: boolean;
    }>;
    togglePermission(role: number, body: {
        resource: string;
        action: string;
        is_allowed: boolean;
    }): Promise<import("../../entities/permission.entity").RolePermission>;
}
