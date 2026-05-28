import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Station } from '../../entities/station.entity';
import { Role } from '../../common/enums/role.enum';

interface User {
  id: number;
  role: Role;
}

@Injectable()
export class StationService {
  constructor(
    @InjectRepository(Station)
    private stationRepo: Repository<Station>,
  ) {}

  async findAll(user: User) {
    const qb = this.stationRepo.createQueryBuilder('station')
      .select([
        'station.id', 'station.name', 'station.user_id',
        'station.province', 'station.city', 'station.district',
        'station.address', 'station.capacity', 'station.panel_count',
        'station.latitude', 'station.longitude', 'station.status',
        'station.created_at', 'station.updated_at',
      ])
      .where('station.deleted_at IS NULL')
      .orderBy('station.id', 'DESC');

    if (user.role === Role.END_USER) {
      qb.andWhere('station.user_id = :userId', { userId: user.id });
    } else if (user.role === Role.INSTALLER) {
      qb.andWhere(
        'station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)',
        { userId: user.id },
      );
    }

    const stations = await qb.getMany();
    return stations;
  }

  async assignUser(stationId: number, userId: number) {
    await this.stationRepo.update(stationId, { user_id: userId });
    return { success: true };
  }

  async update(stationId: number, data: Partial<Station>) {
    const allowed: Record<string, any> = { name: data.name, province: data.province, city: data.city, district: data.district, address: data.address, capacity: data.capacity, status: data.status, user_id: data.user_id };
    Object.keys(allowed).forEach(k => { if (allowed[k] === undefined) delete allowed[k]; });
    await this.stationRepo.update(stationId, allowed);
    return { success: true };
  }
}
