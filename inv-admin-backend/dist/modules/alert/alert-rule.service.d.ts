import { Repository } from 'typeorm';
import { AlertRule } from '../../entities/alert-rule.entity';
import { Alert } from '../../entities/alert.entity';
import { Device } from '../../entities/device.entity';
import { AlertNotification } from '../../entities/alert-notification.entity';
import { CreateAlertRuleDto } from './dto/create-alert-rule.dto';
interface CurrentUser {
    id: number;
    role: number;
}
export declare class AlertRuleService {
    private readonly alertRuleRepo;
    private readonly alertRepo;
    private readonly deviceRepo;
    private readonly notificationRepo;
    private readonly logger;
    constructor(alertRuleRepo: Repository<AlertRule>, alertRepo: Repository<Alert>, deviceRepo: Repository<Device>, notificationRepo: Repository<AlertNotification>);
    create(dto: CreateAlertRuleDto, currentUser: CurrentUser): Promise<AlertRule>;
    findAll(query: {
        page?: number;
        pageSize?: number;
        isActive?: boolean;
        deviceModel?: string;
    }): Promise<{
        list: AlertRule[];
        total: number;
        page: number;
        pageSize: number;
        totalPages: number;
    }>;
    update(id: number, dto: CreateAlertRuleDto): Promise<AlertRule>;
    delete(id: number): Promise<void>;
    evaluateRule(rule: AlertRule, telemetry: any): boolean;
    processTelemetry(sn: string, telemetry: any): Promise<Alert | null>;
    getApplicableRules(deviceModel: string): Promise<AlertRule[]>;
    private resolveNestedPath;
    private checkCooldown;
    private createAlertFromRule;
}
export {};
