import { AlertService } from './alert.service';
import { Role } from '../../common/enums/role.enum';
import { CreateWorkOrderDto } from './dto/create-work-order.dto';
import { WorkOrder, WorkOrderStatus } from '../../entities/work-order.entity';
import { Repository } from 'typeorm';
export declare class WorkOrderController {
    private readonly alertService;
    private workOrderRepo;
    constructor(alertService: AlertService, workOrderRepo: Repository<WorkOrder>);
    getTemplates(): Promise<{
        templateId: string;
        title: string;
        description: string;
        priority: number;
        defaultFields: string[];
        estimatedHours: number;
    }[]>;
    getWorkOrders(query: any, user: {
        id: number;
        role: Role;
    }): Promise<{
        list: WorkOrder[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    createWorkOrder(dto: CreateWorkOrderDto, user: {
        id: number;
        role: Role;
    }): Promise<WorkOrder>;
    getWorkOrder(id: string): Promise<WorkOrder>;
    updateWorkOrder(id: string, body: {
        assignedTo?: number;
    }): Promise<WorkOrder | {
        message: string;
    }>;
    updateWorkOrderStatus(id: string, body: {
        status: WorkOrderStatus;
        resolution?: string;
    }): Promise<WorkOrder>;
    escalateWorkOrder(id: string): Promise<WorkOrder>;
    uploadAttachments(id: string, files: Express.Multer.File[]): Promise<{
        message: string;
        attachments?: undefined;
    } | {
        message: string;
        attachments: {
            name: string;
            url: string;
            type: string;
            uploadedAt: string;
        }[];
    }>;
}
