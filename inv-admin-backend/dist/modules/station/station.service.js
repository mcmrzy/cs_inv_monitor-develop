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
exports.StationService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const station_entity_1 = require("../../entities/station.entity");
const role_enum_1 = require("../../common/enums/role.enum");
let StationService = class StationService {
    constructor(stationRepo) {
        this.stationRepo = stationRepo;
    }
    async findAll(user) {
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
        if (user.role === role_enum_1.Role.END_USER) {
            qb.andWhere('station.user_id = :userId', { userId: user.id });
        }
        else if (user.role === role_enum_1.Role.INSTALLER) {
            qb.andWhere('station.user_id IN (SELECT u.id FROM users u WHERE u.parent_id = :userId OR u.id = :userId)', { userId: user.id });
        }
        const stations = await qb.getMany();
        return stations;
    }
    async assignUser(stationId, userId) {
        await this.stationRepo.update(stationId, { user_id: userId });
        return { success: true };
    }
    async update(stationId, data) {
        const allowed = { name: data.name, province: data.province, city: data.city, district: data.district, address: data.address, capacity: data.capacity, status: data.status, user_id: data.user_id };
        Object.keys(allowed).forEach(k => { if (allowed[k] === undefined)
            delete allowed[k]; });
        await this.stationRepo.update(stationId, allowed);
        return { success: true };
    }
};
exports.StationService = StationService;
exports.StationService = StationService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(station_entity_1.Station)),
    __metadata("design:paramtypes", [typeorm_2.Repository])
], StationService);
//# sourceMappingURL=station.service.js.map