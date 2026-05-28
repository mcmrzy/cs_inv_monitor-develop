import { OnModuleInit } from '@nestjs/common';
import { PermissionService } from './permission.service';
export declare class AdminModule implements OnModuleInit {
    private permissionService;
    constructor(permissionService: PermissionService);
    onModuleInit(): Promise<void>;
}
