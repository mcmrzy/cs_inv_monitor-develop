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
exports.ParallelService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const parallel_config_entity_1 = require("../../entities/parallel-config.entity");
const parallel_status_entity_1 = require("../../entities/parallel-status.entity");
const device_entity_1 = require("../../entities/device.entity");
const alert_entity_1 = require("../../entities/alert.entity");
let ParallelService = class ParallelService {
    constructor(configRepo, statusRepo, deviceRepo, alertRepo) {
        this.configRepo = configRepo;
        this.statusRepo = statusRepo;
        this.deviceRepo = deviceRepo;
        this.alertRepo = alertRepo;
    }
    async createGroup(dto, userId) {
        const master = await this.deviceRepo.findOne({ where: { sn: dto.masterSn } });
        if (!master) {
            throw new common_1.BadRequestException(`Master device ${dto.masterSn} not found`);
        }
        const slaveList = dto.slaveSns.split(',').map((s) => s.trim()).filter(Boolean);
        if (slaveList.length === 0) {
            throw new common_1.BadRequestException('At least one slave SN is required');
        }
        if (slaveList.length > 8) {
            throw new common_1.BadRequestException('Maximum 8 slave devices allowed');
        }
        const existingSlaves = await this.deviceRepo.find({
            where: { sn: (0, typeorm_2.In)(slaveList) },
        });
        if (existingSlaves.length !== slaveList.length) {
            throw new common_1.BadRequestException('One or more slave SNs not found');
        }
        const existingGroup = await this.configRepo.findOne({
            where: { master_sn: dto.masterSn, status: 1 },
        });
        if (existingGroup) {
            throw new common_1.BadRequestException(`Master device ${dto.masterSn} is already in an active group`);
        }
        const saved = await this.configRepo.save({
            group_name: dto.groupName,
            phase_config: dto.phaseConfig,
            master_sn: dto.masterSn,
            slave_sns: dto.slaveSns,
            circulating_current_threshold: dto.circulatingCurrentThreshold ?? null,
            load_balance_deviation: dto.loadBalanceDeviation ?? null,
            created_by: userId,
            status: 1,
        });
        await this.statusRepo.save({
            parallel_id: saved.id,
            device_sn: dto.masterSn,
            role: 'master',
            sync_status: 'synced',
            data_time: new Date(),
        });
        const statusRows = slaveList.map((sn) => ({
            parallel_id: saved.id,
            device_sn: sn,
            role: 'slave',
            sync_status: 'synced',
            data_time: new Date(),
        }));
        await this.statusRepo.save(statusRows);
        return saved;
    }
    async getAllGroups(query) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const qb = this.configRepo.createQueryBuilder('c');
        if (query.keyword) {
            qb.andWhere('(c.group_name ILIKE :kw OR c.master_sn ILIKE :kw)', {
                kw: `%${query.keyword}%`,
            });
        }
        if (query.phaseConfig) {
            qb.andWhere('c.phase_config = :phaseConfig', { phaseConfig: query.phaseConfig });
        }
        if (query.status !== undefined) {
            qb.andWhere('c.status = :status', { status: query.status });
        }
        qb.skip(skip).take(pageSize).orderBy('c.created_at', 'DESC');
        const [items, total] = await qb.getManyAndCount();
        const enrichedItems = await Promise.all(items.map(async (group) => {
            const statuses = await this.statusRepo.find({
                where: { parallel_id: group.id },
                order: { data_time: 'DESC' },
            });
            const totalPower = statuses.reduce((sum, s) => sum + Number(s.output_power), 0);
            const slaveCount = group.slave_sns
                ? group.slave_sns.split(',').filter(Boolean).length
                : 0;
            return {
                ...group,
                slave_count: slaveCount,
                total_power: totalPower,
                member_status: statuses,
            };
        }));
        return { items: enrichedItems, total, page, pageSize };
    }
    async getGroupDetail(id) {
        const group = await this.configRepo.findOne({ where: { id } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        const statuses = await this.statusRepo.find({
            where: { parallel_id: group.id },
            order: { data_time: 'DESC' },
        });
        const totalPower = statuses.reduce((sum, s) => sum + Number(s.output_power), 0);
        const slaveCount = group.slave_sns
            ? group.slave_sns.split(',').filter(Boolean).length
            : 0;
        return {
            ...group,
            slave_count: slaveCount,
            total_power: totalPower,
            members: statuses,
        };
    }
    async updateGroup(id, dto) {
        const group = await this.configRepo.findOne({ where: { id } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        if (dto.groupName !== undefined)
            group.group_name = dto.groupName;
        if (dto.phaseConfig !== undefined)
            group.phase_config = dto.phaseConfig;
        if (dto.masterSn !== undefined)
            group.master_sn = dto.masterSn;
        if (dto.circulatingCurrentThreshold !== undefined)
            group.circulating_current_threshold = dto.circulatingCurrentThreshold;
        if (dto.loadBalanceDeviation !== undefined)
            group.load_balance_deviation = dto.loadBalanceDeviation;
        if (dto.slaveSns !== undefined) {
            const slaveList = dto.slaveSns.split(',').map((s) => s.trim()).filter(Boolean);
            if (slaveList.length > 8) {
                throw new common_1.BadRequestException('Maximum 8 slave devices allowed');
            }
            const oldSlaves = group.slave_sns
                ? group.slave_sns.split(',').map((s) => s.trim()).filter(Boolean)
                : [];
            group.slave_sns = dto.slaveSns;
            const removedSlaves = oldSlaves.filter((s) => !slaveList.includes(s));
            if (removedSlaves.length > 0) {
                await this.statusRepo.delete({
                    parallel_id: id,
                    device_sn: (0, typeorm_2.In)(removedSlaves),
                    role: 'slave',
                });
            }
            const addedSlaves = slaveList.filter((s) => !oldSlaves.includes(s));
            if (addedSlaves.length > 0) {
                const existingDevices = await this.deviceRepo.find({
                    where: { sn: (0, typeorm_2.In)(addedSlaves) },
                });
                if (existingDevices.length !== addedSlaves.length) {
                    throw new common_1.BadRequestException('One or more new slave SNs not found');
                }
                const statusRows = addedSlaves.map((sn) => ({
                    parallel_id: id,
                    device_sn: sn,
                    role: 'slave',
                    sync_status: 'synced',
                    data_time: new Date(),
                }));
                await this.statusRepo.save(statusRows);
            }
        }
        return this.configRepo.save(group);
    }
    async deleteGroup(id) {
        const group = await this.configRepo.findOne({ where: { id } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        group.status = 0;
        await this.configRepo.save(group);
    }
    async syncParams(groupId, params) {
        const group = await this.configRepo.findOne({ where: { id: groupId } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        const slaveSns = group.slave_sns
            ? group.slave_sns.split(',').map((s) => s.trim()).filter(Boolean)
            : [];
        const allDevices = [group.master_sn, ...slaveSns];
        return {
            message: 'Sync parameters sent to all members',
            devices: allDevices,
        };
    }
    async getGroupStatus(id) {
        return this.statusRepo.find({
            where: { parallel_id: id },
            order: { data_time: 'DESC' },
        });
    }
    async checkCirculatingCurrent(groupId) {
        const group = await this.configRepo.findOne({ where: { id: groupId } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        const statuses = await this.statusRepo.find({
            where: { parallel_id: groupId },
        });
        const threshold = Number(group.circulating_current_threshold) || 0;
        const details = statuses
            .filter((s) => Number(s.circulating_current) > threshold)
            .map((s) => ({
            device_sn: s.device_sn,
            circulating_current: Number(s.circulating_current),
            threshold,
        }));
        return {
            hasAlert: details.length > 0,
            details,
        };
    }
    async getAlertHistory(groupId, query) {
        const group = await this.configRepo.findOne({ where: { id: groupId } });
        if (!group) {
            throw new common_1.NotFoundException('Parallel group not found');
        }
        const slaveSns = group.slave_sns
            ? group.slave_sns.split(',').map((s) => s.trim()).filter(Boolean)
            : [];
        const allSns = [group.master_sn, ...slaveSns];
        const page = query?.page ?? 1;
        const pageSize = query?.pageSize ?? 20;
        const [items, total] = await this.alertRepo.findAndCount({
            where: { device_sn: (0, typeorm_2.In)(allSns) },
            order: { occurred_at: 'DESC' },
            skip: (page - 1) * pageSize,
            take: pageSize,
        });
        return { items, total, page, pageSize };
    }
};
exports.ParallelService = ParallelService;
exports.ParallelService = ParallelService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(parallel_config_entity_1.ParallelConfig)),
    __param(1, (0, typeorm_1.InjectRepository)(parallel_status_entity_1.ParallelStatus)),
    __param(2, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(3, (0, typeorm_1.InjectRepository)(alert_entity_1.Alert)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository])
], ParallelService);
//# sourceMappingURL=parallel.service.js.map