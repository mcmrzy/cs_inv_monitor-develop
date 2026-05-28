"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.OtaModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const firmware_entity_1 = require("../../entities/firmware.entity");
const ota_task_entity_1 = require("../../entities/ota-task.entity");
const ota_task_device_entity_1 = require("../../entities/ota-task-device.entity");
const device_entity_1 = require("../../entities/device.entity");
const ota_service_1 = require("./ota.service");
const ota_controller_1 = require("./ota.controller");
let OtaModule = class OtaModule {
};
exports.OtaModule = OtaModule;
exports.OtaModule = OtaModule = __decorate([
    (0, common_1.Module)({
        imports: [typeorm_1.TypeOrmModule.forFeature([firmware_entity_1.Firmware, ota_task_entity_1.OtaTask, ota_task_device_entity_1.OtaTaskDevice, device_entity_1.Device])],
        providers: [ota_service_1.OtaService],
        controllers: [ota_controller_1.OtaController],
    })
], OtaModule);
//# sourceMappingURL=ota.module.js.map