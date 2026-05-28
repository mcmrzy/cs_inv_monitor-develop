import { Repository } from 'typeorm';
import { RolePermission } from '../../entities/permission.entity';
export declare class PermissionService {
    private repo;
    constructor(repo: Repository<RolePermission>);
    seedDefaults(): Promise<void>;
    getRolePermissions(role: number): Promise<{
        resource: string;
        action: string;
        is_allowed: boolean;
    }[]>;
    getAllPermissionsConfig(): Promise<Record<number, Record<string, string[]>>>;
    hasPermission(role: number, resource: string, action: string): Promise<boolean>;
    setPermission(role: number, resource: string, action: string, isAllowed: boolean): Promise<RolePermission>;
    batchUpdatePermissions(role: number, permissions: {
        resource: string;
        action: string;
        is_allowed: boolean;
    }[]): Promise<void>;
}
