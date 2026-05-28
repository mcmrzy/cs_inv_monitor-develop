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
exports.AlertRule = void 0;
const typeorm_1 = require("typeorm");
let AlertRule = class AlertRule {
};
exports.AlertRule = AlertRule;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], AlertRule.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 100 }),
    __metadata("design:type", String)
], AlertRule.prototype, "name", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 100, name: 'field_name' }),
    __metadata("design:type", String)
], AlertRule.prototype, "field_name", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 20 }),
    __metadata("design:type", String)
], AlertRule.prototype, "operator", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 12, scale: 4, name: 'threshold_value' }),
    __metadata("design:type", Number)
], AlertRule.prototype, "threshold_value", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'smallint', default: 2 }),
    __metadata("design:type", Number)
], AlertRule.prototype, "alarm_level", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 200, name: 'fault_code' }),
    __metadata("design:type", String)
], AlertRule.prototype, "fault_code", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', name: 'fault_message' }),
    __metadata("design:type", String)
], AlertRule.prototype, "fault_message", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'device_model' }),
    __metadata("design:type", String)
], AlertRule.prototype, "device_model", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'boolean', default: true, name: 'is_active' }),
    __metadata("design:type", Boolean)
], AlertRule.prototype, "is_active", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'int', default: 5, name: 'cooldown_minutes' }),
    __metadata("design:type", Number)
], AlertRule.prototype, "cooldown_minutes", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'created_by' }),
    __metadata("design:type", Number)
], AlertRule.prototype, "created_by", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at' }),
    __metadata("design:type", Date)
], AlertRule.prototype, "created_at", void 0);
exports.AlertRule = AlertRule = __decorate([
    (0, typeorm_1.Entity)('alert_rules')
], AlertRule);
//# sourceMappingURL=alert-rule.entity.js.map