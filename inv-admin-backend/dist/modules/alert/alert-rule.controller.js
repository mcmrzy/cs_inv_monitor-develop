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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertRuleController = void 0;
const common_1 = require("@nestjs/common");
const alert_rule_service_1 = require("./alert-rule.service");
const create_alert_rule_dto_1 = require("./dto/create-alert-rule.dto");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
let AlertRuleController = class AlertRuleController {
    constructor(alertRuleService) {
        this.alertRuleService = alertRuleService;
    }
    async findAll(page, pageSize, isActive, deviceModel) {
        return this.alertRuleService.findAll({ page, pageSize, isActive: isActive === undefined ? undefined : isActive === 'true', deviceModel });
    }
    async create(dto, user) {
        return this.alertRuleService.create(dto, user);
    }
    async update(id, dto) {
        return this.alertRuleService.update(id, dto);
    }
    async delete(id) {
        await this.alertRuleService.delete(id);
        return { message: '规则已停用' };
    }
};
exports.AlertRuleController = AlertRuleController;
__decorate([
    (0, common_1.Get)(),
    (0, require_permission_decorator_1.RequirePermission)('alert_rules', 'view'),
    __param(0, (0, common_1.Query)('page')),
    __param(1, (0, common_1.Query)('pageSize')),
    __param(2, (0, common_1.Query)('isActive')),
    __param(3, (0, common_1.Query)('deviceModel')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Number, String, String]),
    __metadata("design:returntype", Promise)
], AlertRuleController.prototype, "findAll", null);
__decorate([
    (0, common_1.Post)(),
    (0, require_permission_decorator_1.RequirePermission)('alert_rules', 'create'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_alert_rule_dto_1.CreateAlertRuleDto, Object]),
    __metadata("design:returntype", Promise)
], AlertRuleController.prototype, "create", null);
__decorate([
    (0, common_1.Put)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('alert_rules', 'edit'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, create_alert_rule_dto_1.CreateAlertRuleDto]),
    __metadata("design:returntype", Promise)
], AlertRuleController.prototype, "update", null);
__decorate([
    (0, common_1.Delete)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('alert_rules', 'delete'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", Promise)
], AlertRuleController.prototype, "delete", null);
exports.AlertRuleController = AlertRuleController = __decorate([
    (0, common_1.Controller)('alert-rules'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __metadata("design:paramtypes", [alert_rule_service_1.AlertRuleService])
], AlertRuleController);
//# sourceMappingURL=alert-rule.controller.js.map