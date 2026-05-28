import { Repository } from 'typeorm';
import { CommandLog } from '../../entities/command-log.entity';
import { DeviceServerProxyService } from './device-server-proxy.service';
interface CommandParam {
    name: string;
    label: string;
    type: 'number' | 'string' | 'boolean' | 'select';
    required: boolean;
    options?: {
        label: string;
        value: any;
    }[];
    min?: number;
    max?: number;
    defaultValue?: any;
    unit?: string;
}
export interface CommandTemplate {
    name: string;
    label: string;
    description: string;
    category: 'power' | 'battery' | 'grid' | 'system' | 'ota';
    params: CommandParam[];
    requiresConfirm: boolean;
    confirmationMessage?: string;
}
export declare const COMMAND_TEMPLATES: CommandTemplate[];
export declare class CommandExecutionService {
    private readonly commandLogRepo;
    private readonly proxyService;
    private readonly logger;
    constructor(commandLogRepo: Repository<CommandLog>, proxyService: DeviceServerProxyService);
    getCommandTemplates(sn?: string): CommandTemplate[];
    executeCommand(sn: string, commandName: string, params: Record<string, any>, userId: number, ipAddress?: string): Promise<{
        success: boolean;
        message: string;
        reqId: string;
        status: string;
    }>;
    getCommandHistory(sn: string, page?: number, pageSize?: number): Promise<{
        items: CommandLog[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    private validateParams;
}
export {};
