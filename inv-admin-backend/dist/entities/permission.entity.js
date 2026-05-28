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
Object.defineProperty(exports, "__esModule", { value: true });
exports.RolePermission = exports.PermissionResource = exports.PermissionAction = void 0;
const typeorm_1 = require("typeorm");
var PermissionAction;
(function (PermissionAction) {
    PermissionAction["VIEW"] = "view";
    PermissionAction["CREATE"] = "create";
    PermissionAction["EDIT"] = "edit";
    PermissionAction["DELETE"] = "delete";
    PermissionAction["EXPORT"] = "export";
    PermissionAction["CONTROL"] = "control";
    PermissionAction["MANAGE"] = "manage";
})(PermissionAction || (exports.PermissionAction = PermissionAction = {}));
var PermissionResource;
(function (PermissionResource) {
    PermissionResource["DEVICES"] = "devices";
    PermissionResource["USERS"] = "users";
    PermissionResource["ALERTS"] = "alerts";
    PermissionResource["WORK_ORDERS"] = "work_orders";
    PermissionResource["OTA"] = "ota";
    PermissionResource["STATIONS"] = "stations";
    PermissionResource["DASHBOARD"] = "dashboard";
    PermissionResource["PARALLEL"] = "parallel";
    PermissionResource["ADMIN"] = "admin";
    PermissionResource["AUDIT"] = "audit";
    PermissionResource["ALERT_RULES"] = "alert_rules";
    PermissionResource["FIRMWARE"] = "firmware";
})(PermissionResource || (exports.PermissionResource = PermissionResource = {}));
let RolePermission = class RolePermission {
};
exports.RolePermission = RolePermission;
__decorate([
    (0, typeorm_1.PrimaryGeneratedColumn)({ type: 'bigint' }),
    __metadata("design:type", Number)
], RolePermission.prototype, "id", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'smallint' }),
    __metadata("design:type", Number)
], RolePermission.prototype, "role", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50 }),
    __metadata("design:type", String)
], RolePermission.prototype, "resource", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'varchar', length: 50 }),
    __metadata("design:type", String)
], RolePermission.prototype, "action", void 0);
__decorate([
    (0, typeorm_1.Column)({ type: 'boolean', default: true, name: 'is_allowed' }),
    __metadata("design:type", Boolean)
], RolePermission.prototype, "is_allowed", void 0);
__decorate([
    (0, typeorm_1.UpdateDateColumn)({ type: 'timestamp', name: 'updated_at' }),
    __metadata("design:type", Date)
], RolePermission.prototype, "updated_at", void 0);
exports.RolePermission = RolePermission = __decorate([
    (0, typeorm_1.Entity)('role_permissions'),
    (0, typeorm_1.Index)('idx_permissions_role', ['role']),
    (0, typeorm_1.Index)('uq_role_resource_action', ['role', 'resource', 'action'], { unique: true })
], RolePermission);
//# sourceMappingURL=permission.entity.js.map