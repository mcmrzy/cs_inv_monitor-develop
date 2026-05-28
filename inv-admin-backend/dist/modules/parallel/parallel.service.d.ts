import { Repository } from 'typeorm';
import { ParallelConfig } from '../../entities/parallel-config.entity';
import { ParallelStatus } from '../../entities/parallel-status.entity';
import { Device } from '../../entities/device.entity';
import { Alert } from '../../entities/alert.entity';
import { CreateParallelGroupDto, UpdateParallelGroupDto, QueryParallelGroupDto, SyncParamsDto } from './dto/create-parallel-group.dto';
export declare class ParallelService {
    private readonly configRepo;
    private readonly statusRepo;
    private readonly deviceRepo;
    private readonly alertRepo;
    constructor(configRepo: Repository<ParallelConfig>, statusRepo: Repository<ParallelStatus>, deviceRepo: Repository<Device>, alertRepo: Repository<Alert>);
    createGroup(dto: CreateParallelGroupDto, userId: number): Promise<ParallelConfig>;
    getAllGroups(query: QueryParallelGroupDto): Promise<{
        items: any[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getGroupDetail(id: number): Promise<any>;
    updateGroup(id: number, dto: UpdateParallelGroupDto): Promise<ParallelConfig>;
    deleteGroup(id: number): Promise<void>;
    syncParams(groupId: number, params: SyncParamsDto): Promise<{
        message: string;
        devices: string[];
    }>;
    getGroupStatus(id: number): Promise<ParallelStatus[]>;
    checkCirculatingCurrent(groupId: number): Promise<{
        hasAlert: boolean;
        details: any[];
    }>;
    getAlertHistory(groupId: number, query?: {
        page?: number;
        pageSize?: number;
    }): Promise<{
        items: Alert[];
        total: number;
        page: number;
        pageSize: number;
    }>;
}
