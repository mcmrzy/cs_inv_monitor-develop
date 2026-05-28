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
exports.DeviceService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const device_entity_1 = require("../../entities/device.entity");
const device_telemetry_entity_1 = require("../../entities/device-telemetry.entity");
const device_unbind_request_entity_1 = require("../../entities/device-unbind-request.entity");
const device_lifecycle_entity_1 = require("../../entities/device-lifecycle.entity");
const station_entity_1 = require("../../entities/station.entity");
const role_enum_1 = require("../../common/enums/role.enum");
const command_execution_service_1 = require("./command-execution.service");
let DeviceService = class DeviceService {
    constructor(deviceRepo, telemetryRepo, unbindRequestRepo, lifecycleRepo, stationRepo, commandExecutionService) {
        this.deviceRepo = deviceRepo;
        this.telemetryRepo = telemetryRepo;
        this.unbindRequestRepo = unbindRequestRepo;
        this.lifecycleRepo = lifecycleRepo;
        this.stationRepo = stationRepo;
        this.commandExecutionService = commandExecutionService;
    }
    async checkDeviceAccess(sn, currentUser) {
        const device = await this.deviceRepo.findOne({
            where: { sn },
            relations: ['owner', 'installer', 'station'],
        });
        if (!device) {
            throw new common_1.NotFoundException('Device not found');
        }
        const currentUserId = currentUser.id ?? currentUser.sub;
        if (currentUser.role === role_enum_1.Role.SUPER_ADMIN) {
            return device;
        }
        if (currentUser.role === role_enum_1.Role.END_USER && device.user_id !== currentUserId) {
            throw new common_1.ForbiddenException('Access denied');
        }
        if (currentUser.role === role_enum_1.Role.INSTALLER) {
            if (device.installer_id !== currentUserId && device.user_id !== currentUserId) {
                throw new common_1.ForbiddenException('Access denied');
            }
        }
        return device;
    }
    async findAll(query, currentUser) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const qb = this.deviceRepo.createQueryBuilder('d')
            .leftJoinAndSelect('d.owner', 'owner')
            .leftJoinAndSelect('d.installer', 'installer')
            .leftJoinAndSelect('d.station', 'station');
        const currentUserId = currentUser.id ?? currentUser.sub;
        switch (currentUser.role) {
            case role_enum_1.Role.SUPER_ADMIN:
                break;
            case role_enum_1.Role.AGENT:
            case role_enum_1.Role.INSTALLER:
                qb.andWhere('(d.installer_id = :userId OR d.user_id = :userId)', { userId: currentUserId });
                break;
            case role_enum_1.Role.END_USER:
                qb.andWhere('d.user_id = :userId', { userId: currentUserId });
                break;
        }
        if (query.keyword) {
            qb.andWhere('(d.sn ILIKE :kw OR d.model ILIKE :kw)', {
                kw: `%${query.keyword}%`,
            });
        }
        if (query.status !== undefined) {
            qb.andWhere('d.status = :status', { status: query.status });
        }
        if (query.model) {
            qb.andWhere('d.model = :model', { model: query.model });
        }
        qb.skip(skip).take(pageSize).orderBy('d.created_at', 'DESC');
        const [items, total] = await qb.getManyAndCount();
        return { items, total, page, pageSize };
    }
    async findBySn(sn, currentUser) {
        return this.checkDeviceAccess(sn, currentUser);
    }
    async create(dto, currentUser) {
        const existing = await this.deviceRepo.findOne({ where: { sn: dto.sn } });
        if (existing) {
            throw new common_1.BadRequestException('Device with this SN already exists');
        }
        const installerId = currentUser.role === role_enum_1.Role.INSTALLER
            ? (currentUser.id ?? currentUser.sub)
            : dto.installerId;
        const device = this.deviceRepo.create({
            sn: dto.sn,
            model: dto.model,
            rated_power: dto.ratedPower,
            firmware_version: dto.firmwareVersion,
            station_id: dto.stationId,
            user_id: dto.userId ?? 0,
            installer_id: installerId,
            status: 1,
        });
        const saved = await this.deviceRepo.save(device);
        const userId = currentUser.id ?? currentUser.sub;
        await this.recordLifecycleEvent(dto.sn, 'registered', `Device ${dto.sn} registered`, userId, { model: dto.model });
        if (dto.userId && dto.userId !== 0) {
            await this.recordLifecycleEvent(dto.sn, 'bound', `Device ${dto.sn} bound to user ${dto.userId}`, userId, { userId: dto.userId });
        }
        return saved;
    }
    async update(sn, dto, currentUser) {
        const device = await this.checkDeviceAccess(sn, currentUser);
        const previousUserId = device.user_id;
        if (dto.model !== undefined)
            device.model = dto.model;
        if (dto.ratedPower !== undefined)
            device.rated_power = dto.ratedPower;
        if (dto.firmwareVersion !== undefined)
            device.firmware_version = dto.firmwareVersion;
        if (dto.stationId !== undefined)
            device.station_id = dto.stationId;
        if (dto.userId !== undefined)
            device.user_id = dto.userId;
        if (dto.installerId !== undefined)
            device.installer_id = dto.installerId;
        if (dto.status !== undefined)
            device.status = dto.status;
        const saved = await this.deviceRepo.save(device);
        const userId = currentUser.id ?? currentUser.sub;
        if (dto.userId !== undefined && dto.userId !== previousUserId) {
            if (dto.userId !== 0 && dto.userId !== null) {
                await this.recordLifecycleEvent(sn, 'bound', `Device ${sn} bound to user ${dto.userId}`, userId, { userId: dto.userId, previousUserId });
            }
            else if (previousUserId !== 0) {
                await this.recordLifecycleEvent(sn, 'unbound', `Device ${sn} unbound from user ${previousUserId}`, userId, { previousUserId });
            }
        }
        return saved;
    }
    async delete(sn) {
        const device = await this.deviceRepo.findOne({ where: { sn }, relations: ['owner', 'installer'] });
        if (!device) {
            throw new common_1.NotFoundException('Device not found');
        }
        await this.deviceRepo.softRemove(device);
    }
    async unbind(sn, currentUser) {
        const device = await this.checkDeviceAccess(sn, currentUser);
        const previousUserId = device.user_id;
        device.user_id = 0;
        device.station_id = null;
        const saved = await this.deviceRepo.save(device);
        const userId = currentUser.id ?? currentUser.sub;
        await this.recordLifecycleEvent(sn, 'unbound', `Device ${sn} unbound from user ${previousUserId}`, userId, { previousUserId });
        return saved;
    }
    async requestUnbind(sn, userId, reason) {
        const device = await this.deviceRepo.findOne({ where: { sn }, relations: ['owner', 'installer'] });
        if (!device) {
            throw new common_1.NotFoundException('Device not found');
        }
        const existingPending = await this.unbindRequestRepo.findOne({
            where: { device_sn: sn, status: 'pending' },
        });
        if (existingPending) {
            throw new common_1.BadRequestException('There is already a pending unbind request for this device');
        }
        const request = this.unbindRequestRepo.create({
            device_sn: sn,
            requested_by: userId,
            reason: reason || '',
            status: 'pending',
        });
        return this.unbindRequestRepo.save(request);
    }
    async approveUnbind(requestId, reviewerId, comment) {
        const request = await this.unbindRequestRepo.findOne({ where: { id: requestId } });
        if (!request) {
            throw new common_1.NotFoundException('Unbind request not found');
        }
        if (request.status !== 'pending') {
            throw new common_1.BadRequestException('This request has already been processed');
        }
        request.status = 'approved';
        request.reviewed_by = reviewerId;
        request.review_comment = comment || null;
        request.reviewed_at = new Date();
        const saved = await this.unbindRequestRepo.save(request);
        const device = await this.deviceRepo.findOne({ where: { sn: request.device_sn }, relations: ['owner', 'installer'] });
        if (device) {
            const previousUserId = device.user_id;
            device.user_id = 0;
            device.station_id = null;
            await this.deviceRepo.save(device);
            await this.recordLifecycleEvent(request.device_sn, 'unbound', `Device ${request.device_sn} unbound via approval #${requestId}`, reviewerId, { previousUserId, requestId, requestReason: request.reason });
        }
        return saved;
    }
    async rejectUnbind(requestId, reviewerId, comment) {
        const request = await this.unbindRequestRepo.findOne({ where: { id: requestId } });
        if (!request) {
            throw new common_1.NotFoundException('Unbind request not found');
        }
        if (request.status !== 'pending') {
            throw new common_1.BadRequestException('This request has already been processed');
        }
        request.status = 'rejected';
        request.reviewed_by = reviewerId;
        request.review_comment = comment || '';
        request.reviewed_at = new Date();
        return this.unbindRequestRepo.save(request);
    }
    async getUnbindRequests(query) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const qb = this.unbindRequestRepo.createQueryBuilder('r');
        if (query.status) {
            qb.andWhere('r.status = :status', { status: query.status });
        }
        qb.skip(skip).take(pageSize).orderBy('r.created_at', 'DESC');
        const [items, total] = await qb.getManyAndCount();
        return { items, total, page, pageSize };
    }
    async recordLifecycleEvent(sn, eventType, description, userId, metadata) {
        const event = this.lifecycleRepo.create({
            device_sn: sn,
            event_type: eventType,
            description,
            triggered_by: userId,
            metadata: metadata ?? null,
        });
        return this.lifecycleRepo.save(event);
    }
    async getLifecycleHistory(sn, page = 1, pageSize = 20) {
        const [items, total] = await this.lifecycleRepo.findAndCount({
            where: { device_sn: sn },
            order: { created_at: 'DESC' },
            skip: (page - 1) * pageSize,
            take: pageSize,
        });
        return { items, total, page, pageSize };
    }
    async getTelemetry(sn, query, currentUser) {
        await this.checkDeviceAccess(sn, currentUser);
        const qb = this.telemetryRepo.createQueryBuilder('t')
            .where('t.device_sn = :sn', { sn });
        if (query.startTime) {
            qb.andWhere('t.time >= :startTime', { startTime: new Date(query.startTime) });
        }
        if (query.endTime) {
            qb.andWhere('t.time <= :endTime', { endTime: new Date(query.endTime) });
        }
        qb.orderBy('t.time', 'DESC').take(query.limit ?? 100);
        const rows = await qb.getMany();
        return rows.map((row) => {
            const d = row.data;
            if (!d)
                return { time: row.time, device_sn: row.device_sn };
            return {
                time: row.time,
                device_sn: row.device_sn,
                power: d.ac?.power ?? null,
                voltage: d.ac?.voltage ?? null,
                current: d.ac?.current ?? null,
                frequency: d.ac?.frequency ?? null,
                pf: d.ac?.pf ?? null,
                acPower: d.ac?.power ?? null,
                acVoltage: d.ac?.voltage ?? null,
                acCurrent: d.ac?.current ?? null,
                soc: d.battery?.soc ?? null,
                batteryVoltage: d.battery?.voltage ?? null,
                batteryCurrent: d.battery?.current ?? null,
                batteryTemp: d.battery?.temp_max ?? null,
                pvPower: d.pv?.pv_power ?? null,
                pvVoltage: d.pv?.pv_voltage ?? null,
                dailyEnergy: d.energy?.daily_pv ?? null,
                totalPower: d.ac?.power ?? 0,
                state: d.sys_status?.state ?? null,
                faultCode: d.sys_status?.fault_code ?? 0,
                tempInv: d.sys_status?.temp_inv ?? null,
                raw: d,
            };
        });
    }
    async getRealtimeData(sn, currentUser) {
        await this.checkDeviceAccess(sn, currentUser);
        const row = await this.telemetryRepo.findOne({
            where: { device_sn: sn },
            order: { time: 'DESC' },
        });
        if (!row || !row.data)
            return null;
        const d = row.data;
        const result = {
            device_sn: row.device_sn,
            time: row.time,
        };
        if (d.ac) {
            result.ac = {
                voltage: d.ac.voltage ?? null,
                current: d.ac.current ?? null,
                power: d.ac.power ?? null,
                frequency: d.ac.frequency ?? null,
                load_percent: d.ac.load_percent ?? null,
            };
        }
        if (d.battery) {
            result.battery = {
                soc: d.battery.soc ?? null,
                soh: d.battery.soh ?? null,
                voltage: d.battery.voltage ?? null,
                current: d.battery.current ?? null,
                charge_state: d.battery.charge_state ?? null,
            };
        }
        if (d.pv) {
            result.pv = {
                pv_voltage: d.pv.pv_voltage ?? null,
                pv_current: d.pv.pv_current ?? null,
                pv_power: d.pv.pv_power ?? null,
                mppt_state: d.pv.mppt_state ?? null,
            };
        }
        if (d.sys_status) {
            result.status = {
                state: d.sys_status.state ?? null,
                fault_code: d.sys_status.fault_code ?? 0,
                alarm_code: d.sys_status.alarm_code ?? 0,
                temp_inv: d.sys_status.temp_inv ?? null,
                temp_mos: d.sys_status.temp_mos ?? null,
                efficiency: d.sys_status.efficiency ?? null,
            };
        }
        if (d.energy) {
            result.energy = {
                daily_pv: d.energy.daily_pv ?? null,
                total_pv: d.energy.total_pv ?? null,
                runtime_hours: d.energy.runtime_hours ?? null,
            };
        }
        if (d.device_info) {
            result.info = {
                sn: sn,
                model: d.device_info.model ?? null,
                manufacturer: d.device_info.manufacturer ?? null,
                firmware_arm: d.device_info.firmware_arm ?? null,
                firmware_esp: d.device_info.firmware_esp ?? null,
                type: d.device_info.type ?? null,
                rated_power: d.device_info.rated_power ?? null,
                rated_voltage: d.device_info.rated_voltage ?? null,
                rated_freq: d.device_info.rated_freq ?? null,
                battery_voltage: d.device_info.battery_voltage ?? null,
                battery_type: d.device_info.battery_type ?? null,
                cell_count: d.device_info.cell_count ?? null,
            };
        }
        if (d.online_status) {
            result.online = {
                online: d.online_status.online ?? false,
                rssi: d.online_status.rssi ?? 0,
                ip: d.online_status.ip ?? '',
            };
        }
        return result;
    }
    getCommandTemplates(sn) {
        return this.commandExecutionService.getCommandTemplates(sn);
    }
    async executeCommand(sn, command, params, userId, ipAddress) {
        return this.commandExecutionService.executeCommand(sn, command, params, userId, ipAddress);
    }
    async getCommandHistory(sn, page = 1, pageSize = 20) {
        return this.commandExecutionService.getCommandHistory(sn, page, pageSize);
    }
    async exportTelemetryCSV(sn, startTime, endTime, fields, currentUser) {
        await this.checkDeviceAccess(sn, currentUser);
        const selectedFields = fields
            ? fields.split(',').filter((f) => f.trim())
            : ['total_active_power', 'daily_energy', 'internal_temperature'];
        const allowedFields = [
            'total_active_power',
            'daily_energy',
            'internal_temperature',
            'work_state',
            'fault_code',
        ];
        const validFields = selectedFields.filter((f) => allowedFields.includes(f));
        const qb = this.telemetryRepo.createQueryBuilder('t')
            .where('t.device_sn = :sn', { sn })
            .orderBy('t.time', 'ASC');
        if (startTime) {
            qb.andWhere('t.time >= :startTime', { startTime: new Date(startTime) });
        }
        if (endTime) {
            qb.andWhere('t.time <= :endTime', { endTime: new Date(endTime) });
        }
        const rows = await qb.getMany();
        const headers = ['Date', 'SN', ...validFields];
        const csvLines = [headers.join(',')];
        for (const row of rows) {
            const values = [row.time.toISOString(), sn];
            for (const field of validFields) {
                const val = row[field];
                values.push(val != null ? String(val) : '');
            }
            csvLines.push(values.join(','));
        }
        return csvLines.join('\n');
    }
    async exportTelemetryExcel(sn, startTime, endTime, currentUser) {
        await this.checkDeviceAccess(sn, currentUser);
        const qb = this.telemetryRepo.createQueryBuilder('t')
            .where('t.device_sn = :sn', { sn })
            .orderBy('t.time', 'ASC');
        if (startTime) {
            qb.andWhere('t.time >= :startTime', { startTime: new Date(startTime) });
        }
        if (endTime) {
            qb.andWhere('t.time <= :endTime', { endTime: new Date(endTime) });
        }
        const rows = await qb.getMany();
        const fields = [
            'total_active_power',
            'daily_energy',
            'internal_temperature',
            'work_state',
            'fault_code',
        ];
        const data = rows.map((row) => ({
            Date: row.time.toISOString(),
            SN: sn,
            total_active_power: row.total_active_power,
            daily_energy: row.daily_energy,
            internal_temperature: row.internal_temperature,
            work_state: row.work_state || '',
            fault_code: row.fault_code || '',
        }));
        const XLSX = require('xlsx');
        const ws = XLSX.utils.json_to_sheet(data);
        const wb = XLSX.utils.book_new();
        XLSX.utils.book_append_sheet(wb, ws, 'Telemetry');
        return XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    }
};
exports.DeviceService = DeviceService;
exports.DeviceService = DeviceService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(1, (0, typeorm_1.InjectRepository)(device_telemetry_entity_1.DeviceTelemetry)),
    __param(2, (0, typeorm_1.InjectRepository)(device_unbind_request_entity_1.DeviceUnbindRequest)),
    __param(3, (0, typeorm_1.InjectRepository)(device_lifecycle_entity_1.DeviceLifecycle)),
    __param(4, (0, typeorm_1.InjectRepository)(station_entity_1.Station)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        command_execution_service_1.CommandExecutionService])
], DeviceService);
//# sourceMappingURL=device.service.js.map