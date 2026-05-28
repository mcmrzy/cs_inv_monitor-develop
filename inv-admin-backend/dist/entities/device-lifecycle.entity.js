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
exports.DeviceLifecycle = void 0;
const typeorm_1 = require("typeorm");
let DeviceLifecycle = class DeviceLifecycle {
};
exports.DeviceLifecycle = DeviceLifecycle;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], DeviceLifecycle.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'device_sn' }),
    __metadata("design:type", String)
], DeviceLifecycle.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'event_type' }),
    __metadata("design:type", String)
], DeviceLifecycle.prototype, "event_type", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", String)
], DeviceLifecycle.prototype, "description", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'triggered_by' }),
    __metadata("design:type", Number)
], DeviceLifecycle.prototype, "triggered_by", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'jsonb', nullable: true, name: 'metadata' }),
    __metadata("design:type", Object)
], DeviceLifecycle.prototype, "metadata", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at' }),
    __metadata("design:type", Date)
], DeviceLifecycle.prototype, "created_at", void 0);
exports.DeviceLifecycle = DeviceLifecycle = __decorate([
    (0, typeorm_1.Entity)('device_lifecycle')
], DeviceLifecycle);
//# sourceMappingURL=device-lifecycle.entity.js.map