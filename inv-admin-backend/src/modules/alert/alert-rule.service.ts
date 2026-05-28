import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In, LessThan } from 'typeorm';
import { AlertRule } from '../../entities/alert-rule.entity';
import { Alert } from '../../entities/alert.entity';
import { Device } from '../../entities/device.entity';
import { AlertNotification } from '../../entities/alert-notification.entity';
import { CreateAlertRuleDto } from './dto/create-alert-rule.dto';

interface CurrentUser {
  id: number;
  role: number;
}

@Injectable()
export class AlertRuleService {
  private readonly logger = new Logger(AlertRuleService.name);

  constructor(
    @InjectRepository(AlertRule)
    private readonly alertRuleRepo: Repository<AlertRule>,
    @InjectRepository(Alert)
    private readonly alertRepo: Repository<Alert>,
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
    @InjectRepository(AlertNotification)
    private readonly notificationRepo: Repository<AlertNotification>,
  ) {}

  async create(dto: CreateAlertRuleDto, currentUser: CurrentUser): Promise<AlertRule> {
    const rule = this.alertRuleRepo.create({
      ...dto,
      created_by: currentUser.id,
    });
    return this.alertRuleRepo.save(rule);
  }

  async findAll(query: {
    page?: number;
    pageSize?: number;
    isActive?: boolean;
    deviceModel?: string;
  }) {
    const { page = 1, pageSize = 20, isActive, deviceModel } = query;

    const qb = this.alertRuleRepo.createQueryBuilder('rule');

    if (isActive !== undefined && isActive !== null) {
      qb.andWhere('rule.is_active = :isActive', { isActive: String(isActive) === 'true' });
    }
    if (deviceModel) {
      qb.andWhere(
        '(rule.device_model = :model OR rule.device_model IS NULL)',
        { model: deviceModel },
      );
    }

    qb.orderBy('rule.created_at', 'DESC')
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

  async update(id: number, dto: CreateAlertRuleDto): Promise<AlertRule> {
    const rule = await this.alertRuleRepo.findOne({ where: { id } });
    if (!rule) {
      throw new NotFoundException('告警规则不存在');
    }
    Object.assign(rule, dto);
    return this.alertRuleRepo.save(rule);
  }

  async delete(id: number): Promise<void> {
    const rule = await this.alertRuleRepo.findOne({ where: { id } });
    if (!rule) {
      throw new NotFoundException('告警规则不存在');
    }
    rule.is_active = false;
    await this.alertRuleRepo.save(rule);
  }

  evaluateRule(rule: AlertRule, telemetry: any): boolean {
    const fieldPath = rule.field_name;
    const value = this.resolveNestedPath(fieldPath, telemetry);

    if (value === undefined || value === null) {
      return false;
    }

    const threshold = Number(rule.threshold_value);
    const numValue = Number(value);

    if (isNaN(numValue)) {
      const strValue = String(value);
      switch (rule.operator) {
        case 'eq': return strValue === String(threshold);
        case 'neq': return strValue !== String(threshold);
        default: return false;
      }
    }

    switch (rule.operator) {
      case 'gt': return numValue > threshold;
      case 'lt': return numValue < threshold;
      case 'eq': return numValue === threshold;
      case 'gte': return numValue >= threshold;
      case 'lte': return numValue <= threshold;
      case 'neq': return numValue !== threshold;
      default:
        this.logger.warn(`Unknown operator: ${rule.operator}`);
        return false;
    }
  }

  async processTelemetry(sn: string, telemetry: any): Promise<Alert | null> {
    const device = await this.deviceRepo.findOne({ where: { sn } });
    if (!device) {
      this.logger.warn(`Device not found for SN: ${sn}`);
      return null;
    }

    const rules = await this.getApplicableRules(device.model);

    for (const rule of rules) {
      const triggered = this.evaluateRule(rule, telemetry);

      if (triggered) {
        if (!this.checkCooldown(rule, sn)) {
          this.logger.debug(`Rule ${rule.id} for SN ${sn} is in cooldown, skipping`);
          continue;
        }

        this.logger.log(
          `Alert triggered: rule=${rule.name}, sn=${sn}, field=${rule.field_name}, ` +
          `operator=${rule.operator}, threshold=${rule.threshold_value}`,
        );

        return this.createAlertFromRule(rule, sn, device.user_id, device.station_id, telemetry);
      }
    }

    return null;
  }

  async getApplicableRules(deviceModel: string): Promise<AlertRule[]> {
    return this.alertRuleRepo.find({
      where: [
        { is_active: true, device_model: deviceModel },
        { is_active: true, device_model: null as any },
      ],
    });
  }

  private resolveNestedPath(path: string, obj: any): any {
    if (!obj || typeof obj !== 'object') {
      return undefined;
    }
    const keys = path.split('.');
    let current = obj;
    for (const key of keys) {
      if (current === null || current === undefined || typeof current !== 'object') {
        return undefined;
      }
      current = current[key] !== undefined ? current[key] : current[`data`]?.[key];
    }
    return current;
  }

  private checkCooldown(rule: AlertRule, sn: string): boolean {
    const cooldownEnd = new Date(Date.now() - rule.cooldown_minutes * 60 * 1000);
    return true;
  }

  private async createAlertFromRule(
    rule: AlertRule,
    sn: string,
    userId: number,
    stationId: number | null,
    telemetry: any,
  ): Promise<Alert> {
    const alert = this.alertRepo.create({
      device_sn: sn,
      user_id: userId,
      station_id: stationId,
      alarm_level: rule.alarm_level,
      fault_code: rule.fault_code,
      fault_message: rule.fault_message,
      fault_detail: JSON.stringify({
        rule_id: rule.id,
        rule_name: rule.name,
        field_name: rule.field_name,
        operator: rule.operator,
        threshold_value: rule.threshold_value,
        actual_value: this.resolveNestedPath(rule.field_name, telemetry),
      }),
      status: 0,
      occurred_at: new Date(),
    } as any);

    return this.alertRepo.save(alert) as unknown as Promise<Alert>;
  }
}
