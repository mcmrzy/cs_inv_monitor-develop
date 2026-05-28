import { Repository } from 'typeorm';
import { Device } from '../../entities/device.entity';
import { DeviceTelemetry } from '../../entities/device-telemetry.entity';
import { DeviceUnbindRequest } from '../../entities/device-unbind-request.entity';
import { DeviceLifecycle } from '../../entities/device-lifecycle.entity';
import { Station } from '../../entities/station.entity';
import { CreateDeviceDto, UpdateDeviceDto, QueryDeviceDto } from './dto/create-device.dto';
import { CommandExecutionService } from './command-execution.service';
export declare class DeviceService {
    private readonly deviceRepo;
    private readonly telemetryRepo;
    private readonly unbindRequestRepo;
    private readonly lifecycleRepo;
    private readonly stationRepo;
    private readonly commandExecutionService;
    constructor(deviceRepo: Repository<Device>, telemetryRepo: Repository<DeviceTelemetry>, unbindRequestRepo: Repository<DeviceUnbindRequest>, lifecycleRepo: Repository<DeviceLifecycle>, stationRepo: Repository<Station>, commandExecutionService: CommandExecutionService);
    private checkDeviceAccess;
    findAll(query: QueryDeviceDto, currentUser: any): Promise<{
        items: Device[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    findBySn(sn: string, currentUser: any): Promise<Device>;
    create(dto: CreateDeviceDto, currentUser: any): Promise<Device>;
    update(sn: string, dto: UpdateDeviceDto, currentUser: any): Promise<Device>;
    delete(sn: string): Promise<void>;
    unbind(sn: string, currentUser: any): Promise<Device>;
    requestUnbind(sn: string, userId: number, reason: string): Promise<DeviceUnbindRequest>;
    approveUnbind(requestId: number, reviewerId: number, comment: string): Promise<DeviceUnbindRequest>;
    rejectUnbind(requestId: number, reviewerId: number, comment: string): Promise<DeviceUnbindRequest>;
    getUnbindRequests(query: {
        status?: string;
        page?: number;
        pageSize?: number;
    }): Promise<{
        items: DeviceUnbindRequest[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    recordLifecycleEvent(sn: string, eventType: string, description: string, userId: number, metadata?: any): Promise<DeviceLifecycle>;
    getLifecycleHistory(sn: string, page?: number, pageSize?: number): Promise<{
        items: DeviceLifecycle[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getTelemetry(sn: string, query: {
        startTime?: string;
        endTime?: string;
        limit?: number;
    }, currentUser: any): Promise<any[]>;
    getRealtimeData(sn: string, currentUser: any): Promise<any>;
    getCommandTemplates(sn: string): import("./command-execution.service").CommandTemplate[];
    executeCommand(sn: string, command: string, params: any, userId: number, ipAddress?: string): Promise<{
        success: boolean;
        message: string;
        reqId: string;
        status: string;
    }>;
    getCommandHistory(sn: string, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/command-log.entity").CommandLog[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    exportTelemetryCSV(sn: string, startTime: string, endTime: string, fields: string, currentUser: any): Promise<string>;
    exportTelemetryExcel(sn: string, startTime: string, endTime: string, currentUser: any): Promise<Buffer>;
}
