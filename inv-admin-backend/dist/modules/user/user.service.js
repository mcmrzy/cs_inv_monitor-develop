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
exports.UserService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const bcrypt = require("bcryptjs");
const user_entity_1 = require("../../entities/user.entity");
const role_enum_1 = require("../../common/enums/role.enum");
let UserService = class UserService {
    constructor(userRepo) {
        this.userRepo = userRepo;
    }
    getRoleName(role) {
        const map = {
            [role_enum_1.Role.SUPER_ADMIN]: 'SUPER_ADMIN',
            [role_enum_1.Role.AGENT]: 'AGENT',
            [role_enum_1.Role.INSTALLER]: 'INSTALLER',
            [role_enum_1.Role.END_USER]: 'END_USER',
        };
        return map[role] ?? 'UNKNOWN';
    }
    canManageRole(managerRole, targetRole) {
        switch (managerRole) {
            case role_enum_1.Role.SUPER_ADMIN:
                return true;
            case role_enum_1.Role.AGENT:
                return targetRole === role_enum_1.Role.INSTALLER || targetRole === role_enum_1.Role.END_USER;
            case role_enum_1.Role.INSTALLER:
                return targetRole === role_enum_1.Role.END_USER;
            default:
                return false;
        }
    }
    isDescendantOf(targetParentId, ancestorId) {
        return targetParentId === ancestorId;
    }
    async create(dto, createdBy) {
        const creatorRole = createdBy.role;
        const creatorId = createdBy.id ?? createdBy.sub;
        if (!this.canManageRole(creatorRole, dto.role)) {
            throw new common_1.ForbiddenException(`Role ${this.getRoleName(creatorRole)} cannot create users with role ${this.getRoleName(dto.role)}`);
        }
        if (dto.parentId !== undefined && dto.parentId !== null) {
            const parent = await this.userRepo.findOne({ where: { id: dto.parentId } });
            if (!parent) {
                throw new common_1.BadRequestException('Parent user not found');
            }
            if (!this.canManageRole(creatorRole, parent.role)) {
                throw new common_1.ForbiddenException('Cannot assign this parent user');
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
        return saved;
    }
    async findAll(query, currentUser) {
        const page = query.page ?? 1;
        const pageSize = query.pageSize ?? 20;
        const skip = (page - 1) * pageSize;
        const qb = this.userRepo.createQueryBuilder('u');
        switch (currentUser.role) {
            case role_enum_1.Role.SUPER_ADMIN:
                break;
            case role_enum_1.Role.AGENT: {
                const subUserIds = await this.getSubUserIds(currentUser.id ?? currentUser.sub);
                subUserIds.push(currentUser.id ?? currentUser.sub);
                qb.andWhere('u.id IN (:...ids)', { ids: subUserIds });
                break;
            }
            case role_enum_1.Role.INSTALLER: {
                const subUserIds = await this.getSubUserIds(currentUser.id ?? currentUser.sub);
                subUserIds.push(currentUser.id ?? currentUser.sub);
                qb.andWhere('u.id IN (:...ids)', { ids: subUserIds });
                break;
            }
            case role_enum_1.Role.END_USER:
                qb.andWhere('u.id = :userId', { userId: currentUser.id ?? currentUser.sub });
                break;
        }
        if (query.keyword) {
            qb.andWhere('(u.phone ILIKE :kw OR u.email ILIKE :kw OR u.nickname ILIKE :kw)', { kw: `%${query.keyword}%` });
        }
        if (query.role !== undefined) {
            qb.andWhere('u.role = :role', { role: query.role });
        }
        qb.skip(skip).take(pageSize).orderBy('u.created_at', 'DESC');
        const [items, total] = await qb.getManyAndCount();
        return { items, total, page, pageSize };
    }
    async findById(id, currentUser) {
        const user = await this.userRepo.findOne({ where: { id } });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const currentUserId = currentUser.id ?? currentUser.sub;
        if (currentUser.role !== role_enum_1.Role.SUPER_ADMIN) {
            if (currentUser.role === role_enum_1.Role.END_USER && user.id !== currentUserId) {
                throw new common_1.ForbiddenException('Access denied');
            }
            if (currentUser.role === role_enum_1.Role.AGENT || currentUser.role === role_enum_1.Role.INSTALLER) {
                const subUserIds = await this.getSubUserIds(currentUserId);
                subUserIds.push(currentUserId);
                if (!subUserIds.includes(user.id)) {
                    throw new common_1.ForbiddenException('Access denied');
                }
            }
        }
        return user;
    }
    async update(id, dto, currentUser) {
        const user = await this.findById(id, currentUser);
        if (dto.role !== undefined && dto.role !== user.role) {
            if (!this.canManageRole(currentUser.role, dto.role)) {
                throw new common_1.ForbiddenException('Cannot change role to this level');
            }
        }
        if (dto.parentId !== undefined) {
            const parent = await this.userRepo.findOne({ where: { id: dto.parentId } });
            if (!parent) {
                throw new common_1.BadRequestException('Parent user not found');
            }
            user.parent_id = dto.parentId;
        }
        if (dto.phone !== undefined)
            user.phone = dto.phone;
        if (dto.email !== undefined)
            user.email = dto.email;
        if (dto.nickname !== undefined)
            user.nickname = dto.nickname;
        if (dto.role !== undefined)
            user.role = dto.role;
        if (dto.regionId !== undefined)
            user.region_id = dto.regionId;
        if (dto.status !== undefined)
            user.status = dto.status;
        return this.userRepo.save(user);
    }
    async disable(id) {
        const user = await this.userRepo.findOne({ where: { id } });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        user.status = 0;
        await this.userRepo.save(user);
    }
    async resetPassword(id, newPassword) {
        const user = await this.userRepo.findOne({ where: { id } });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        user.password_hash = await bcrypt.hash(newPassword, 12);
        await this.userRepo.save(user);
    }
    async getSubUserIds(userId) {
        const result = [];
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
};
exports.UserService = UserService;
exports.UserService = UserService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __metadata("design:paramtypes", [typeorm_2.Repository])
], UserService);
//# sourceMappingURL=user.service.js.map