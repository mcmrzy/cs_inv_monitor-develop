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
exports.OtaController = void 0;
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const ota_service_1 = require("./ota.service");
const create_firmware_dto_1 = require("./dto/create-firmware.dto");
const create_ota_task_dto_1 = require("./dto/create-ota-task.dto");
const query_ota_task_dto_1 = require("./dto/query-ota-task.dto");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
let OtaController = class OtaController {
    constructor(otaService) {
        this.otaService = otaService;
    }
    uploadFirmware(file, dto, currentUser) {
        return this.otaService.uploadFirmware(file, dto, currentUser.id ?? currentUser.sub);
    }
    getFirmwares(model, page, pageSize) {
        return this.otaService.getFirmwares({ model, page, pageSize });
    }
    deleteFirmware(id) { return this.otaService.deleteFirmware(id); }
    createTask(dto, currentUser) {
        return this.otaService.createTask(dto, currentUser.id ?? currentUser.sub);
    }
    getTasks(query, currentUser) {
        return this.otaService.getTasks(query, currentUser);
    }
    getTaskDetail(id) { return this.otaService.getTaskDetail(id); }
    getTaskDevices(id, page, pageSize) {
        return this.otaService.getTaskDevices(id, { page, pageSize });
    }
    executeTask(id) { return this.otaService.executeTask(id); }
    cancelTask(id) { return this.otaService.cancelTask(id); }
    retryDevice(id, deviceSn) {
        return this.otaService.retryDevice(id, deviceSn);
    }
    rollbackTask(id) { return this.otaService.rollbackTask(id); }
};
exports.OtaController = OtaController;
__decorate([
    (0, common_1.Post)('firmwares'),
    (0, require_permission_decorator_1.RequirePermission)('firmware', 'create'),
    (0, common_1.UseInterceptors)((0, platform_express_1.FileInterceptor)('file')),
    __param(0, (0, common_1.UploadedFile)()),
    __param(1, (0, common_1.Body)()),
    __param(2, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, create_firmware_dto_1.CreateFirmwareDto, Object]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "uploadFirmware", null);
__decorate([
    (0, common_1.Get)('firmwares'),
    (0, require_permission_decorator_1.RequirePermission)('firmware', 'view'),
    __param(0, (0, common_1.Query)('model')),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Number, Number]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "getFirmwares", null);
__decorate([
    (0, common_1.Delete)('firmwares/:id'),
    (0, require_permission_decorator_1.RequirePermission)('firmware', 'delete'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "deleteFirmware", null);
__decorate([
    (0, common_1.Post)('ota/tasks'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'create'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_ota_task_dto_1.CreateOtaTaskDto, Object]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "createTask", null);
__decorate([
    (0, common_1.Get)('ota/tasks'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'view'),
    __param(0, (0, common_1.Query)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [query_ota_task_dto_1.QueryOtaTaskDto, Object]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "getTasks", null);
__decorate([
    (0, common_1.Get)('ota/tasks/:id'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'view'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "getTaskDetail", null);
__decorate([
    (0, common_1.Get)('ota/tasks/:id/devices'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'view'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Number, Number]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "getTaskDevices", null);
__decorate([
    (0, common_1.Post)('ota/tasks/:id/execute'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'control'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "executeTask", null);
__decorate([
    (0, common_1.Post)('ota/tasks/:id/cancel'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'control'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "cancelTask", null);
__decorate([
    (0, common_1.Post)('ota/tasks/:id/retry/:deviceSn'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'control'),
    __param(0, (0, common_1.Param)('id')),
    __param(1, (0, common_1.Param)('deviceSn')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, String]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "retryDevice", null);
__decorate([
    (0, common_1.Post)('ota/tasks/:id/rollback'),
    (0, require_permission_decorator_1.RequirePermission)('ota', 'control'),
    __param(0, (0, common_1.Param)('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], OtaController.prototype, "rollbackTask", null);
exports.OtaController = OtaController = __decorate([
    (0, common_1.Controller)(),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __metadata("design:paramtypes", [ota_service_1.OtaService])
], OtaController);
//# sourceMappingURL=ota.controller.js.map