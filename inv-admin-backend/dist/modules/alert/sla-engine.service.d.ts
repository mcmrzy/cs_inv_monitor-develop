import { Repository } from 'typeorm';
import { WorkOrder } from '../../entities/work-order.entity';
export declare class SlaEngineService {
    private workOrderRepo;
    private readonly logger;
    constructor(workOrderRepo: Repository<WorkOrder>);
    calculateDeadline(priority: number): Date;
    checkOverdue(): Promise<number>;
    onSlaBreach(workOrder: WorkOrder): void;
}
