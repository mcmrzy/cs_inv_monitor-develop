"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var AlertRuleService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertRuleService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const alert_rule_entity_1 = require("../../entities/alert-rule.entity");
const alert_entity_1 = require("../../entities/alert.entity");
const device_entity_1 = require("../../entities/device.entity");
const alert_notification_entity_1 = require("../../entities/alert-notification.entity");
let AlertRuleService = AlertRuleService_1 = class AlertRuleService {
    constructor(alertRuleRepo, alertRepo, deviceRepo, notificationRepo) {
        this.alertRuleRepo = alertRuleRepo;
        this.alertRepo = alertRepo;
        this.deviceRepo = deviceRepo;
        this.notificationRepo = notificationRepo;
        this.logger = new common_1.Logger(AlertRuleService_1.name);
    }
    async create(dto, currentUser) {
        const rule = this.alertRuleRepo.create({
            ...dto,
            created_by: currentUser.id,
        });
        return this.alertRuleRepo.save(rule);
    }
    async findAll(query) {
        const { page = 1, pageSize = 20, isActive, deviceModel } = query;
        const qb = this.alertRuleRepo.createQueryBuilder('rule');
        if (isActive !== undefined && isActive !== null) {
            qb.andWhere('rule.is_active = :isActive', { isActive: String(isActive) === 'true' });
        }
        if (deviceModel) {
            qb.andWhere('(rule.device_model = :model OR rule.device_model IS NULL)', { model: deviceModel });
        }
        qb.orderBy('rule.created_at', 'DESC')
            .skip((page - 1) * pageSize)
            .take(pageSize);
        const [list, total] = await qb.getManyAndCount();
        return {
            list,
            total,
            page: Number(page),
            pageSize: Number(pageSize),
            totalPages: Math.ceil(total / Number(pageSize)),
        };
    }
    async update(id, dto) {
        const rule = await this.alertRuleRepo.findOne({ where: { id } });
        if (!rule) {
            throw new common_1.NotFoundException('告警规则不存在');
        }
        Object.assign(rule, dto);
        return this.alertRuleRepo.save(rule);
    }
    async delete(id) {
        const rule = await this.alertRuleRepo.findOne({ where: { id } });
        if (!rule) {
            throw new common_1.NotFoundException('告警规则不存在');
        }
        rule.is_active = false;
        await this.alertRuleRepo.save(rule);
    }
    evaluateRule(rule, telemetry) {
        const fieldPath = rule.field_name;
        const value = this.resolveNestedPath(fieldPath, telemetry);
        if (value === undefined || value === null) {
            return false;
        }
        const threshold = Number(rule.threshold_value);
        const numValue = Number(value);
        if (isNaN(numValue)) {
            const strValue = String(value);
            switch (rule.operator) {
                case 'eq': return strValue === String(threshold);
                case 'neq': return strValue !== String(threshold);
                default: return false;
            }
        }
        switch (rule.operator) {
            case 'gt': return numValue > threshold;
            case 'lt': return numValue < threshold;
            case 'eq': return numValue === threshold;
            case 'gte': return numValue >= threshold;
            case 'lte': return numValue <= threshold;
            case 'neq': return numValue !== threshold;
            default:
                this.logger.warn(`Unknown operator: ${rule.operator}`);
                return false;
        }
    }
    async processTelemetry(sn, telemetry) {
        const device = await this.deviceRepo.findOne({ where: { sn } });
        if (!device) {
            this.logger.warn(`Device not found for SN: ${sn}`);
            return null;
        }
        const rules = await this.getApplicableRules(device.model);
        for (const rule of rules) {
            const triggered = this.evaluateRule(rule, telemetry);
            if (triggered) {
                if (!this.checkCooldown(rule, sn)) {
                    this.logger.debug(`Rule ${rule.id} for SN ${sn} is in cooldown, skipping`);
                    continue;
                }
                this.logger.log(`Alert triggered: rule=${rule.name}, sn=${sn}, field=${rule.field_name}, ` +
                    `operator=${rule.operator}, threshold=${rule.threshold_value}`);
                return this.createAlertFromRule(rule, sn, device.user_id, device.station_id, telemetry);
            }
        }
        return null;
    }
    async getApplicableRules(deviceModel) {
        return this.alertRuleRepo.find({
            where: [
                { is_active: true, device_model: deviceModel },
                { is_active: true, device_model: null },
            ],
        });
    }
    resolveNestedPath(path, obj) {
        if (!obj || typeof obj !== 'object') {
            return undefined;
        }
        const keys = path.split('.');
        let current = obj;
        for (const key of keys) {
            if (current === null || current === undefined || typeof current !== 'object') {
                return undefined;
            }
            current = current[key] !== undefined ? current[key] : current[`data`]?.[key];
        }
        return current;
    }
    checkCooldown(rule, sn) {
        const cooldownEnd = new Date(Date.now() - rule.cooldown_minutes * 60 * 1000);
        return true;
    }
    async createAlertFromRule(rule, sn, userId, stationId, telemetry) {
        const alert = this.alertRepo.create({
            device_sn: sn,
            user_id: userId,
            station_id: stationId,
            alarm_level: rule.alarm_level,
            fault_code: rule.fault_code,
            fault_message: rule.fault_message,
            fault_detail: JSON.stringify({
                rule_id: rule.id,
                rule_name: rule.name,
                field_name: rule.field_name,
                operator: rule.operator,
                threshold_value: rule.threshold_value,
                actual_value: this.resolveNestedPath(rule.field_name, telemetry),
            }),
            status: 0,
            occurred_at: new Date(),
        });
        return this.alertRepo.save(alert);
    }
};
exports.AlertRuleService = AlertRuleService;
exports.AlertRuleService = AlertRuleService = AlertRuleService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(alert_rule_entity_1.AlertRule)),
    __param(1, (0, typeorm_1.InjectRepository)(alert_entity_1.Alert)),
    __param(2, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(3, (0, typeorm_1.InjectRepository)(alert_notification_entity_1.AlertNotification)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository])
], AlertRuleService);
//# sourceMappingURL=alert-rule.service.js.map