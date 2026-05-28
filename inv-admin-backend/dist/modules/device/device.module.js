"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.DeviceModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const device_entity_1 = require("../../entities/device.entity");
const device_telemetry_entity_1 = require("../../entities/device-telemetry.entity");
const device_unbind_request_entity_1 = require("../../entities/device-unbind-request.entity");
const device_lifecycle_entity_1 = require("../../entities/device-lifecycle.entity");
const command_log_entity_1 = require("../../entities/command-log.entity");
const station_entity_1 = require("../../entities/station.entity");
const user_entity_1 = require("../../entities/user.entity");
const device_service_1 = require("./device.service");
const excel_import_service_1 = require("./excel-import.service");
const command_execution_service_1 = require("./command-execution.service");
const device_server_proxy_service_1 = require("./device-server-proxy.service");
const device_controller_1 = require("./device.controller");
const re_auth_guard_1 = require("../../common/guards/re-auth.guard");
let DeviceModule = class DeviceModule {
};
exports.DeviceModule = DeviceModule;
exports.DeviceModule = DeviceModule = __decorate([
    (0, common_1.Module)({
        imports: [
            typeorm_1.TypeOrmModule.forFeature([
                device_entity_1.Device,
                device_telemetry_entity_1.DeviceTelemetry,
                device_unbind_request_entity_1.DeviceUnbindRequest,
                device_lifecycle_entity_1.DeviceLifecycle,
                command_log_entity_1.CommandLog,
                station_entity_1.Station,
                user_entity_1.User,
            ]),
        ],
        providers: [device_service_1.DeviceService, excel_import_service_1.ExcelImportService, command_execution_service_1.CommandExecutionService, device_server_proxy_service_1.DeviceServerProxyService, re_auth_guard_1.ReAuthGuard],
        controllers: [device_controller_1.DeviceController],
    })
], DeviceModule);
//# sourceMappingURL=device.module.js.map