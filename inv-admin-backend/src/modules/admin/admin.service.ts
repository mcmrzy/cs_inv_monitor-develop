import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, FindOptionsWhere } from 'typeorm';
import * as bcrypt from 'bcryptjs';
import { AuditLog } from '../../entities/audit-log.entity';
import { User } from '../../entities/user.entity';
import { Device } from '../../entities/device.entity';
import { SystemConfig } from '../../entities/system-config.entity';
import { Role } from '../../common/enums/role.enum';

interface QueryAuditLogDto {
  page?: number;
  pageSize?: number;
  userId?: number;
  action?: string;
  startTime?: string;
  endTime?: string;
}

interface CreateTenantDto {
  phone: string;
  password: string;
  nickname?: string;
  email?: string;
  deviceLimit?: number;
  userLimit?: number;
}

interface UpdateTenantDto {
  deviceLimit?: number;
  userLimit?: number;
}

@Injectable()
export class AdminService {
  constructor(
    @InjectRepository(AuditLog)
    private auditLogRepo: Repository<AuditLog>,
    @InjectRepository(User)
    private userRepo: Repository<User>,
    @InjectRepository(Device)
    private deviceRepo: Repository<Device>,
    @InjectRepository(SystemConfig)
    private systemConfigRepo: Repository<SystemConfig>,
  ) {}

