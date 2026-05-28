"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AppModule = void 0;
const common_1 = require("@nestjs/common");
const core_1 = require("@nestjs/core");
const typeorm_1 = require("@nestjs/typeorm");
const config_1 = require("@nestjs/config");
const schedule_1 = require("@nestjs/schedule");
const database_config_1 = require("./config/database.config");
const audit_log_entity_1 = require("./entities/audit-log.entity");
const permission_entity_1 = require("./entities/permission.entity");
const alert_module_1 = require("./modules/alert/alert.module");
const dashboard_module_1 = require("./modules/dashboard/dashboard.module");
const admin_module_1 = require("./modules/admin/admin.module");
const websocket_module_1 = require("./modules/websocket/websocket.module");
const auth_module_1 = require("./modules/auth/auth.module");
const user_module_1 = require("./modules/user/user.module");
const device_module_1 = require("./modules/device/device.module");
const ota_module_1 = require("./modules/ota/ota.module");
const parallel_module_1 = require("./modules/parallel/parallel.module");
const station_module_1 = require("./modules/station/station.module");
const http_exception_filter_1 = require("./common/filters/http-exception.filter");
const transform_interceptor_1 = require("./common/interceptors/transform.interceptor");
const audit_log_interceptor_1 = require("./common/interceptors/audit-log.interceptor");
const metrics_interceptor_1 = require("./common/interceptors/metrics.interceptor");
let AppModule = class AppModule {
};
exports.AppModule = AppModule;
exports.AppModule = AppModule = __decorate([
    (0, common_1.Module)({
        imports: [
            config_1.ConfigModule.forRoot({
                isGlobal: true,
            }),
            schedule_1.ScheduleModule.forRoot(),
            typeorm_1.TypeOrmModule.forRoot(database_config_1.databaseConfig),
            typeorm_1.TypeOrmModule.forFeature([audit_log_entity_1.AuditLog, permission_entity_1.RolePermission]),
            alert_module_1.AlertModule,
            dashboard_module_1.DashboardModule,
            admin_module_1.AdminModule,
            websocket_module_1.WebSocketModule,
            auth_module_1.AuthModule,
            user_module_1.UserModule,
            device_module_1.DeviceModule,
            ota_module_1.OtaModule,
            parallel_module_1.ParallelModule,
            station_module_1.StationModule,
        ],
        providers: [
            {
                provide: core_1.APP_FILTER,
                useClass: http_exception_filter_1.HttpExceptionFilter,
            },
            {
                provide: core_1.APP_INTERCEPTOR,
                useClass: transform_interceptor_1.TransformInterceptor,
            },
            {
                provide: core_1.APP_INTERCEPTOR,
                useClass: audit_log_interceptor_1.AuditLogInterceptor,
            },
            {
                provide: core_1.APP_INTERCEPTOR,
                useClass: metrics_interceptor_1.MetricsInterceptor,
            },
        ],
    })
], AppModule);
//# sourceMappingURL=app.module.js.map