"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ParallelModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const parallel_config_entity_1 = require("../../entities/parallel-config.entity");
const parallel_status_entity_1 = require("../../entities/parallel-status.entity");
const device_entity_1 = require("../../entities/device.entity");
const alert_entity_1 = require("../../entities/alert.entity");
const parallel_service_1 = require("./parallel.service");
const parallel_controller_1 = require("./parallel.controller");
let ParallelModule = class ParallelModule {
};
exports.ParallelModule = ParallelModule;
exports.ParallelModule = ParallelModule = __decorate([
    (0, common_1.Module)({
        imports: [
            typeorm_1.TypeOrmModule.forFeature([parallel_config_entity_1.ParallelConfig, parallel_status_entity_1.ParallelStatus, device_entity_1.Device, alert_entity_1.Alert]),
        ],
        controllers: [parallel_controller_1.ParallelController],
        providers: [parallel_service_1.ParallelService],
        exports: [parallel_service_1.ParallelService],
    })
], ParallelModule);
//# sourceMappingURL=parallel.module.js.map