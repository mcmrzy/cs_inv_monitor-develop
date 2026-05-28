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
exports.DeviceTelemetry = void 0;
const typeorm_1 = require("typeorm");
let DeviceTelemetry = class DeviceTelemetry {
};
exports.DeviceTelemetry = DeviceTelemetry;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], DeviceTelemetry.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'device_sn' }),
    __metadata("design:type", String)
], DeviceTelemetry.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'model_code' }),
    __metadata("design:type", String)
], DeviceTelemetry.prototype, "model_code", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 200, nullable: true }),
    __metadata("design:type", String)
], DeviceTelemetry.prototype, "topic", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'jsonb' }),
    __metadata("design:type", Object)
], DeviceTelemetry.prototype, "data", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 12, scale: 2, default: 0, name: 'total_active_power' }),
    __metadata("design:type", Number)
], DeviceTelemetry.prototype, "total_active_power", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 14, scale: 4, default: 0, name: 'daily_energy' }),
    __metadata("design:type", Number)
], DeviceTelemetry.prototype, "daily_energy", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'work_state' }),
    __metadata("design:type", String)
], DeviceTelemetry.prototype, "work_state", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'fault_code' }),
    __metadata("design:type", String)
], DeviceTelemetry.prototype, "fault_code", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 6, scale: 1, default: 0, name: 'internal_temperature' }),
    __metadata("design:type", Number)
], DeviceTelemetry.prototype, "internal_temperature", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: 'timestamp', default: () => 'NOW()' }),
    __metadata("design:type", Date)
], DeviceTelemetry.prototype, "time", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], DeviceTelemetry.prototype, "created_at", void 0);
exports.DeviceTelemetry = DeviceTelemetry = __decorate([
    (0, typeorm_1.Entity)('device_telemetry')
], DeviceTelemetry);
//# sourceMappingURL=device-telemetry.entity.js.map