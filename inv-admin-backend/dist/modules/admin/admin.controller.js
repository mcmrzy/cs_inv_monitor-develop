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
exports.AdminController = void 0;
const common_1 = require("@nestjs/common");
const admin_service_1 = require("./admin.service");
const permission_service_1 = require("./permission.service");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
let AdminController = class AdminController {
    constructor(adminService, permissionService) {
        this.adminService = adminService;
        this.permissionService = permissionService;
    }
    async getAuditLogs(query) { return this.adminService.getAuditLogs(query); }
    async getSystemHealth() { return this.adminService.getSystemHealth(); }
    async createTenant(body) { return this.adminService.createTenant(body); }
    async getTenants(page, pageSize) {
        return this.adminService.getTenants(page, pageSize);
    }
    async updateTenant(id, body) { return this.adminService.updateTenant(id, body); }
    async toggleTenant(id) { return this.adminService.toggleTenant(id); }
    async getSystemConfig() { return this.adminService.getSystemConfig(); }
    async updateSystemConfig(body) { return this.adminService.updateSystemConfig(body); }
    async getAllPermissions() { return this.permissionService.getAllPermissionsConfig(); }
    async getRolePermissions(role) { return this.permissionService.getRolePermissions(role); }
    async updateRolePermissions(role, body) {
        await this.permissionService.batchUpdatePermissions(role, body.permissions);
        return { success: true };
    }
    async togglePermission(role, body) {
        return this.permissionService.setPermission(role, body.resource, body.action, body.is_allowed);
    }
};
exports.AdminController = AdminController;
__decorate([
    (0, common_1.Get)('logs'),
    (0, require_permission_decorator_1.RequirePermission)('audit', 'view'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getAuditLogs", null);
__decorate([
    (0, common_1.Get)('system-health'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'view'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getSystemHealth", null);
__decorate([
    (0, common_1.Post)('tenants'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "createTenant", null);
__decorate([
    (0, common_1.Get)('tenants'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Query)('page')),
    __param(1, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Number]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getTenants", null);
__decorate([
    (0, common_1.Patch)('tenants/:id'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "updateTenant", null);
__decorate([
    (0, common_1.Post)('tenants/:id/toggle'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "toggleTenant", null);
__decorate([
    (0, common_1.Get)('system-config'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'view'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getSystemConfig", null);
__decorate([
    (0, common_1.Patch)('system-config'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "updateSystemConfig", null);
__decorate([
    (0, common_1.Get)('permissions'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getAllPermissions", null);
__decorate([
    (0, common_1.Get)('permissions/:role'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Param)('role')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "getRolePermissions", null);
__decorate([
    (0, common_1.Put)('permissions/:role'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Param)('role')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "updateRolePermissions", null);
__decorate([
    (0, common_1.Post)('permissions/:role/toggle'),
    (0, require_permission_decorator_1.RequirePermission)('admin', 'manage'),
    __param(0, (0, common_1.Param)('role')),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Object]),
    __metadata("design:returntype", Promise)
], AdminController.prototype, "togglePermission", null);
exports.AdminController = AdminController = __decorate([
    (0, common_1.Controller)('admin'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __metadata("design:paramtypes", [admin_service_1.AdminService,
        permission_service_1.PermissionService])
], AdminController);
//# sourceMappingURL=admin.controller.js.map