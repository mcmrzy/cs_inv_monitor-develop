import { AlertService } from './alert.service';
import { QueryAlertDto } from './dto/query-alert.dto';
import { Role } from '../../common/enums/role.enum';
export declare class AlertController {
    private readonly alertService;
    constructor(alertService: AlertService);
    findAll(query: QueryAlertDto, user: {
        id: number;
        role: Role;
    }): Promise<{
        list: import("../../entities/alert.entity").Alert[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    acknowledge(id: number, user: {
        id: number;
        role: Role;
    }): Promise<import("../../entities/alert.entity").Alert>;
    ignore(id: number, user: {
        id: number;
        role: Role;
    }): Promise<import("../../entities/alert.entity").Alert>;
}
