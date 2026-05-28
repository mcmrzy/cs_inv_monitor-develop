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
exports.DeviceController = void 0;
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const device_service_1 = require("./device.service");
const excel_import_service_1 = require("./excel-import.service");
const create_device_dto_1 = require("./dto/create-device.dto");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
let DeviceController = class DeviceController {
    constructor(deviceService, excelImportService) {
        this.deviceService = deviceService;
        this.excelImportService = excelImportService;
    }
    findAll(query, currentUser) {
        return this.deviceService.findAll(query, currentUser);
    }
    getUnbindRequests(status, page, pageSize) {
        return this.deviceService.getUnbindRequests({ status, page, pageSize });
    }
    findBySn(sn, currentUser) {
        return this.deviceService.findBySn(sn, currentUser);
    }
    getLifecycleHistory(sn, page, pageSize) {
        return this.deviceService.getLifecycleHistory(sn, page, pageSize);
    }
    create(dto, currentUser) {
        return this.deviceService.create(dto, currentUser);
    }
    async importExcel(file, currentUser, installerId) {
        const rows = this.excelImportService.parseExcel(file.buffer);
        const userId = currentUser.id ?? currentUser.sub;
        const installer = installerId ?? userId;
        return this.excelImportService.bulkImport(rows, userId, installer);
    }
    requestUnbind(sn, body, currentUser) {
        const userId = currentUser.id ?? currentUser.sub;
        return this.deviceService.requestUnbind(sn, userId, body.reason);
    }
    approveUnbind(id, body, currentUser) {
        const userId = currentUser.id ?? currentUser.sub;
        return this.deviceService.approveUnbind(id, userId, body.comment ?? '');
    }
    rejectUnbind(id, body, currentUser) {
        const userId = currentUser.id ?? currentUser.sub;
        return this.deviceService.rejectUnbind(id, userId, body.comment ?? '');
    }
    update(sn, dto, currentUser) {
        return this.deviceService.update(sn, dto, currentUser);
    }
    delete(sn) {
        return this.deviceService.delete(sn);
    }
    unbind(sn, currentUser) {
        return this.deviceService.unbind(sn, currentUser);
    }
    getTelemetry(sn, startTime, endTime, limit, currentUser) {
        return this.deviceService.getTelemetry(sn, { startTime, endTime, limit }, currentUser);
    }
    getRealtimeData(sn, currentUser) {
        return this.deviceService.getRealtimeData(sn, currentUser);
    }
    getCommandTemplates(sn) {
        return this.deviceService.getCommandTemplates(sn);
    }
    sendConfig(sn, body, currentUser, req) {
        const userId = currentUser.id ?? currentUser.sub;
        const ipAddress = req.ip || req.connection?.remoteAddress;
        return this.deviceService.executeCommand(sn, body.command, body.params, userId, ipAddress);
    }
    getCommandHistory(sn, page, pageSize) {
        return this.deviceService.getCommandHistory(sn, page, pageSize);
    }
    async exportTelemetryCSV(sn, startTime, endTime, fields, currentUser, res) {
        const csv = await this.deviceService.exportTelemetryCSV(sn, startTime ?? '', endTime ?? '', fields ?? '', currentUser);
        res.setHeader('Content-Type', 'text/csv; charset=utf-8');
        res.setHeader('Content-Disposition', `attachment; filename="${sn}_telemetry_${Date.now()}.csv"`);
        res.send(csv);
    }
    async exportTelemetryExcel(sn, startTime, endTime, currentUser, res) {
        const buffer = await this.deviceService.exportTelemetryExcel(sn, startTime ?? '', endTime ?? '', currentUser);
        res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        res.setHeader('Content-Disposition', `attachment; filename="${sn}_telemetry_${Date.now()}.xlsx"`);
        res.send(buffer);
    }
};
exports.DeviceController = DeviceController;
__decorate([
    (0, common_1.Get)(),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Query)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_device_dto_1.QueryDeviceDto, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "findAll", null);
__decorate([
    (0, common_1.Get)('unbind-requests'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Query)('status')),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Number, Number]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getUnbindRequests", null);
__decorate([
    (0, common_1.Get)(':sn'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "findBySn", null);
__decorate([
    (0, common_1.Get)(':sn/lifecycle'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Number, Number]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getLifecycleHistory", null);
__decorate([
    (0, common_1.Post)(),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'create'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_device_dto_1.CreateDeviceDto, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "create", null);
__decorate([
    (0, common_1.Post)('import-excel'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'create'),
    (0, common_1.UseInterceptors)((0, platform_express_1.FileInterceptor)('file')),
    __param(0, (0, common_1.UploadedFile)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __param(2, (0, common_1.Body)('installerId')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object, Number]),
    __metadata("design:returntype", Promise)
], DeviceController.prototype, "importExcel", null);
__decorate([
    (0, common_1.Post)(':sn/request-unbind'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "requestUnbind", null);
__decorate([
    (0, common_1.Post)('unbind-requests/:id/approve'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Object, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "approveUnbind", null);
__decorate([
    (0, common_1.Post)('unbind-requests/:id/reject'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Object, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "rejectUnbind", null);
__decorate([
    (0, common_1.Put)(':sn'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'edit'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, create_device_dto_1.UpdateDeviceDto, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "update", null);
__decorate([
    (0, common_1.Delete)(':sn'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'delete'),
    __param(0, (0, common_1.Param)('sn')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "delete", null);
__decorate([
    (0, common_1.Post)(':sn/unbind'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'manage'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "unbind", null);
__decorate([
    (0, common_1.Get)(':sn/telemetry'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Query)('startTime')),
    __param(2, (0, common_1.Query)('endTime')),
    __param(3, (0, common_1.Query)('limit')),
    __param(4, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Number, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getTelemetry", null);
__decorate([
    (0, common_1.Get)(':sn/realtime'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getRealtimeData", null);
__decorate([
    (0, common_1.Get)(':sn/commands'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Param)('sn')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getCommandTemplates", null);
__decorate([
    (0, common_1.Post)(':sn/config'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'control'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __param(3, (0, common_1.Req)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object, Object, Object]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "sendConfig", null);
__decorate([
    (0, common_1.Get)(':sn/commands/history'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'view'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Number, Number]),
    __metadata("design:returntype", void 0)
], DeviceController.prototype, "getCommandHistory", null);
__decorate([
    (0, common_1.Get)(':sn/telemetry/export'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'export'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Query)('startTime')),
    __param(2, (0, common_1.Query)('endTime')),
    __param(3, (0, common_1.Query)('fields')),
    __param(4, (0, current_user_decorator_1.CurrentUser)()),
    __param(5, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, String, Object, Object]),
    __metadata("design:returntype", Promise)
], DeviceController.prototype, "exportTelemetryCSV", null);
__decorate([
    (0, common_1.Get)(':sn/telemetry/export-excel'),
    (0, require_permission_decorator_1.RequirePermission)('devices', 'export'),
    __param(0, (0, common_1.Param)('sn')),
    __param(1, (0, common_1.Query)('startTime')),
    __param(2, (0, common_1.Query)('endTime')),
    __param(3, (0, current_user_decorator_1.CurrentUser)()),
    __param(4, (0, common_1.Res)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String, String, Object, Object]),
    __metadata("design:returntype", Promise)
], DeviceController.prototype, "exportTelemetryExcel", null);
exports.DeviceController = DeviceController = __decorate([
    (0, common_1.Controller)('devices'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __metadata("design:paramtypes", [device_service_1.DeviceService,
        excel_import_service_1.ExcelImportService])
], DeviceController);
//# sourceMappingURL=device.controller.js.map