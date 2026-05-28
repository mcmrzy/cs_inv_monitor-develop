"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.WorkOrderTemplateService = exports.WORK_ORDER_TEMPLATES = void 0;
const common_1 = require("@nestjs/common");
exports.WORK_ORDER_TEMPLATES = [
    {
        templateId: 'installation',
        title: '设备安装工单',
        description: '新设备安装调试',
        priority: 2,
        defaultFields: ['device_sn', 'station_id', 'installer_id'],
        estimatedHours: 4,
    },
    {
        templateId: 'repair',
        title: '设备维修工单',
        description: '设备故障维修',
        priority: 3,
        defaultFields: ['device_sn', 'fault_description'],
        estimatedHours: 8,
    },
    {
        templateId: 'inspection',
        title: '设备巡检工单',
        description: '定期设备巡检维护',
        priority: 1,
        defaultFields: ['station_id'],
        estimatedHours: 2,
    },
    {
        templateId: 'maintenance',
        title: '预防性维护工单',
        description: '设备预防性维护保养',
        priority: 2,
        defaultFields: ['device_sn', 'maintenance_items'],
        estimatedHours: 6,
    },
];
let WorkOrderTemplateService = class WorkOrderTemplateService {
    getTemplates() {
        return exports.WORK_ORDER_TEMPLATES;
    }
    getTemplate(templateId) {
        return exports.WORK_ORDER_TEMPLATES.find((t) => t.templateId === templateId);
    }
};
exports.WorkOrderTemplateService = WorkOrderTemplateService;
exports.WorkOrderTemplateService = WorkOrderTemplateService = __decorate([
    (0, common_1.Injectable)()
], WorkOrderTemplateService);
//# sourceMappingURL=work-order-template.service.js.map