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
exports.ParallelStatus = void 0;
const typeorm_1 = require("typeorm");
let ParallelStatus = class ParallelStatus {
};
exports.ParallelStatus = ParallelStatus;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: 'bigint', name: 'parallel_id' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "parallel_id", void 0);
__decorate([
    (0, typeorm_1.Index)(),
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'device_sn' }),
    __metadata("design:type", String)
], ParallelStatus.prototype, "device_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 10, scale: 2, default: 0, name: 'output_power' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "output_power", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 5, scale: 1, default: 0, name: 'load_percent' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "load_percent", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 10, scale: 4, default: 0, name: 'phase_angle_offset' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "phase_angle_offset", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 8, scale: 3, default: 0, name: 'circulating_current' }),
    __metadata("design:type", Number)
], ParallelStatus.prototype, "circulating_current", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 20, default: 'synced' }),
    __metadata("design:type", String)
], ParallelStatus.prototype, "sync_status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 20 }),
    __metadata("design:type", String)
], ParallelStatus.prototype, "role", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'timestamp', name: 'data_time' }),
    __metadata("design:type", Date)
], ParallelStatus.prototype, "data_time", void 0);
exports.ParallelStatus = ParallelStatus = __decorate([
    (0, typeorm_1.Entity)('parallel_status')
], ParallelStatus);
//# sourceMappingURL=parallel-status.entity.js.map