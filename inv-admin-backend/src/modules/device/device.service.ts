import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Device } from '../../entities/device.entity';
import { DeviceTelemetry } from '../../entities/device-telemetry.entity';
import { DeviceUnbindRequest } from '../../entities/device-unbind-request.entity';
import { DeviceLifecycle } from '../../entities/device-lifecycle.entity';
import { Station } from '../../entities/station.entity';
import { CreateDeviceDto, UpdateDeviceDto, QueryDeviceDto } from './dto/create-device.dto';
import { Role } from '../../common/enums/role.enum';
import { CommandExecutionService } from './command-execution.service';

@Injectable()
export class DeviceService {
  constructor(
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
    @InjectRepository(DeviceTelemetry)
    private readonly telemetryRepo: Repository<DeviceTelemetry>,
    @InjectRepository(DeviceUnbindRequest)
    private readonly unbindRequestRepo: Repository<DeviceUnbindRequest>,
    @InjectRepository(DeviceLifecycle)
    private readonly lifecycleRepo: Repository<DeviceLifecycle>,
    @InjectRepository(Station)
    private readonly stationRepo: Repository<Station>,
    private readonly commandExecutionService: CommandExecutionService,
  ) {}

  private async checkDeviceAccess(sn: string, currentUser: any): Promise<Device> {
    const device = await this.deviceRepo.findOne({
      where: { sn },
      relations: ['owner', 'installer', 'station'],
    });
    if (!device) {
      throw new NotFoundException('Device not found');
    }

    const currentUserId = currentUser.id ?? currentUser.sub;

    if (currentUser.role === Role.SUPER_ADMIN) {
      return device;
    }

    if (currentUser.role === Role.END_USER && device.user_id !== currentUserId) {
      throw new ForbiddenException('Access denied');
    }

    if (currentUser.role === Role.INSTALLER) {
      if (device.installer_id !== currentUserId && device.user_id !== currentUserId) {
        throw new ForbiddenException('Access denied');
      }
    }

    return device;
  }

