import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder, Between, FindOptionsWhere, Like } from 'typeorm';
import { Alert } from '../../entities/alert.entity';
import { WorkOrder, WorkOrderStatus, WorkOrderPriority } from '../../entities/work-order.entity';
import { Device } from '../../entities/device.entity';
import { Role } from '../../common/enums/role.enum';
import { QueryAlertDto } from './dto/query-alert.dto';
import { CreateWorkOrderDto } from './dto/create-work-order.dto';
import { SlaEngineService } from './sla-engine.service';
import { WorkOrderTemplateService } from './work-order-template.service';
import { v4 as uuidv4 } from 'uuid';

interface CurrentUser {
  id: number;
  role: Role;
}

@Injectable()
export class AlertService {
  private readonly logger = new Logger(AlertService.name);

  constructor(
    @InjectRepository(Alert)
    private alertRepo: Repository<Alert>,
    @InjectRepository(WorkOrder)
    private workOrderRepo: Repository<WorkOrder>,
    @InjectRepository(Device)
    private deviceRepo: Repository<Device>,
    private readonly slaEngineService: SlaEngineService,
    private readonly templateService: WorkOrderTemplateService,
  ) {}

  private applyRoleFilter(query: SelectQueryBuilder<Alert>, user: CurrentUser): void {
    if (user.role === Role.SUPER_ADMIN) return;
    if (user.role === Role.END_USER) {
      query.andWhere('alert.user_id = :userId', { userId: user.id });
    } else if (user.role === Role.INSTALLER) {
      query
        .leftJoin(Device, 'd', 'd.sn = alert.device_sn')
        .andWhere('(alert.user_id = :userId OR d.installer_id = :userId)', { userId: user.id });
    } else if (user.role === Role.AGENT) {
      query.andWhere('alert.user_id IN ' +
        '(SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
    }
  }

  async findAll(queryDto: QueryAlertDto, currentUser: CurrentUser) {
    const { page = 1, pageSize = 20, status, alarmLevel, keyword, startTime, endTime } = queryDto;

    const qb = this.alertRepo.createQueryBuilder('alert')
      .leftJoinAndMapOne('alert.device', Device, 'device', 'device.sn = alert.device_sn')
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
      qb.andWhere(
        '(alert.device_sn ILIKE :kw OR alert.fault_message ILIKE :kw)',
        { kw: `%${keyword}%` },
      );
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

  async acknowledge(id: number, userId: number) {
    const alert = await this.alertRepo.findOne({ where: { id } });
    if (!alert) {
      throw new NotFoundException('告警记录不存在');
    }
    alert.status = 1;
    alert.handled_by = userId;
    alert.handled_at = new Date();
    return this.alertRepo.save(alert);
  }

  async ignore(id: number, userId: number) {
    const alert = await this.alertRepo.findOne({ where: { id } });
    if (!alert) {
      throw new NotFoundException('告警记录不存在');
    }
    alert.status = 2;
    alert.handled_by = userId;
    alert.handled_at = new Date();
    return this.alertRepo.save(alert);
  }

  async getStats(currentUser: CurrentUser) {
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

  async createWorkOrder(dto: CreateWorkOrderDto, userId: number) {
    let title = dto.title;
    let description = dto.description;
    let priority = dto.priority ?? WorkOrderPriority.LOW;
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
      id: uuidv4(),
      title,
      description,
      device_sn: dto.deviceSn,
      station_id: dto.stationId,
      created_by: userId,
      assigned_to: dto.assignedTo,
      priority,
      status: WorkOrderStatus.OPEN,
      template_type: templateType,
      sla_deadline: slaDeadline,
      sla_overdue_count: 0,
    });
    return this.workOrderRepo.save(workOrder);
  }

  async getWorkOrders(query: any, currentUser: CurrentUser) {
    const { page = 1, pageSize = 20, status, priority, deviceSn } = query;

    const qb = this.workOrderRepo.createQueryBuilder('wo');

    if (currentUser.role === Role.END_USER) {
      qb.andWhere('wo.created_by = :userId', { userId: currentUser.id });
    } else if (currentUser.role === Role.INSTALLER) {
      qb.andWhere(
        '(wo.created_by = :userId OR wo.assigned_to = :userId OR wo.device_sn IN ' +
        '(SELECT d.sn FROM devices d WHERE d.installer_id = :userId))',
        { userId: currentUser.id },
      );
    } else if (currentUser.role === Role.AGENT) {
      qb.andWhere(
        'wo.created_by IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId) ' +
        'OR wo.assigned_to IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId) ' +
        'OR wo.assigned_to = :userId',
        { userId: currentUser.id },
      );
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

  async getWorkOrder(id: string) {
    const workOrder = await this.workOrderRepo.findOne({ where: { id } });
    if (!workOrder) {
      throw new NotFoundException('工单不存在');
    }
    return workOrder;
  }

  async updateWorkOrderStatus(id: string, status: WorkOrderStatus, resolution?: string) {
    const workOrder = await this.workOrderRepo.findOne({ where: { id } });
    if (!workOrder) {
      throw new NotFoundException('工单不存在');
    }
    workOrder.status = status;
    if (resolution !== undefined) {
      workOrder.resolution = resolution;
    }
    if (status === WorkOrderStatus.RESOLVED || status === WorkOrderStatus.CLOSED) {
      workOrder.resolved_at = new Date();
    }
    return this.workOrderRepo.save(workOrder);
  }

  async assignWorkOrder(id: string, assignedTo: number) {
    const workOrder = await this.workOrderRepo.findOne({ where: { id } });
    if (!workOrder) {
      throw new NotFoundException('工单不存在');
    }
    workOrder.assigned_to = assignedTo;
    if (workOrder.status === WorkOrderStatus.OPEN) {
      workOrder.status = WorkOrderStatus.IN_PROGRESS;
    }
    return this.workOrderRepo.save(workOrder);
  }

  async escalateWorkOrder(id: string) {
    const workOrder = await this.workOrderRepo.findOne({ where: { id } });
    if (!workOrder) {
      throw new NotFoundException('工单不存在');
    }
    if (workOrder.priority < WorkOrderPriority.URGENT) {
      workOrder.priority = workOrder.priority + 1;
    }
    workOrder.sla_deadline = this.slaEngineService.calculateDeadline(workOrder.priority);
    this.logger.warn(`Work order ${id} manually escalated to priority ${workOrder.priority}`);
    return this.workOrderRepo.save(workOrder);
  }

  getTemplates() {
    return this.templateService.getTemplates();
  }
}
