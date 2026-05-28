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
exports.OtaTask = exports.OtaTaskStatus = void 0;
const typeorm_1 = require("typeorm");
var OtaTaskStatus;
(function (OtaTaskStatus) {
    OtaTaskStatus["PENDING"] = "pending";
    OtaTaskStatus["PUSHING"] = "pushing";
    OtaTaskStatus["IN_PROGRESS"] = "in_progress";
    OtaTaskStatus["COMPLETED"] = "completed";
    OtaTaskStatus["FAILED"] = "failed";
    OtaTaskStatus["CANCELLED"] = "cancelled";
    OtaTaskStatus["ROLLED_BACK"] = "rolled_back";
})(OtaTaskStatus || (exports.OtaTaskStatus = OtaTaskStatus = {}));
let OtaTask = class OtaTask {
};
exports.OtaTask = OtaTask;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)('uuid'),
    __metadata("design:type", String)
], OtaTask.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 200 }),
    __metadata("design:type", String)
], OtaTask.prototype, "name", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', name: 'firmware_id' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "firmware_id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', name: 'created_by' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "created_by", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'enum', enum: OtaTaskStatus, default: OtaTaskStatus.PENDING }),
    __metadata("design:type", String)
], OtaTask.prototype, "status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'integer', default: 0, name: 'total_devices' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "total_devices", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'integer', default: 0, name: 'success_count' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "success_count", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'integer', default: 0, name: 'failed_count' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "failed_count", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 20, default: 'all_at_once', name: 'push_strategy' }),
    __metadata("design:type", String)
], OtaTask.prototype, "push_strategy", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'int', default: 100, name: 'push_percentage' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "push_percentage", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'int', default: 10, name: 'batch_size' }),
    __metadata("design:type", Number)
], OtaTask.prototype, "batch_size", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], OtaTask.prototype, "created_at", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], OtaTask.prototype, "updated_at", void 0);
exports.OtaTask = OtaTask = __decorate([
    (0, typeorm_1.Entity)('ota_tasks')
], OtaTask);
//# sourceMappingURL=ota-task.entity.js.map