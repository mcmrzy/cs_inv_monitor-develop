import { Injectable } from '@nestjs/common';

export const WORK_ORDER_TEMPLATES = [
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

export type WorkOrderTemplate = typeof WORK_ORDER_TEMPLATES[number];

@Injectable()
export class WorkOrderTemplateService {
  getTemplates() {
    return WORK_ORDER_TEMPLATES;
  }

  getTemplate(templateId: string): WorkOrderTemplate | undefined {
    return WORK_ORDER_TEMPLATES.find((t) => t.templateId === templateId);
  }
}
