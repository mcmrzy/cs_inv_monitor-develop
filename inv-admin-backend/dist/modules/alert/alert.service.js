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
var AlertService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const alert_entity_1 = require("../../entities/alert.entity");
const work_order_entity_1 = require("../../entities/work-order.entity");
const device_entity_1 = require("../../entities/device.entity");
const role_enum_1 = require("../../common/enums/role.enum");
const sla_engine_service_1 = require("./sla-engine.service");
const work_order_template_service_1 = require("./work-order-template.service");
const uuid_1 = require("uuid");
let AlertService = AlertService_1 = class AlertService {
    constructor(alertRepo, workOrderRepo, deviceRepo, slaEngineService, templateService) {
        this.alertRepo = alertRepo;
        this.workOrderRepo = workOrderRepo;
        this.deviceRepo = deviceRepo;
        this.slaEngineService = slaEngineService;
        this.templateService = templateService;
        this.logger = new common_1.Logger(AlertService_1.name);
    }
    applyRoleFilter(query, user) {
        if (user.role === role_enum_1.Role.SUPER_ADMIN)
            return;
        if (user.role === role_enum_1.Role.END_USER) {
            query.andWhere('alert.user_id = :userId', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.INSTALLER) {
            query
                .leftJoin(device_entity_1.Device, 'd', 'd.sn = alert.device_sn')
                .andWhere('(alert.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.AGENT) {
            query.andWhere('alert.user_id IN ' +
                '(SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
        }
    }
    async findAll(queryDto, currentUser) {
        const { page = 1, pageSize = 20, status, alarmLevel, keyword, startTime, endTime } = queryDto;
        const qb = this.alertRepo.createQueryBuilder('alert')
            .leftJoinAndMapOne('alert.device', device_entity_1.Device, 'device', 'device.sn = alert.device_sn')
            .select([
            'alert',
            'device.id', 'device.sn', 'device.model',
            'device.station_id', 'device.status',
        ]);
        this.applyRoleFilter(qb, currentUser);
        if (status !== undefined && status !== null) {
            qb.andWhere('alert.status = :status', { status });
        }
        if (alarmLevel !== undefined && alarmLevel !== null) {
            qb.andWhere('alert.alarm_level = :alarmLevel', { alarmLevel });
        }
        if (keyword) {
            qb.andWhere('(alert.device_sn ILIKE :kw OR alert.fault_message ILIKE :kw)', { kw: `%${keyword}%` });
        }
        if (startTime) {
            qb.andWhere('alert.occurred_at >= :startTime', { startTime: new Date(startTime) });
        }
        if (endTime) {
            qb.andWhere('alert.occurred_at <= :endTime', { endTime: new Date(endTime) });
        }
        qb.orderBy('alert.occurred_at', 'DESC')
            .skip((page - 1) * pageSize)
            .take(pageSize);
        const [list, total] = await qb.getManyAndCount();
        return {
            list,
            total,
            page,
            pageSize,
            totalPages: Math.ceil(total / pageSize),
        };
    }
    async acknowledge(id, userId) {
        const alert = await this.alertRepo.findOne({ where: { id } });
        if (!alert) {
            throw new common_1.NotFoundException('告警记录不存在');
        }
        alert.status = 1;
        alert.handled_by = userId;
        alert.handled_at = new Date();
        return this.alertRepo.save(alert);
    }
    async ignore(id, userId) {
        const alert = await this.alertRepo.findOne({ where: { id } });
        if (!alert) {
            throw new common_1.NotFoundException('告警记录不存在');
        }
        alert.status = 2;
        alert.handled_by = userId;
        alert.handled_at = new Date();
        return this.alertRepo.save(alert);
    }
    async getStats(currentUser) {
        const qb = this.alertRepo.createQueryBuilder('alert');
        this.applyRoleFilter(qb, currentUser);
        const totalUnhandled = await qb.clone()
            .andWhere('alert.status = 0')
            .getCount();
        const level1Count = await qb.clone()
            .andWhere('alert.status = 0')
            .andWhere('alert.alarm_level = 1')
            .getCount();
        const level2Count = await qb.clone()
            .andWhere('alert.status = 0')
            .andWhere('alert.alarm_level = 2')
            .getCount();
        const level3Count = await qb.clone()
            .andWhere('alert.status = 0')
            .andWhere('alert.alarm_level = 3')
            .getCount();
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const todayCount = await qb.clone()
            .andWhere('alert.occurred_at >= :todayStart', { todayStart })
            .getCount();
        return {
            totalUnhandled,
            byLevel: { level1: level1Count, level2: level2Count, level3: level3Count },
            todayCount,
        };
    }
    async createWorkOrder(dto, userId) {
        let title = dto.title;
        let description = dto.description;
        let priority = dto.priority ?? work_order_entity_1.WorkOrderPriority.LOW;
        let templateType = dto.templateType ?? null;
        if (templateType) {
            const template = this.templateService.getTemplate(templateType);
            if (template) {
                if (!title || title === template.title) {
                    title = template.title;
                }
                if (!description) {
                    description = template.description;
                }
                if (dto.priority === undefined || dto.priority === null) {
                    priority = template.priority;
                }
            }
        }
        const slaDeadline = this.slaEngineService.calculateDeadline(priority);
        const workOrder = this.workOrderRepo.create({
            id: (0, uuid_1.v4)(),
            title,
            description,
            device_sn: dto.deviceSn,
            station_id: dto.stationId,
            created_by: userId,
            assigned_to: dto.assignedTo,
            priority,
            status: work_order_entity_1.WorkOrderStatus.OPEN,
            template_type: templateType,
            sla_deadline: slaDeadline,
            sla_overdue_count: 0,
        });
        return this.workOrderRepo.save(workOrder);
    }
    async getWorkOrders(query, currentUser) {
        const { page = 1, pageSize = 20, status, priority, deviceSn } = query;
        const qb = this.workOrderRepo.createQueryBuilder('wo');
        if (currentUser.role === role_enum_1.Role.END_USER) {
            qb.andWhere('wo.created_by = :userId', { userId: currentUser.id });
        }
        else if (currentUser.role === role_enum_1.Role.INSTALLER) {
            qb.andWhere('(wo.created_by = :userId OR wo.assigned_to = :userId OR wo.device_sn IN ' +
                '(SELECT d.sn FROM devices d WHERE d.installer_id = :userId))', { userId: currentUser.id });
        }
        else if (currentUser.role === role_enum_1.Role.AGENT) {
            qb.andWhere('wo.created_by IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId) ' +
                'OR wo.assigned_to IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId) ' +
                'OR wo.assigned_to = :userId', { userId: currentUser.id });
        }
        if (status) {
            qb.andWhere('wo.status = :status', { status });
        }
        if (priority) {
            qb.andWhere('wo.priority = :priority', { priority });
        }
        if (deviceSn) {
            qb.andWhere('wo.device_sn = :deviceSn', { deviceSn });
        }
        qb.orderBy('wo.created_at', 'DESC')
            .skip((page - 1) * pageSize)
            .take(pageSize);
        const [list, total] = await qb.getManyAndCount();
        return {
            list,
            total,
            page: Number(page),
            pageSize: Number(pageSize),
            totalPages: Math.ceil(total / Number(pageSize)),
        };
    }
    async getWorkOrder(id) {
        const workOrder = await this.workOrderRepo.findOne({ where: { id } });
        if (!workOrder) {
            throw new common_1.NotFoundException('工单不存在');
        }
        return workOrder;
    }
    async updateWorkOrderStatus(id, status, resolution) {
        const workOrder = await this.workOrderRepo.findOne({ where: { id } });
        if (!workOrder) {
            throw new common_1.NotFoundException('工单不存在');
        }
        workOrder.status = status;
        if (resolution !== undefined) {
            workOrder.resolution = resolution;
        }
        if (status === work_order_entity_1.WorkOrderStatus.RESOLVED || status === work_order_entity_1.WorkOrderStatus.CLOSED) {
            workOrder.resolved_at = new Date();
        }
        return this.workOrderRepo.save(workOrder);
    }
    async assignWorkOrder(id, assignedTo) {
        const workOrder = await this.workOrderRepo.findOne({ where: { id } });
        if (!workOrder) {
            throw new common_1.NotFoundException('工单不存在');
        }
        workOrder.assigned_to = assignedTo;
        if (workOrder.status === work_order_entity_1.WorkOrderStatus.OPEN) {
            workOrder.status = work_order_entity_1.WorkOrderStatus.IN_PROGRESS;
        }
        return this.workOrderRepo.save(workOrder);
    }
    async escalateWorkOrder(id) {
        const workOrder = await this.workOrderRepo.findOne({ where: { id } });
        if (!workOrder) {
            throw new common_1.NotFoundException('工单不存在');
        }
        if (workOrder.priority < work_order_entity_1.WorkOrderPriority.URGENT) {
            workOrder.priority = workOrder.priority + 1;
        }
        workOrder.sla_deadline = this.slaEngineService.calculateDeadline(workOrder.priority);
        this.logger.warn(`Work order ${id} manually escalated to priority ${workOrder.priority}`);
        return this.workOrderRepo.save(workOrder);
    }
    getTemplates() {
        return this.templateService.getTemplates();
    }
};
exports.AlertService = AlertService;
exports.AlertService = AlertService = AlertService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(alert_entity_1.Alert)),
    __param(1, (0, typeorm_1.InjectRepository)(work_order_entity_1.WorkOrder)),
    __param(2, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        sla_engine_service_1.SlaEngineService,
        work_order_template_service_1.WorkOrderTemplateService])
], AlertService);
//# sourceMappingURL=alert.service.js.map