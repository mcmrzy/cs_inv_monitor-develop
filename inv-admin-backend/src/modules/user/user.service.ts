import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In, Not, IsNull } from 'typeorm';
import * as bcrypt from 'bcryptjs';
import { User } from '../../entities/user.entity';
import { CreateUserDto, UpdateUserDto, QueryUserDto } from './dto/create-user.dto';
import { Role } from '../../common/enums/role.enum';

@Injectable()
export class UserService {
  constructor(
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
  ) {}

  private getRoleName(role: number): string {
    const map: Record<number, string> = {
      [Role.SUPER_ADMIN]: 'SUPER_ADMIN',
      [Role.AGENT]: 'AGENT',
      [Role.INSTALLER]: 'INSTALLER',
      [Role.END_USER]: 'END_USER',
    };
    return map[role] ?? 'UNKNOWN';
  }

  private canManageRole(managerRole: number, targetRole: number): boolean {
    switch (managerRole) {
      case Role.SUPER_ADMIN:
        return true;
      case Role.AGENT:
        return targetRole === Role.INSTALLER || targetRole === Role.END_USER;
      case Role.INSTALLER:
        return targetRole === Role.END_USER;
      default:
        return false;
    }
  }

  private isDescendantOf(targetParentId: number | null, ancestorId: number): boolean {
    return targetParentId === ancestorId;
  }

  async create(dto: CreateUserDto, createdBy: any): Promise<User> {
    const creatorRole = createdBy.role;
    const creatorId = createdBy.id ?? createdBy.sub;

    if (!this.canManageRole(creatorRole, dto.role)) {
      throw new ForbiddenException(
        `Role ${this.getRoleName(creatorRole)} cannot create users with role ${this.getRoleName(dto.role)}`,
      );
    }

    if (dto.parentId !== undefined && dto.parentId !== null) {
      const parent = await this.userRepo.findOne({ where: { id: dto.parentId } });
      if (!parent) {
        throw new BadRequestException('Parent user not found');
      }
      if (!this.canManageRole(creatorRole, parent.role)) {
        throw new ForbiddenException('Cannot assign this parent user');
      }
    }

    let parentId = dto.parentId ?? null;
    if (parentId === undefined) {
      parentId = creatorId;
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);

    const user = this.userRepo.create({
      phone: dto.phone ?? '',
      email: dto.email ?? null,
      password_hash: passwordHash,
      nickname: dto.nickname ?? null,
      role: dto.role,
      parent_id: parentId,
      status: 1,
    });

    const saved = await this.userRepo.save(user);
    return saved as User;
  }

  async findAll(query: QueryUserDto, currentUser: any): Promise<{
    items: User[];
    total: number;
    page: number;
    pageSize: number;
  }> {
    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;
    const skip = (page - 1) * pageSize;

    const qb = this.userRepo.createQueryBuilder('u');

    switch (currentUser.role) {
      case Role.SUPER_ADMIN:
        break;
      case Role.AGENT: {
        const subUserIds = await this.getSubUserIds(currentUser.id ?? currentUser.sub);
        subUserIds.push(currentUser.id ?? currentUser.sub);
        qb.andWhere('u.id IN (:...ids)', { ids: subUserIds });
        break;
      }
      case Role.INSTALLER: {
        const subUserIds = await this.getSubUserIds(currentUser.id ?? currentUser.sub);
        subUserIds.push(currentUser.id ?? currentUser.sub);
        qb.andWhere('u.id IN (:...ids)', { ids: subUserIds });
        break;
      }
      case Role.END_USER:
        qb.andWhere('u.id = :userId', { userId: currentUser.id ?? currentUser.sub });
        break;
    }

    if (query.keyword) {
      qb.andWhere(
        '(u.phone ILIKE :kw OR u.email ILIKE :kw OR u.nickname ILIKE :kw)',
        { kw: `%${query.keyword}%` },
      );
    }

    if (query.role !== undefined) {
      qb.andWhere('u.role = :role', { role: query.role });
    }

    qb.skip(skip).take(pageSize).orderBy('u.created_at', 'DESC');

    const [items, total] = await qb.getManyAndCount();

    return { items, total, page, pageSize };
  }

  async findById(id: number, currentUser: any): Promise<User> {
    const user = await this.userRepo.findOne({ where: { id } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const currentUserId = currentUser.id ?? currentUser.sub;

    if (currentUser.role !== Role.SUPER_ADMIN) {
      if (currentUser.role === Role.END_USER && user.id !== currentUserId) {
        throw new ForbiddenException('Access denied');
      }
      if (currentUser.role === Role.AGENT || currentUser.role === Role.INSTALLER) {
        const subUserIds = await this.getSubUserIds(currentUserId);
        subUserIds.push(currentUserId);
        if (!subUserIds.includes(user.id)) {
          throw new ForbiddenException('Access denied');
        }
      }
    }

    return user;
  }

  async update(id: number, dto: UpdateUserDto, currentUser: any): Promise<User> {
    const user = await this.findById(id, currentUser);

    if (dto.role !== undefined && dto.role !== user.role) {
      if (!this.canManageRole(currentUser.role, dto.role)) {
        throw new ForbiddenException('Cannot change role to this level');
      }
    }

    if (dto.parentId !== undefined) {
      const parent = await this.userRepo.findOne({ where: { id: dto.parentId } });
      if (!parent) {
        throw new BadRequestException('Parent user not found');
      }
      user.parent_id = dto.parentId;
    }

    if (dto.phone !== undefined) user.phone = dto.phone;
    if (dto.email !== undefined) user.email = dto.email;
    if (dto.nickname !== undefined) user.nickname = dto.nickname;
    if (dto.role !== undefined) user.role = dto.role;
    if (dto.regionId !== undefined) user.region_id = dto.regionId;
    if (dto.status !== undefined) user.status = dto.status;

    return this.userRepo.save(user);
  }

  async disable(id: number): Promise<void> {
    const user = await this.userRepo.findOne({ where: { id } });
    if (!user) {
      throw new NotFoundException('User not found');
    }
    user.status = 0;
    await this.userRepo.save(user);
  }

  async resetPassword(id: number, newPassword: string): Promise<void> {
    const user = await this.userRepo.findOne({ where: { id } });
    if (!user) {
      throw new NotFoundException('User not found');
    }
    user.password_hash = await bcrypt.hash(newPassword, 12);
    await this.userRepo.save(user);
  }

  async getSubUserIds(userId: number): Promise<number[]> {
    const result: number[] = [];
    const children = await this.userRepo.find({
      where: { parent_id: userId },
      select: ['id'],
    });

    for (const child of children) {
      result.push(child.id);
      const grandChildren = await this.getSubUserIds(child.id);
      result.push(...grandChildren);
    }

    return result;
  }
}
