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
exports.ParallelController = void 0;
const common_1 = require("@nestjs/common");
const parallel_service_1 = require("./parallel.service");
const create_parallel_group_dto_1 = require("./dto/create-parallel-group.dto");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
let ParallelController = class ParallelController {
    constructor(parallelService) {
        this.parallelService = parallelService;
    }
    findAll(query) { return this.parallelService.getAllGroups(query); }
    getDetail(id) { return this.parallelService.getGroupDetail(id); }
    create(dto, user) {
        return this.parallelService.createGroup(dto, user.id ?? user.sub);
    }
    update(id, dto) {
        return this.parallelService.updateGroup(id, dto);
    }
    delete(id) { return this.parallelService.deleteGroup(id); }
    syncParams(id, params) {
        return this.parallelService.syncParams(id, params);
    }
    getStatus(id) { return this.parallelService.getGroupStatus(id); }
    getAlerts(id, page, pageSize) {
        return this.parallelService.getAlertHistory(id, { page, pageSize });
    }
};
exports.ParallelController = ParallelController;
__decorate([
    (0, common_1.Get)(),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'view'),
    __param(0, (0, common_1.Query)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_parallel_group_dto_1.QueryParallelGroupDto]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "findAll", null);
__decorate([
    (0, common_1.Get)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'view'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "getDetail", null);
__decorate([
    (0, common_1.Post)(),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'create'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_parallel_group_dto_1.CreateParallelGroupDto, Object]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "create", null);
__decorate([
    (0, common_1.Patch)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'create'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, create_parallel_group_dto_1.UpdateParallelGroupDto]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "update", null);
__decorate([
    (0, common_1.Delete)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'create'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "delete", null);
__decorate([
    (0, common_1.Post)(':id/sync'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'control'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, create_parallel_group_dto_1.SyncParamsDto]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "syncParams", null);
__decorate([
    (0, common_1.Get)(':id/status'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'view'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "getStatus", null);
__decorate([
    (0, common_1.Get)(':id/alerts'),
    (0, require_permission_decorator_1.RequirePermission)('parallel', 'view'),
    __param(0, (0, common_1.Param)('id', common_1.ParseIntPipe)),
    __param(1, (0, common_1.Query)('page')),
    __param(2, (0, common_1.Query)('pageSize')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Number, Number]),
    __metadata("design:returntype", void 0)
], ParallelController.prototype, "getAlerts", null);
exports.ParallelController = ParallelController = __decorate([
    (0, common_1.Controller)('parallel-groups'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __metadata("design:paramtypes", [parallel_service_1.ParallelService])
], ParallelController);
//# sourceMappingURL=parallel.controller.js.map