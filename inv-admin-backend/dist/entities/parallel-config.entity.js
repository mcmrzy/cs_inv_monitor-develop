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
exports.ParallelConfig = void 0;
const typeorm_1 = require("typeorm");
let ParallelConfig = class ParallelConfig {
};
exports.ParallelConfig = ParallelConfig;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], ParallelConfig.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 100, name: 'group_name' }),
    __metadata("design:type", String)
], ParallelConfig.prototype, "group_name", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 10, default: 'single' }),
    __metadata("design:type", String)
], ParallelConfig.prototype, "phase_config", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50, name: 'master_sn' }),
    __metadata("design:type", String)
], ParallelConfig.prototype, "master_sn", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'text', nullable: true, name: 'slave_sns' }),
    __metadata("design:type", String)
], ParallelConfig.prototype, "slave_sns", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 10, scale: 2, nullable: true, name: 'circulating_current_threshold' }),
    __metadata("design:type", Number)
], ParallelConfig.prototype, "circulating_current_threshold", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'decimal', precision: 5, scale: 1, nullable: true, name: 'load_balance_deviation' }),
    __metadata("design:type", Number)
], ParallelConfig.prototype, "load_balance_deviation", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'smallint', default: 1 }),
    __metadata("design:type", Number)
], ParallelConfig.prototype, "status", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'bigint', nullable: true, name: 'created_by' }),
    __metadata("design:type", Number)
], ParallelConfig.prototype, "created_by", void 0);
__decorate([
    (0, typeorm_1.CreateDateColumn)({ type: 'timestamp', name: 'created_at' }),
    __metadata("design:type", Date)
], ParallelConfig.prototype, "created_at", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ type: 'timestamp', name: 'updated_at' }),
    __metadata("design:type", Date)
], ParallelConfig.prototype, "updated_at", void 0);
exports.ParallelConfig = ParallelConfig = __decorate([
    (0, typeorm_1.Entity)('parallel_configs')
], ParallelConfig);
//# sourceMappingURL=parallel-config.entity.js.map