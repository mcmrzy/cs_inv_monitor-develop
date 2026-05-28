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
var SlaEngineService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SlaEngineService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const work_order_entity_1 = require("../../entities/work-order.entity");
let SlaEngineService = SlaEngineService_1 = class SlaEngineService {
    constructor(workOrderRepo) {
        this.workOrderRepo = workOrderRepo;
        this.logger = new common_1.Logger(SlaEngineService_1.name);
    }
    calculateDeadline(priority) {
        const now = new Date();
        switch (priority) {
            case work_order_entity_1.WorkOrderPriority.LOW:
                return new Date(now.getTime() + 48 * 60 * 60 * 1000);
            case work_order_entity_1.WorkOrderPriority.MEDIUM:
                return new Date(now.getTime() + 24 * 60 * 60 * 1000);
            case work_order_entity_1.WorkOrderPriority.HIGH:
                return new Date(now.getTime() + 8 * 60 * 60 * 1000);
            case work_order_entity_1.WorkOrderPriority.URGENT:
                return new Date(now.getTime() + 2 * 60 * 60 * 1000);
            default:
                return new Date(now.getTime() + 48 * 60 * 60 * 1000);
        }
    }
    async checkOverdue() {
        const now = new Date();
        const overdueWorkOrders = await this.workOrderRepo
            .createQueryBuilder('wo')
            .where('wo.status IN (:...statuses)', { statuses: [work_order_entity_1.WorkOrderStatus.OPEN, work_order_entity_1.WorkOrderStatus.IN_PROGRESS] })
            .andWhere('wo.sla_deadline IS NOT NULL')
            .andWhere('wo.sla_deadline < :now', { now })
            .getMany();
        let escalatedCount = 0;
        for (const wo of overdueWorkOrders) {
            wo.sla_overdue_count = (wo.sla_overdue_count || 0) + 1;
            this.logger.warn(`SLA breach: work order ${wo.id}, overdue count: ${wo.sla_overdue_count}, current priority: ${wo.priority}`);
            const overdueHours = (now.getTime() - wo.sla_deadline.getTime()) / (1000 * 60 * 60);
            if (overdueHours > 24 && wo.priority < work_order_entity_1.WorkOrderPriority.URGENT) {
                wo.priority = Math.min(wo.priority + 1, work_order_entity_1.WorkOrderPriority.URGENT);
                this.logger.warn(`Work order ${wo.id} auto-escalated to priority ${wo.priority} due to ${overdueHours.toFixed(1)}h overdue`);
                escalatedCount++;
            }
        }
        if (overdueWorkOrders.length > 0) {
            await this.workOrderRepo.save(overdueWorkOrders);
            this.logger.log(`SLA check complete: ${overdueWorkOrders.length} overdue, ${escalatedCount} escalated`);
        }
        return overdueWorkOrders.length;
    }
    onSlaBreach(workOrder) {
        this.logger.error(`SLA BREACH: Work order "${workOrder.title}" (${workOrder.id}) is overdue. ` +
            `Priority: ${workOrder.priority}, Assignee: ${workOrder.assigned_to}, ` +
            `Created: ${workOrder.created_at}, Deadline: ${workOrder.sla_deadline}`);
    }
};
exports.SlaEngineService = SlaEngineService;
exports.SlaEngineService = SlaEngineService = SlaEngineService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(work_order_entity_1.WorkOrder)),
    __metadata("design:paramtypes", [typeorm_2.Repository])
], SlaEngineService);
//# sourceMappingURL=sla-engine.service.js.map