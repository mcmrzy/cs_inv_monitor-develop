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
exports.OtaTaskDevice = exports.OtaTaskDeviceStatus = void 0;
const typeorm_1 = require("typeorm");
var OtaTaskDeviceStatus;
(function (OtaTaskDeviceStatus) {
    OtaTaskDeviceStatus["PENDING"] = "pending";
    OtaTaskDeviceStatus["DOWNLOADING"] = "downloading";
    OtaTaskDeviceStatus["INSTALLING"] = "installing";
    OtaTaskDeviceStatus["SUCCESS"] = "success";
    OtaTaskDeviceStatus["FAILED"] = "failed";
})(OtaTaskDeviceStatus || (exports.OtaTaskDeviceStatus = OtaTaskDeviceStatus = {}));
let OtaTaskDevice = class OtaTaskDevice {
};
exports.OtaTaskDevice = OtaTaskDevice;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], OtaTaskDevice.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'uuid', name: 'task_id' }),
    __metadata("design:type", String)
], OtaTaskDevice.prototype, "task_id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'device_sn' }),
    __metadata("design:type", String)
], OtaTaskDevice.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'old_version' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "old_version", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, nullable: true, name: 'new_version' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "new_version", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'enum', enum: OtaTaskDeviceStatus, default: OtaTaskDeviceStatus.PENDING }),
    __metadata("design:type", String)
], OtaTaskDevice.prototype, "status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'integer', default: 0 }),
    __metadata("design:type", Number)
], OtaTaskDevice.prototype, "progress", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true, name: 'error_message' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "error_message", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', nullable: true, name: 'started_at' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "started_at", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', nullable: true, name: 'completed_at' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "completed_at", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true, name: 'mqtt_message' }),
    __metadata("design:type", Object)
], OtaTaskDevice.prototype, "mqtt_message", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' }),
    __metadata("design:type", Date)
], OtaTaskDevice.prototype, "created_at", void 0);
exports.OtaTaskDevice = OtaTaskDevice = __decorate([
    (0, typeorm_1.Entity)('ota_task_devices')
], OtaTaskDevice);
//# sourceMappingURL=ota-task-device.entity.js.map