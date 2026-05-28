import { ParallelService } from './parallel.service';
import { CreateParallelGroupDto, UpdateParallelGroupDto, QueryParallelGroupDto, SyncParamsDto } from './dto/create-parallel-group.dto';
export declare class ParallelController {
    private readonly parallelService;
    constructor(parallelService: ParallelService);
    findAll(query: QueryParallelGroupDto): Promise<{
        items: any[];
        total: number;
        page: number;
        pageSize: number;
    }>;
    getDetail(id: number): Promise<any>;
    create(dto: CreateParallelGroupDto, user: any): Promise<import("../../entities/parallel-config.entity").ParallelConfig>;
    update(id: number, dto: UpdateParallelGroupDto): Promise<import("../../entities/parallel-config.entity").ParallelConfig>;
    delete(id: number): Promise<void>;
    syncParams(id: number, params: SyncParamsDto): Promise<{
        message: string;
        devices: string[];
    }>;
    getStatus(id: number): Promise<import("../../entities/parallel-status.entity").ParallelStatus[]>;
    getAlerts(id: number, page?: number, pageSize?: number): Promise<{
        items: import("../../entities/alert.entity").Alert[];
        total: number;
        page: number;
        pageSize: number;
    }>;
}