  async findAll(query: QueryDeviceDto, currentUser: any): Promise<{
    items: Device[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const skip = (page - 1) * pageSize;

    const qb = this.deviceRepo.createQueryBuilder('d')
      .leftJoinAndSelect('d.owner', 'owner')
      .leftJoinAndSelect('d.installer', 'installer')
      .leftJoinAndSelect('d.station', 'station');

    const currentUserId = currentUser.id ?? currentUser.sub;
    switch (currentUser.role) {
      case Role.SUPER_ADMIN:
        break;
      case Role.AGENT:
      case Role.INSTALLER:
        qb.andWhere(
          '(d.installer_id = :userId OR d.user_id = :userId)',
          { userId: currentUserId },
        );
        break;
      case Role.END_USER:
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

  async findBySn(sn: string, currentUser: any): Promise<Device> {
    return this.checkDeviceAccess(sn, currentUser);
  }

  async create(dto: CreateDeviceDto, currentUser: any): Promise<Device> {
    const existing = await this.deviceRepo.findOne({ where: { sn: dto.sn } });
    if (existing) {
      throw new BadRequestException('Device with this SN already exists');
    }

    const installerId =
      currentUser.role === Role.INSTALLER
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
    await this.recordLifecycleEvent(
      dto.sn,
      'registered',
      `Device ${dto.sn} registered`,
      userId,
      { model: dto.model },
    );

    if (dto.userId && dto.userId !== 0) {
      await this.recordLifecycleEvent(
        dto.sn,
        'bound',
        `Device ${dto.sn} bound to user ${dto.userId}`,
        userId,
        { userId: dto.userId },
      );
    }

    return saved;
  }

  async update(sn: string, dto: UpdateDeviceDto, currentUser: any): Promise<Device> {
    const device = await this.checkDeviceAccess(sn, currentUser);
    const previousUserId = device.user_id;

    if (dto.model !== undefined) device.model = dto.model;
    if (dto.ratedPower !== undefined) device.rated_power = dto.ratedPower;
    if (dto.firmwareVersion !== undefined) device.firmware_version = dto.firmwareVersion;
    if (dto.stationId !== undefined) device.station_id = dto.stationId;
    if (dto.userId !== undefined) device.user_id = dto.userId;
    if (dto.installerId !== undefined) device.installer_id = dto.installerId;
    if (dto.status !== undefined) device.status = dto.status;

    const saved = await this.deviceRepo.save(device);

    const userId = currentUser.id ?? currentUser.sub;
    if (dto.userId !== undefined && dto.userId !== previousUserId) {
      if (dto.userId !== 0 && dto.userId !== null) {
        await this.recordLifecycleEvent(
          sn,
          'bound',
          `Device ${sn} bound to user ${dto.userId}`,
          userId,
          { userId: dto.userId, previousUserId },
        );
      } else if (previousUserId !== 0) {
        await this.recordLifecycleEvent(
          sn,
          'unbound',
          `Device ${sn} unbound from user ${previousUserId}`,
          userId,
          { previousUserId },
        );
      }
    }

    return saved;
  }

  async delete(sn: string): Promise<void> {
    const device = await this.deviceRepo.findOne({ where: { sn }, relations: ['owner', 'installer'] });
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.deviceRepo.softRemove(device);
  }

  async unbind(sn: string, currentUser: any): Promise<Device> {
    const device = await this.checkDeviceAccess(sn, currentUser);
    const previousUserId = device.user_id;
    device.user_id = 0;
    device.station_id = null;
    const saved = await this.deviceRepo.save(device);

    const userId = currentUser.id ?? currentUser.sub;
    await this.recordLifecycleEvent(
      sn,
      'unbound',
      `Device ${sn} unbound from user ${previousUserId}`,
      userId,
      { previousUserId },
    );

    return saved;
  }

  async requestUnbind(sn: string, userId: number, reason: string): Promise<DeviceUnbindRequest> {
    const device = await this.deviceRepo.findOne({ where: { sn }, relations: ['owner', 'installer'] });
    if (!device) {
      throw new NotFoundException('Device not found');
    }

    const existingPending = await this.unbindRequestRepo.findOne({
      where: { device_sn: sn, status: 'pending' },
    });
    if (existingPending) {
      throw new BadRequestException('There is already a pending unbind request for this device');
    }

    const request = this.unbindRequestRepo.create({
      device_sn: sn,
      requested_by: userId,
      reason: reason || '',
      status: 'pending',
    });

    return this.unbindRequestRepo.save(request);
  }

  async approveUnbind(requestId: number, reviewerId: number, comment: string): Promise<DeviceUnbindRequest> {
    const request = await this.unbindRequestRepo.findOne({ where: { id: requestId } });
    if (!request) {
      throw new NotFoundException('Unbind request not found');
    }
    if (request.status !== 'pending') {
      throw new BadRequestException('This request has already been processed');
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

      await this.recordLifecycleEvent(
        request.device_sn,
        'unbound',
        `Device ${request.device_sn} unbound via approval #${requestId}`,
        reviewerId,
        { previousUserId, requestId, requestReason: request.reason },
      );
    }

    return saved;
  }

  async rejectUnbind(requestId: number, reviewerId: number, comment: string): Promise<DeviceUnbindRequest> {
    const request = await this.unbindRequestRepo.findOne({ where: { id: requestId } });
    if (!request) {
      throw new NotFoundException('Unbind request not found');
    }
    if (request.status !== 'pending') {
      throw new BadRequestException('This request has already been processed');
    }

    request.status = 'rejected';
    request.reviewed_by = reviewerId;
    request.review_comment = comment || '';
    request.reviewed_at = new Date();
    return this.unbindRequestRepo.save(request);
  }

  async getUnbindRequests(query: {
    status?: string;
    page?: number;
    pageSize?: number;
  }): Promise<{ items: DeviceUnbindRequest[]; total: number; page: number; pageSize: number }> {
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

  async recordLifecycleEvent(
    sn: string,
    eventType: string,
    description: string,
    userId: number,
    metadata?: any,
  ): Promise<DeviceLifecycle> {
    const event = this.lifecycleRepo.create({
      device_sn: sn,
      event_type: eventType,
      description,
      triggered_by: userId,
      metadata: metadata ?? null,
    });
    return this.lifecycleRepo.save(event);
  }

  async getLifecycleHistory(
    sn: string,
    page: number = 1,
    pageSize: number = 20,
  ): Promise<{ items: DeviceLifecycle[]; total: number; page: number; pageSize: number }> {
    const [items, total] = await this.lifecycleRepo.findAndCount({
      where: { device_sn: sn },
      order: { created_at: 'DESC' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    });
    return { items, total, page, pageSize };
  }

  async getTelemetry(
    sn: string,
    query: { startTime?: string; endTime?: string; limit?: number },
    currentUser: any,
  ): Promise<any[]> {
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
      const d = row.data as Record<string, any> | null;
      if (!d) return { time: row.time, device_sn: row.device_sn };
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

  async getRealtimeData(sn: string, currentUser: any): Promise<any> {
    await this.checkDeviceAccess(sn, currentUser);

    const row = await this.telemetryRepo.findOne({
      where: { device_sn: sn },
      order: { time: 'DESC' },
    });

    if (!row || !row.data) return null;

    const d = row.data as Record<string, any>;

    const result: any = {
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

  getCommandTemplates(sn: string) {
    return this.commandExecutionService.getCommandTemplates(sn);
  }

  async executeCommand(
    sn: string,
    command: string,
    params: any,
    userId: number,
    ipAddress?: string,
  ) {
    return this.commandExecutionService.executeCommand(sn, command, params, userId, ipAddress);
  }

  async getCommandHistory(sn: string, page: number = 1, pageSize: number = 20) {
    return this.commandExecutionService.getCommandHistory(sn, page, pageSize);
  }

  async exportTelemetryCSV(
    sn: string,
    startTime: string,
    endTime: string,
    fields: string,
    currentUser: any,
  ): Promise<string> {
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
        const val = (row as any)[field];
        values.push(val != null ? String(val) : '');
      }
      csvLines.push(values.join(','));
    }

    return csvLines.join('\n');
  }

  async exportTelemetryExcel(
    sn: string,
    startTime: string,
    endTime: string,
    currentUser: any,
  ): Promise<Buffer> {
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
}