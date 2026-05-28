import { AlertRuleService } from './alert-rule.service';
import { CreateAlertRuleDto } from './dto/create-alert-rule.dto';
import { Role } from '../../common/enums/role.enum';
export declare class AlertRuleController {
    private readonly alertRuleService;
    constructor(alertRuleService: AlertRuleService);
    findAll(page?: number, pageSize?: number, isActive?: string, deviceModel?: string): Promise<{
        list: import("../../entities/alert-rule.entity").AlertRule[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    create(dto: CreateAlertRuleDto, user: {
        id: number;
        role: Role;
    }): Promise<import("../../entities/alert-rule.entity").AlertRule>;
    update(id: number, dto: CreateAlertRuleDto): Promise<import("../../entities/alert-rule.entity").AlertRule>;
    delete(id: number): Promise<{
        message: string;
    }>;
}
