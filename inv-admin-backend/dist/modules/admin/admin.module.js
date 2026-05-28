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
exports.AdminModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const audit_log_entity_1 = require("../../entities/audit-log.entity");
const user_entity_1 = require("../../entities/user.entity");
const device_entity_1 = require("../../entities/device.entity");
const station_entity_1 = require("../../entities/station.entity");
const system_config_entity_1 = require("../../entities/system-config.entity");
const permission_entity_1 = require("../../entities/permission.entity");
const admin_service_1 = require("./admin.service");
const permission_service_1 = require("./permission.service");
const geo_location_service_1 = require("./geo-location.service");
const admin_controller_1 = require("./admin.controller");
const metrics_controller_1 = require("./metrics.controller");
const health_controller_1 = require("./health.controller");
const prometheus_metrics_1 = require("../../common/metrics/prometheus.metrics");
let AdminModule = class AdminModule {
    constructor(permissionService) {
        this.permissionService = permissionService;
    }
    async onModuleInit() {
        await this.permissionService.seedDefaults();
    }
};
exports.AdminModule = AdminModule;
exports.AdminModule = AdminModule = __decorate([
    (0, common_1.Global)(),
    (0, common_1.Module)({
        imports: [typeorm_1.TypeOrmModule.forFeature([audit_log_entity_1.AuditLog, user_entity_1.User, device_entity_1.Device, station_entity_1.Station, system_config_entity_1.SystemConfig, permission_entity_1.RolePermission])],
        controllers: [admin_controller_1.AdminController, metrics_controller_1.MetricsController, health_controller_1.HealthController],
        providers: [admin_service_1.AdminService, permission_service_1.PermissionService, geo_location_service_1.GeoLocationService, prometheus_metrics_1.PrometheusMetrics],
        exports: [prometheus_metrics_1.PrometheusMetrics, permission_service_1.PermissionService],
    }),
    __metadata("design:paramtypes", [permission_service_1.PermissionService])
], AdminModule);
//# sourceMappingURL=admin.module.js.map