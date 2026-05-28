import { OtaService } from './ota.service';
import { CreateFirmwareDto } from './dto/create-firmware.dto';
import { CreateOtaTaskDto } from './dto/create-ota-task.dto';
import { QueryOtaTaskDto } from './dto/query-ota-task.dto';
export declare class OtaController {
    private readonly otaService;
    constructor(otaService: OtaService);
    uploadFirmware(file: Express.Multer.File, dto: CreateFirmwareDto, currentUser: any): Promise<import("../../entities/firmware.entity").Firmware>;
    getFirmwares(model?: string, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/firmware.entity").Firmware[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    deleteFirmware(id: number): Promise<void>;
    createTask(dto: CreateOtaTaskDto, currentUser: any): Promise<import("../../entities/ota-task.entity").OtaTask>;
    getTasks(query: QueryOtaTaskDto, currentUser: any): Promise<{
        items: import("../../entities/ota-task.entity").OtaTask[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getTaskDetail(id: string): Promise<import("../../entities/ota-task.entity").OtaTask>;
    getTaskDevices(id: string, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/ota-task-device.entity").OtaTaskDevice[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    executeTask(id: string): Promise<import("../../entities/ota-task.entity").OtaTask>;
    cancelTask(id: string): Promise<import("../../entities/ota-task.entity").OtaTask>;
    retryDevice(id: string, deviceSn: string): Promise<import("../../entities/ota-task-device.entity").OtaTaskDevice>;
    rollbackTask(id: string): Promise<import("../../entities/ota-task.entity").OtaTask>;
}
