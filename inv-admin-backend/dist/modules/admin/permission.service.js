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
exports.PermissionService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const permission_entity_1 = require("../../entities/permission.entity");
const default_permissions_1 = require("../../common/permissions/default-permissions");
let PermissionService = class PermissionService {
    constructor(repo) {
        this.repo = repo;
    }
    async seedDefaults() {
        for (const role of [0, 1, 2, 3]) {
            const defaults = default_permissions_1.DEFAULT_ROLE_PERMISSIONS[role];
            for (const perm of defaults) {
                const existing = await this.repo.findOne({
                    where: { role, resource: perm.resource, action: perm.action },
                });
                if (!existing) {
                    await this.repo.save(this.repo.create({
                        role,
                        resource: perm.resource,
                        action: perm.action,
                        is_allowed: true,
                    }));
                }
            }
        }
    }
    async getRolePermissions(role) {
        return this.repo.find({ where: { role } });
    }
    async getAllPermissionsConfig() {
        const all = await this.repo.find();
        const config = {};
        for (const row of all) {
            if (!config[row.role])
                config[row.role] = {};
            if (!config[row.role][row.resource])
                config[row.role][row.resource] = [];
            if (row.is_allowed)
                config[row.role][row.resource].push(row.action);
        }
        return config;
    }
    async hasPermission(role, resource, action) {
        if (role === 0)
            return true;
        const perm = await this.repo.findOne({ where: { role, resource, action } });
        return !!perm && perm.is_allowed;
    }
    async setPermission(role, resource, action, isAllowed) {
        const perm = await this.repo.findOne({ where: { role, resource, action } });
        if (perm) {
            perm.is_allowed = isAllowed;
            return this.repo.save(perm);
        }
        return this.repo.save(this.repo.create({ role, resource, action, is_allowed: isAllowed }));
    }
    async batchUpdatePermissions(role, permissions) {
        for (const p of permissions) {
            await this.setPermission(role, p.resource, p.action, p.is_allowed);
        }
    }
};
exports.PermissionService = PermissionService;
exports.PermissionService = PermissionService = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(permission_entity_1.RolePermission)),
    __metadata("design:paramtypes", [typeorm_2.Repository])
], PermissionService);
//# sourceMappingURL=permission.service.js.map