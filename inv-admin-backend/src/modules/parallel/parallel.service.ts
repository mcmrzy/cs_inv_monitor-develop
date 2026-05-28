import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import { ParallelConfig } from '../../entities/parallel-config.entity';
import { ParallelStatus } from '../../entities/parallel-status.entity';
import { Device } from '../../entities/device.entity';
import { Alert } from '../../entities/alert.entity';
import {
  CreateParallelGroupDto,
  UpdateParallelGroupDto,
  QueryParallelGroupDto,
  SyncParamsDto,
} from './dto/create-parallel-group.dto';

@Injectable()
export class ParallelService {
  constructor(
    @InjectRepository(ParallelConfig)
    private readonly configRepo: Repository<ParallelConfig>,
    @InjectRepository(ParallelStatus)
    private readonly statusRepo: Repository<ParallelStatus>,
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
    @InjectRepository(Alert)
    private readonly alertRepo: Repository<Alert>,
  ) {}

  async createGroup(dto: CreateParallelGroupDto, userId: number): Promise<ParallelConfig> {
    const master = await this.deviceRepo.findOne({ where: { sn: dto.masterSn } });
    if (!master) {
      throw new BadRequestException(`Master device ${dto.masterSn} not found`);
    }

    const slaveList = dto.slaveSns.split(',').map((s) => s.trim()).filter(Boolean);
    if (slaveList.length === 0) {
      throw new BadRequestException('At least one slave SN is required');
    }
    if (slaveList.length > 8) {
      throw new BadRequestException('Maximum 8 slave devices allowed');
    }

    const existingSlaves = await this.deviceRepo.find({
      where: { sn: In(slaveList) },
    });
    if (existingSlaves.length !== slaveList.length) {
      throw new BadRequestException('One or more slave SNs not found');
    }

    const existingGroup = await this.configRepo.findOne({
      where: { master_sn: dto.masterSn, status: 1 },
    });
    if (existingGroup) {
      throw new BadRequestException(`Master device ${dto.masterSn} is already in an active group`);
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
    } as unknown as ParallelConfig);

    await this.statusRepo.save({
      parallel_id: saved.id,
      device_sn: dto.masterSn,
      role: 'master',
      sync_status: 'synced',
      data_time: new Date(),
    } as unknown as ParallelStatus);

    const statusRows = slaveList.map((sn) => ({
      parallel_id: saved.id,
      device_sn: sn,
      role: 'slave',
      sync_status: 'synced',
      data_time: new Date(),
    } as unknown as ParallelStatus));
    await this.statusRepo.save(statusRows);

    return saved;
  }

  async getAllGroups(query: QueryParallelGroupDto): Promise<{
    items: any[];
    total: number;
    page: number;
    pageSize: number;
  }> {
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

    const enrichedItems = await Promise.all(
      items.map(async (group) => {
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
      }),
    );

    return { items: enrichedItems, total, page, pageSize };
  }

  async getGroupDetail(id: number): Promise<any> {
    const group = await this.configRepo.findOne({ where: { id } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
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

  async updateGroup(id: number, dto: UpdateParallelGroupDto): Promise<ParallelConfig> {
    const group = await this.configRepo.findOne({ where: { id } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
    }

    if (dto.groupName !== undefined) group.group_name = dto.groupName;
    if (dto.phaseConfig !== undefined) group.phase_config = dto.phaseConfig;
    if (dto.masterSn !== undefined) group.master_sn = dto.masterSn;
    if (dto.circulatingCurrentThreshold !== undefined)
      group.circulating_current_threshold = dto.circulatingCurrentThreshold;
    if (dto.loadBalanceDeviation !== undefined)
      group.load_balance_deviation = dto.loadBalanceDeviation;

    if (dto.slaveSns !== undefined) {
      const slaveList = dto.slaveSns.split(',').map((s) => s.trim()).filter(Boolean);
      if (slaveList.length > 8) {
        throw new BadRequestException('Maximum 8 slave devices allowed');
      }

      const oldSlaves = group.slave_sns
        ? group.slave_sns.split(',').map((s) => s.trim()).filter(Boolean)
        : [];
      group.slave_sns = dto.slaveSns;

      const removedSlaves = oldSlaves.filter((s) => !slaveList.includes(s));
      if (removedSlaves.length > 0) {
        await this.statusRepo.delete({
          parallel_id: id,
          device_sn: In(removedSlaves),
          role: 'slave',
        });
      }

      const addedSlaves = slaveList.filter((s) => !oldSlaves.includes(s));
      if (addedSlaves.length > 0) {
        const existingDevices = await this.deviceRepo.find({
          where: { sn: In(addedSlaves) },
        });
        if (existingDevices.length !== addedSlaves.length) {
          throw new BadRequestException('One or more new slave SNs not found');
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

  async deleteGroup(id: number): Promise<void> {
    const group = await this.configRepo.findOne({ where: { id } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
    }
    group.status = 0;
    await this.configRepo.save(group);
  }

  async syncParams(groupId: number, params: SyncParamsDto): Promise<{ message: string; devices: string[] }> {
    const group = await this.configRepo.findOne({ where: { id: groupId } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
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

  async getGroupStatus(id: number): Promise<ParallelStatus[]> {
    return this.statusRepo.find({
      where: { parallel_id: id },
      order: { data_time: 'DESC' },
    });
  }

  async checkCirculatingCurrent(groupId: number): Promise<{
    hasAlert: boolean;
    details: any[];
  }> {
    const group = await this.configRepo.findOne({ where: { id: groupId } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
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

  async getAlertHistory(
    groupId: number,
    query?: { page?: number; pageSize?: number },
  ): Promise<{
    items: Alert[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const group = await this.configRepo.findOne({ where: { id: groupId } });
    if (!group) {
      throw new NotFoundException('Parallel group not found');
    }

    const slaveSns = group.slave_sns
      ? group.slave_sns.split(',').map((s) => s.trim()).filter(Boolean)
      : [];
    const allSns = [group.master_sn, ...slaveSns];

    const page = query?.page ?? 1;
    const pageSize = query?.pageSize ?? 20;

    const [items, total] = await this.alertRepo.findAndCount({
      where: { device_sn: In(allSns) },
      order: { occurred_at: 'DESC' },
      skip: (page - 1) * pageSize,
      take: pageSize,
    });

    return { items, total, page, pageSize };
  }
}
