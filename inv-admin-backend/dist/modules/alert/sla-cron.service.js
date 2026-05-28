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
var SlaCronService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SlaCronService = void 0;
const common_1 = require("@nestjs/common");
const schedule_1 = require("@nestjs/schedule");
const sla_engine_service_1 = require("./sla-engine.service");
let SlaCronService = SlaCronService_1 = class SlaCronService {
    constructor(slaEngineService) {
        this.slaEngineService = slaEngineService;
        this.logger = new common_1.Logger(SlaCronService_1.name);
    }
    async handleSlaCheck() {
        this.logger.log('Running SLA overdue check...');
        try {
            const overdueCount = await this.slaEngineService.checkOverdue();
            if (overdueCount > 0) {
                this.logger.warn(`SLA check found ${overdueCount} overdue work orders`);
            }
        }
        catch (error) {
            this.logger.error('SLA check failed', error);
        }
    }
};
exports.SlaCronService = SlaCronService;
__decorate([
    (0, schedule_1.Cron)(schedule_1.CronExpression.EVERY_10_MINUTES),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], SlaCronService.prototype, "handleSlaCheck", null);
exports.SlaCronService = SlaCronService = SlaCronService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [sla_engine_service_1.SlaEngineService])
], SlaCronService);
//# sourceMappingURL=sla-cron.service.js.map