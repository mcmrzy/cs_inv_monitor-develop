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
exports.WorkOrderController = void 0;
const common_1 = require("@nestjs/common");
const platform_express_1 = require("@nestjs/platform-express");
const multer_1 = require("multer");
const path_1 = require("path");
const alert_service_1 = require("./alert.service");
const jwt_auth_guard_1 = require("../../common/guards/jwt-auth.guard");
const permission_guard_1 = require("../../common/guards/permission.guard");
const require_permission_decorator_1 = require("../../common/decorators/require-permission.decorator");
const current_user_decorator_1 = require("../../common/decorators/current-user.decorator");
const create_work_order_dto_1 = require("./dto/create-work-order.dto");
const work_order_entity_1 = require("../../entities/work-order.entity");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const uuid_1 = require("uuid");
let WorkOrderController = class WorkOrderController {
    constructor(alertService, workOrderRepo) {
        this.alertService = alertService;
        this.workOrderRepo = workOrderRepo;
    }
    async getTemplates() {
        return this.alertService.getTemplates();
    }
    async getWorkOrders(query, user) {
        return this.alertService.getWorkOrders(query, user);
    }
    async createWorkOrder(dto, user) {
        return this.alertService.createWorkOrder(dto, user.id);
    }
    async getWorkOrder(id) {
        return this.alertService.getWorkOrder(id);
    }
    async updateWorkOrder(id, body) {
        if (body.assignedTo)
            return this.alertService.assignWorkOrder(id, body.assignedTo);
        return { message: '无效的更新操作' };
    }
    async updateWorkOrderStatus(id, body) {
        return this.alertService.updateWorkOrderStatus(id, body.status, body.resolution);
    }
    async escalateWorkOrder(id) {
        return this.alertService.escalateWorkOrder(id);
    }
    async uploadAttachments(id, files) {
        const workOrder = await this.workOrderRepo.findOne({ where: { id } });
        if (!workOrder)
            return { message: '工单不存在' };
        const existingAttachments = workOrder.attachments || [];
        if (existingAttachments.length + files.length > 10)
            return { message: '每个工单最多上传10张图片' };
        const newAttachments = files.map((file) => ({ name: file.originalname, url: `/uploads/work-orders/${file.filename}`, type: file.mimetype, uploadedAt: new Date().toISOString() }));
        workOrder.attachments = [...existingAttachments, ...newAttachments];
        await this.workOrderRepo.save(workOrder);
        return { message: '上传成功', attachments: workOrder.attachments };
    }
};
exports.WorkOrderController = WorkOrderController;
__decorate([
    (0, common_1.Get)('templates'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'view'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "getTemplates", null);
__decorate([
    (0, common_1.Get)(),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'view'),
    __param(0, (0, common_1.Query)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Object]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "getWorkOrders", null);
__decorate([
    (0, common_1.Post)(),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'create'),
    __param(0, (0, common_1.Body)()),
    __param(1, (0, current_user_decorator_1.CurrentUser)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [create_work_order_dto_1.CreateWorkOrderDto, Object]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "createWorkOrder", null);
__decorate([
    (0, common_1.Get)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'view'),
    __param(0, (0, common_1.Param)('id', common_1.ParseUUIDPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "getWorkOrder", null);
__decorate([
    (0, common_1.Patch)(':id'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'edit'),
    __param(0, (0, common_1.Param)('id', common_1.ParseUUIDPipe)),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "updateWorkOrder", null);
__decorate([
    (0, common_1.Patch)(':id/status'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'edit'),
    __param(0, (0, common_1.Param)('id', common_1.ParseUUIDPipe)),
    __param(1, (0, common_1.Body)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Object]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "updateWorkOrderStatus", null);
__decorate([
    (0, common_1.Post)(':id/escalate'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'manage'),
    __param(0, (0, common_1.Param)('id', common_1.ParseUUIDPipe)),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "escalateWorkOrder", null);
__decorate([
    (0, common_1.Post)(':id/attachments'),
    (0, require_permission_decorator_1.RequirePermission)('work_orders', 'edit'),
    (0, common_1.UseInterceptors)((0, platform_express_1.FilesInterceptor)('files', 5, {
        storage: (0, multer_1.diskStorage)({
            destination: './uploads/work-orders',
            filename: (_req, file, cb) => { const uniqueSuffix = (0, uuid_1.v4)(); cb(null, `${uniqueSuffix}${(0, path_1.extname)(file.originalname)}`); },
        }),
        fileFilter: (_req, file, cb) => {
            if (!file.mimetype.match(/^image\//)) {
                cb(new Error('只允许上传图片文件'), false);
                return;
            }
            cb(null, true);
        },
    })),
    __param(0, (0, common_1.Param)('id', common_1.ParseUUIDPipe)),
    __param(1, (0, common_1.UploadedFiles)()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, Array]),
    __metadata("design:returntype", Promise)
], WorkOrderController.prototype, "uploadAttachments", null);
exports.WorkOrderController = WorkOrderController = __decorate([
    (0, common_1.Controller)('work-orders'),
    (0, common_1.UseGuards)(jwt_auth_guard_1.JwtAuthGuard, permission_guard_1.PermissionGuard),
    __param(1, (0, typeorm_1.InjectRepository)(work_order_entity_1.WorkOrder)),
    __metadata("design:paramtypes", [alert_service_1.AlertService,
        typeorm_2.Repository])
], WorkOrderController);
//# sourceMappingURL=work-order.controller.js.map