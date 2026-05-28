export declare const WORK_ORDER_TEMPLATES: {
    templateId: string;
    title: string;
    description: string;
    priority: number;
    defaultFields: string[];
    estimatedHours: number;
}[];
export type WorkOrderTemplate = typeof WORK_ORDER_TEMPLATES[number];
export declare class WorkOrderTemplateService {
    getTemplates(): {
        templateId: string;
        title: string;
        description: string;
        priority: number;
        defaultFields: string[];
        estimatedHours: number;
    }[];
    getTemplate(templateId: string): WorkOrderTemplate | undefined;
}
