export declare enum WorkOrderPriority {
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    URGENT = 4
}
export declare enum WorkOrderStatus {
    OPEN = "open",
    IN_PROGRESS = "in_progress",
    RESOLVED = "resolved",
    CLOSED = "closed"
}
export declare class WorkOrder {
    id: string;
    title: string;
    description: string;
    device_sn: string;
    station_id: number;
    created_by: number;
    assigned_to: number;
    priority: number;
    status: WorkOrderStatus;
    resolution: string;
    created_at: Date;
    updated_at: Date;
    resolved_at: Date;
    template_type: string | null;
    sla_deadline: Date | null;
    sla_overdue_count: number;
    attachments: {
        name: string;
        url: string;
        type: string;
        uploadedAt: string;
    }[] | null;
}