  async getAuditLogs(query: QueryAuditLogDto) {
    const { page = 1, pageSize = 20, userId, action, startTime, endTime } = query;

    const qb = this.auditLogRepo.createQueryBuilder('log');

    if (userId) {
      qb.andWhere('log.user_id = :userId', { userId });
    }
    if (action) {
      qb.andWhere('log.action = :action', { action });
    }
    if (startTime) {
      qb.andWhere('log.created_at >= :startTime', { startTime: new Date(startTime) });
    }
    if (endTime) {
      qb.andWhere('log.created_at <= :endTime', { endTime: new Date(endTime) });
    }

    qb.orderBy('log.created_at', 'DESC')
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

  async getSystemHealth() {
    const uptimeSeconds = process.uptime();
    const days = Math.floor(uptimeSeconds / 86400);
    const hours = Math.floor((uptimeSeconds % 86400) / 3600);
    const uptime = `${days}d ${hours}h`;

    const memUsage = process.memoryUsage();
    const usedMemory = `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`;
    const totalMemory = `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`;

    let databaseStatus = 'unknown';
    try {
      await this.userRepo.query('SELECT 1');
      databaseStatus = 'connected';
    } catch {
      databaseStatus = 'disconnected';
    }

    return {
      uptime,
      memory: { used: usedMemory, total: totalMemory },
      database: databaseStatus,
      redis: 'connected',
      version: '1.0.0',
    };
  }

  private async getTenantConfig(tenantId: number, key: string): Promise<string | null> {
    const cfg = await this.systemConfigRepo.findOne({
      where: { config_key: `tenant:${tenantId}:${key}` },
    });
    return cfg?.config_value ?? null;
  }

  private async setTenantConfig(tenantId: number, key: string, value: string): Promise<void> {
    const configKey = `tenant:${tenantId}:${key}`;
    let cfg = await this.systemConfigRepo.findOne({ where: { config_key: configKey } });
    if (!cfg) {
      cfg = this.systemConfigRepo.create({
        config_key: configKey,
        config_value: value,
        description: `Tenant ${tenantId} ${key} quota`,
      });
    } else {
      cfg.config_value = value;
    }
    await this.systemConfigRepo.save(cfg);
  }

  async createTenant(dto: CreateTenantDto) {
    const existing = await this.userRepo.findOne({ where: { phone: dto.phone } });
    if (existing) {
      throw new BadRequestException('手机号已注册');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    const agent = this.userRepo.create({
      phone: dto.phone,
      password_hash: passwordHash,
      nickname: dto.nickname ?? dto.phone,
      email: dto.email ?? null,
      role: Role.AGENT,
      status: 1,
    });
    const savedAgent = await this.userRepo.save(agent);

    const deviceLimit = dto.deviceLimit ?? 100;
    const userLimit = dto.userLimit ?? 50;
    await this.setTenantConfig(savedAgent.id, 'device_limit', String(deviceLimit));
    await this.setTenantConfig(savedAgent.id, 'user_limit', String(userLimit));

    const installerPasswordHash = await bcrypt.hash('demo123456', 10);
    const installer = this.userRepo.create({
      phone: `${dto.phone}_installer`,
      password_hash: installerPasswordHash,
      nickname: `${savedAgent.nickname}-安装商`,
      role: Role.INSTALLER,
      parent_id: savedAgent.id,
      status: 1,
    });
    await this.userRepo.save(installer);

    const endUserPasswordHash = await bcrypt.hash('demo123456', 10);
    const endUser = this.userRepo.create({
      phone: `${dto.phone}_enduser`,
      password_hash: endUserPasswordHash,
      nickname: `${savedAgent.nickname}-终端用户`,
      role: Role.END_USER,
      parent_id: savedAgent.id,
      status: 1,
    });
    await this.userRepo.save(endUser);

    return {
      agent: {
        id: savedAgent.id,
        phone: savedAgent.phone,
        nickname: savedAgent.nickname,
        email: savedAgent.email,
        status: savedAgent.status,
        deviceLimit,
        userLimit,
        createdAt: savedAgent.created_at,
      },
      demoAccounts: {
        installer: { id: installer.id, phone: installer.phone, nickname: installer.nickname },
        endUser: { id: endUser.id, phone: endUser.phone, nickname: endUser.nickname },
      },
    };
  }

  async getTenants(page = 1, pageSize = 20) {
    const qb = this.userRepo.createQueryBuilder('u')
      .where('u.role = :role', { role: Role.AGENT })
      .orderBy('u.created_at', 'DESC')
      .skip((page - 1) * pageSize)
      .take(pageSize);

    const [agents, total] = await qb.getManyAndCount();

    const tenants = await Promise.all(
      agents.map(async (agent) => {
        const subUserCount = await this.userRepo.count({ where: { parent_id: agent.id } });
        const deviceCount = await this.deviceRepo.count({ where: { user_id: agent.id } });
        const deviceLimit = await this.getTenantConfig(agent.id, 'device_limit');
        const userLimit = await this.getTenantConfig(agent.id, 'user_limit');

        return {
          id: agent.id,
          phone: agent.phone,
          nickname: agent.nickname,
          email: agent.email,
          status: agent.status,
          subUserCount,
          deviceCount,
          deviceLimit: deviceLimit ? Number(deviceLimit) : null,
          userLimit: userLimit ? Number(userLimit) : null,
          createdAt: agent.created_at,
          lastLoginAt: agent.last_login_at,
        };
      }),
    );

    return { items: tenants, total, page, pageSize };
  }

  async updateTenant(id: number, dto: UpdateTenantDto) {
    const tenant = await this.userRepo.findOne({ where: { id, role: Role.AGENT } });
    if (!tenant) {
      throw new NotFoundException('租户不存在');
    }

    if (dto.deviceLimit !== undefined) {
      await this.setTenantConfig(id, 'device_limit', String(dto.deviceLimit));
    }
    if (dto.userLimit !== undefined) {
      await this.setTenantConfig(id, 'user_limit', String(dto.userLimit));
    }

    const deviceLimit = await this.getTenantConfig(id, 'device_limit');
    const userLimit = await this.getTenantConfig(id, 'user_limit');

    return {
      id: tenant.id,
      nickname: tenant.nickname,
      deviceLimit: deviceLimit ? Number(deviceLimit) : null,
      userLimit: userLimit ? Number(userLimit) : null,
    };
  }

  async toggleTenant(id: number) {
    const tenant = await this.userRepo.findOne({ where: { id, role: Role.AGENT } });
    if (!tenant) {
      throw new NotFoundException('租户不存在');
    }

    tenant.status = tenant.status === 1 ? 0 : 1;
    await this.userRepo.save(tenant);

    return {
      id: tenant.id,
      nickname: tenant.nickname,
      status: tenant.status,
      enabled: tenant.status === 1,
    };
  }

  async getSystemConfig() {
    const configs = await this.systemConfigRepo.find({
      where: { config_key: 'system_settings' },
    });
    if (configs.length === 0) {
      return {};
    }
    try {
      return JSON.parse(configs[0].config_value);
    } catch {
      return {};
    }
  }

  async updateSystemConfig(data: Record<string, unknown>) {
    let cfg = await this.systemConfigRepo.findOne({
      where: { config_key: 'system_settings' },
    });
    if (!cfg) {
      cfg = this.systemConfigRepo.create({
        config_key: 'system_settings',
        config_value: JSON.stringify(data),
        description: 'System configuration',
      });
    } else {
      cfg.config_value = JSON.stringify(data);
    }
    await this.systemConfigRepo.save(cfg);
    return { success: true };
  }
}
