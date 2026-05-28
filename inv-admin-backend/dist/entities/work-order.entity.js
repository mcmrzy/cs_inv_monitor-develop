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
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorkOrder = exports.WorkOrderStatus = exports.WorkOrderPriority = void 0;
const typeorm_1 = require("typeorm");
var WorkOrderPriority;
(function (WorkOrderPriority) {
    WorkOrderPriority[WorkOrderPriority["LOW"] = 1] = "LOW";
    WorkOrderPriority[WorkOrderPriority["MEDIUM"] = 2] = "MEDIUM";
    WorkOrderPriority[WorkOrderPriority["HIGH"] = 3] = "HIGH";
    WorkOrderPriority[WorkOrderPriority["URGENT"] = 4] = "URGENT";
})(WorkOrderPriority || (exports.WorkOrderPriority = WorkOrderPriority = {}));
var WorkOrderStatus;
(function (WorkOrderStatus) {
    WorkOrderStatus["OPEN"] = "open";
    WorkOrderStatus["IN_PROGRESS"] = "in_progress";
    WorkOrderStatus["RESOLVED"] = "resolved";
    WorkOrderStatus["CLOSED"] = "closed";
})(WorkOrderStatus || (exports.WorkOrderStatus = WorkOrderStatus = {}));
let WorkOrder = class WorkOrder {
};
exports.WorkOrder = WorkOrder;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)('uuid'),
    __metadata("design:type", String)
], WorkOrder.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 200 }),
    __metadata("design:type", String)
], WorkOrder.prototype, "title", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], WorkOrder.prototype, "description", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'device_sn' }),
    __metadata("design:type", String)
], WorkOrder.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'station_id' }),
    __metadata("design:type", Number)
], WorkOrder.prototype, "station_id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', name: 'created_by' }),
    __metadata("design:type", Number)
], WorkOrder.prototype, "created_by", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'assigned_to' }),
    __metadata("design:type", Number)
], WorkOrder.prototype, "assigned_to", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'smallint', default: WorkOrderPriority.LOW }),
    __metadata("design:type", Number)
], WorkOrder.prototype, "priority", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'enum', enum: WorkOrderStatus, default: WorkOrderStatus.OPEN }),
    __metadata("design:type", String)
], WorkOrder.prototype, "status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], WorkOrder.prototype, "resolution", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], WorkOrder.prototype, "created_at", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], WorkOrder.prototype, "updated_at", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', nullable: true, name: 'resolved_at' }),
    __metadata("design:type", Date)
], WorkOrder.prototype, "resolved_at", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'template_type' }),
    __metadata("design:type", Object)
], WorkOrder.prototype, "template_type", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', nullable: true, name: 'sla_deadline' }),
    __metadata("design:type", Object)
], WorkOrder.prototype, "sla_deadline", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'int', default: 0, name: 'sla_overdue_count' }),
    __metadata("design:type", Number)
], WorkOrder.prototype, "sla_overdue_count", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'jsonb', nullable: true, name: 'attachments' }),
    __metadata("design:type", Object)
], WorkOrder.prototype, "attachments", void 0);
exports.WorkOrder = WorkOrder = __decorate([
    (0, typeorm_1.Entity)('work_orders')
], WorkOrder);
//# sourceMappingURL=work-order.entity.js.map