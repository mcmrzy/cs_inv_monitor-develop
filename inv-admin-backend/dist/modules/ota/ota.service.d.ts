import { Repository } from 'typeorm';
import { Firmware } from '../../entities/firmware.entity';
import { OtaTask } from '../../entities/ota-task.entity';
import { OtaTaskDevice } from '../../entities/ota-task-device.entity';
import { Device } from '../../entities/device.entity';
import { CreateFirmwareDto } from './dto/create-firmware.dto';
import { CreateOtaTaskDto } from './dto/create-ota-task.dto';
import { QueryOtaTaskDto } from './dto/query-ota-task.dto';
export declare class OtaService {
    private readonly firmwareRepo;
    private readonly otaTaskRepo;
    private readonly otaTaskDeviceRepo;
    private readonly deviceRepo;
    constructor(firmwareRepo: Repository<Firmware>, otaTaskRepo: Repository<OtaTask>, otaTaskDeviceRepo: Repository<OtaTaskDevice>, deviceRepo: Repository<Device>);
    uploadFirmware(file: Express.Multer.File, dto: CreateFirmwareDto, userId: number): Promise<Firmware>;
    getFirmwares(query: {
        model?: string;
        page?: number;
        pageSize?: number;
    }): Promise<{
        items: Firmware[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    deleteFirmware(id: number): Promise<void>;
    createTask(dto: CreateOtaTaskDto, userId: number): Promise<OtaTask>;
    getTasks(query: QueryOtaTaskDto, currentUser: any): Promise<{
        items: OtaTask[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getTaskDetail(taskId: string): Promise<OtaTask>;
    getTaskDevices(taskId: string, query: {
        page?: number;
        pageSize?: number;
    }): Promise<{
        items: OtaTaskDevice[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    executeTask(taskId: string): Promise<OtaTask>;
    private runExecutionStrategy;
    private pushAllAtOnce;
    private pushInBatches;
    rollbackTask(taskId: string): Promise<OtaTask>;
    retryDevice(taskId: string, deviceSn: string): Promise<OtaTaskDevice>;
    updateDeviceProgress(taskId: string, deviceSn: string, statusStr: string, progress: number): Promise<OtaTaskDevice>;
    private updateTaskCounts;
    cancelTask(taskId: string): Promise<OtaTask>;
}
