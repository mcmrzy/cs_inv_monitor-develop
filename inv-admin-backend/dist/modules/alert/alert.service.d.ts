import { Repository } from 'typeorm';
import { Alert } from '../../entities/alert.entity';
import { WorkOrder, WorkOrderStatus } from '../../entities/work-order.entity';
import { Device } from '../../entities/device.entity';
import { Role } from '../../common/enums/role.enum';
import { QueryAlertDto } from './dto/query-alert.dto';
import { CreateWorkOrderDto } from './dto/create-work-order.dto';
import { SlaEngineService } from './sla-engine.service';
import { WorkOrderTemplateService } from './work-order-template.service';
interface CurrentUser {
    id: number;
    role: Role;
}
export declare class AlertService {
    private alertRepo;
    private workOrderRepo;
    private deviceRepo;
    private readonly slaEngineService;
    private readonly templateService;
    private readonly logger;
    constructor(alertRepo: Repository<Alert>, workOrderRepo: Repository<WorkOrder>, deviceRepo: Repository<Device>, slaEngineService: SlaEngineService, templateService: WorkOrderTemplateService);
    private applyRoleFilter;
    findAll(queryDto: QueryAlertDto, currentUser: CurrentUser): Promise<{
        list: Alert[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    acknowledge(id: number, userId: number): Promise<Alert>;
    ignore(id: number, userId: number): Promise<Alert>;
    getStats(currentUser: CurrentUser): Promise<{
        totalUnhandled: number;
        byLevel: {
            level1: number;
            level2: number;
            level3: number;
        };
        todayCount: number;
    }>;
    createWorkOrder(dto: CreateWorkOrderDto, userId: number): Promise<WorkOrder>;
    getWorkOrders(query: any, currentUser: CurrentUser): Promise<{
        list: WorkOrder[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    getWorkOrder(id: string): Promise<WorkOrder>;
    updateWorkOrderStatus(id: string, status: WorkOrderStatus, resolution?: string): Promise<WorkOrder>;
    assignWorkOrder(id: string, assignedTo: number): Promise<WorkOrder>;
    escalateWorkOrder(id: string): Promise<WorkOrder>;
    getTemplates(): {
        templateId: string;
        title: string;
        description: string;
        priority: number;
        defaultFields: string[];
        estimatedHours: number;
    }[];
}
export {};
