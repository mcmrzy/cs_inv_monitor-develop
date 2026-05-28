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
exports.AdminService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const bcrypt = require("bcryptjs");
const audit_log_entity_1 = require("../../entities/audit-log.entity");
const user_entity_1 = require("../../entities/user.entity");
const device_entity_1 = require("../../entities/device.entity");
const system_config_entity_1 = require("../../entities/system-config.entity");
const role_enum_1 = require("../../common/enums/role.enum");
let AdminService = class AdminService {
    constructor(auditLogRepo, userRepo, deviceRepo, systemConfigRepo) {
        this.auditLogRepo = auditLogRepo;
        this.userRepo = userRepo;
        this.deviceRepo = deviceRepo;
        this.systemConfigRepo = systemConfigRepo;
    }
    async getAuditLogs(query) {
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
        }
        catch {
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
    async getTenantConfig(tenantId, key) {
        const cfg = await this.systemConfigRepo.findOne({
            where: { config_key: `tenant:${tenantId}:${key}` },
        });
        return cfg?.config_value ?? null;
    }
    async setTenantConfig(tenantId, key, value) {
        const configKey = `tenant:${tenantId}:${key}`;
        let cfg = await this.systemConfigRepo.findOne({ where: { config_key: configKey } });
        if (!cfg) {
            cfg = this.systemConfigRepo.create({
                config_key: configKey,
                config_value: value,
                description: `Tenant ${tenantId} ${key} quota`,
            });
        }
        else {
            cfg.config_value = value;
        }
        await this.systemConfigRepo.save(cfg);
    }
    async createTenant(dto) {
        const existing = await this.userRepo.findOne({ where: { phone: dto.phone } });
        if (existing) {
            throw new common_1.BadRequestException('手机号已注册');
        }
        const passwordHash = await bcrypt.hash(dto.password, 10);
        const agent = this.userRepo.create({
            phone: dto.phone,
            password_hash: passwordHash,
            nickname: dto.nickname ?? dto.phone,
            email: dto.email ?? null,
            role: role_enum_1.Role.AGENT,
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
            role: role_enum_1.Role.INSTALLER,
            parent_id: savedAgent.id,
            status: 1,
        });
        await this.userRepo.save(installer);
        const endUserPasswordHash = await bcrypt.hash('demo123456', 10);
        const endUser = this.userRepo.create({
            phone: `${dto.phone}_enduser`,
            password_hash: endUserPasswordHash,
            nickname: `${savedAgent.nickname}-终端用户`,
            role: role_enum_1.Role.END_USER,
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
            .where('u.role = :role', { role: role_enum_1.Role.AGENT })
            .orderBy('u.created_at', 'DESC')
            .skip((page - 1) * pageSize)
            .take(pageSize);
        const [agents, total] = await qb.getManyAndCount();
        const tenants = await Promise.all(agents.map(async (agent) => {
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
        }));
        return { items: tenants, total, page, pageSize };
    }
    async updateTenant(id, dto) {
        const tenant = await this.userRepo.findOne({ where: { id, role: role_enum_1.Role.AGENT } });
        if (!tenant) {
            throw new common_1.NotFoundException('租户不存在');
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
    async toggleTenant(id) {
        const tenant = await this.userRepo.findOne({ where: { id, role: role_enum_1.Role.AGENT } });
        if (!tenant) {
            throw new common_1.NotFoundException('租户不存在');
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
        }
        catch {
            return {};
        }
    }
    async updateSystemConfig(data) {
        let cfg = await this.systemConfigRepo.findOne({
            where: { config_key: 'system_settings' },
        });
        if (!cfg) {
            cfg = this.systemConfigRepo.create({
                config_key: 'system_settings',
                config_value: JSON.stringify(data),
                description: 'System configuration',
            });
        }
        else {
            cfg.config_value = JSON.stringify(data);
        }
        await this.systemConfigRepo.save(cfg);
        return { success: true };
    }
};
exports.AdminService = AdminService;
exports.AdminService = AdminService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(audit_log_entity_1.AuditLog)),
    __param(1, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __param(2, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(3, (0, typeorm_1.InjectRepository)(system_config_entity_1.SystemConfig)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository])
], AdminService);
//# sourceMappingURL=admin.service.js.map