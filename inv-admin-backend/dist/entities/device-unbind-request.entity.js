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
exports.DeviceUnbindRequest = void 0;
const typeorm_1 = require("typeorm");
let DeviceUnbindRequest = class DeviceUnbindRequest {
};
exports.DeviceUnbindRequest = DeviceUnbindRequest;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], DeviceUnbindRequest.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'device_sn' }),
    __metadata("design:type", String)
], DeviceUnbindRequest.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', name: 'requested_by' }),
    __metadata("design:type", Number)
], DeviceUnbindRequest.prototype, "requested_by", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true }),
    __metadata("design:type", Object)
], DeviceUnbindRequest.prototype, "reason", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 20, default: 'pending' }),
    __metadata("design:type", String)
], DeviceUnbindRequest.prototype, "status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'reviewed_by' }),
    __metadata("design:type", Object)
], DeviceUnbindRequest.prototype, "reviewed_by", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true, name: 'review_comment' }),
    __metadata("design:type", Object)
], DeviceUnbindRequest.prototype, "review_comment", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', nullable: true, name: 'reviewed_at' }),
    __metadata("design:type", Date)
], DeviceUnbindRequest.prototype, "reviewed_at", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at' }),
    __metadata("design:type", Date)
], DeviceUnbindRequest.prototype, "created_at", void 0);
exports.DeviceUnbindRequest = DeviceUnbindRequest = __decorate([
    (0, typeorm_1.Entity)('device_unbind_requests')
], DeviceUnbindRequest);
//# sourceMappingURL=device-unbind-request.entity.js.map