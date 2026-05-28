import { Response } from 'express';
import { DeviceService } from './device.service';
import { ExcelImportService } from './excel-import.service';
import { CreateDeviceDto, UpdateDeviceDto, QueryDeviceDto } from './dto/create-device.dto';
export declare class DeviceController {
    private readonly deviceService;
    private readonly excelImportService;
    constructor(deviceService: DeviceService, excelImportService: ExcelImportService);
    findAll(query: QueryDeviceDto, currentUser: any): Promise<{
        items: import("../../entities/device.entity").Device[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getUnbindRequests(status?: string, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/device-unbind-request.entity").DeviceUnbindRequest[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    findBySn(sn: string, currentUser: any): Promise<import("../../entities/device.entity").Device>;
    getLifecycleHistory(sn: string, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/device-lifecycle.entity").DeviceLifecycle[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    create(dto: CreateDeviceDto, currentUser: any): Promise<import("../../entities/device.entity").Device>;
    importExcel(file: Express.Multer.File, currentUser: any, installerId?: number): Promise<import("./excel-import.service").ExcelImportResult>;
    requestUnbind(sn: string, body: {
        reason: string;
    }, currentUser: any): Promise<import("../../entities/device-unbind-request.entity").DeviceUnbindRequest>;
    approveUnbind(id: number, body: {
        comment?: string;
    }, currentUser: any): Promise<import("../../entities/device-unbind-request.entity").DeviceUnbindRequest>;
    rejectUnbind(id: number, body: {
        comment?: string;
    }, currentUser: any): Promise<import("../../entities/device-unbind-request.entity").DeviceUnbindRequest>;
    update(sn: string, dto: UpdateDeviceDto, currentUser: any): Promise<import("../../entities/device.entity").Device>;
    delete(sn: string): Promise<void>;
    unbind(sn: string, currentUser: any): Promise<import("../../entities/device.entity").Device>;
    getTelemetry(sn: string, startTime?: string, endTime?: string, limit?: number, currentUser?: any): Promise<any[]>;
    getRealtimeData(sn: string, currentUser: any): Promise<any>;
    getCommandTemplates(sn: string): import("./command-execution.service").CommandTemplate[];
    sendConfig(sn: string, body: {
        command: string;
        params: any;
    }, currentUser: any, req: any): Promise<{
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
    exportTelemetryCSV(sn: string, startTime?: string, endTime?: string, fields?: string, currentUser?: any, res?: Response): Promise<void>;
    exportTelemetryExcel(sn: string, startTime?: string, endTime?: string, currentUser?: any, res?: Response): Promise<void>;
}
