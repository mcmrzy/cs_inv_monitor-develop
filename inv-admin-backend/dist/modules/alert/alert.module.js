"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertModule = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const alert_entity_1 = require("../../entities/alert.entity");
const work_order_entity_1 = require("../../entities/work-order.entity");
const device_entity_1 = require("../../entities/device.entity");
const alert_rule_entity_1 = require("../../entities/alert-rule.entity");
const alert_notification_entity_1 = require("../../entities/alert-notification.entity");
const user_entity_1 = require("../../entities/user.entity");
const alert_service_1 = require("./alert.service");
const alert_controller_1 = require("./alert.controller");
const work_order_controller_1 = require("./work-order.controller");
const alert_rule_service_1 = require("./alert-rule.service");
const alert_rule_controller_1 = require("./alert-rule.controller");
const alert_notification_service_1 = require("./alert-notification.service");
const sla_engine_service_1 = require("./sla-engine.service");
const work_order_template_service_1 = require("./work-order-template.service");
const sla_cron_service_1 = require("./sla-cron.service");
const websocket_module_1 = require("../websocket/websocket.module");
let AlertModule = class AlertModule {
};
exports.AlertModule = AlertModule;
exports.AlertModule = AlertModule = __decorate([
    (0, common_1.Module)({
        imports: [
            typeorm_1.TypeOrmModule.forFeature([alert_entity_1.Alert, work_order_entity_1.WorkOrder, device_entity_1.Device, alert_rule_entity_1.AlertRule, alert_notification_entity_1.AlertNotification, user_entity_1.User]),
            websocket_module_1.WebSocketModule,
        ],
        controllers: [alert_controller_1.AlertController, work_order_controller_1.WorkOrderController, alert_rule_controller_1.AlertRuleController],
        providers: [alert_service_1.AlertService, alert_rule_service_1.AlertRuleService, alert_notification_service_1.AlertNotificationService, sla_engine_service_1.SlaEngineService, work_order_template_service_1.WorkOrderTemplateService, sla_cron_service_1.SlaCronService],
        exports: [alert_service_1.AlertService, alert_rule_service_1.AlertRuleService, alert_notification_service_1.AlertNotificationService, sla_engine_service_1.SlaEngineService],
    })
], AlertModule);
//# sourceMappingURL=alert.module.js.map