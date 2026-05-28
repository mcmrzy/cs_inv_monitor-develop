export declare enum OtaTaskStatus {
    PENDING = "pending",
    PUSHING = "pushing",
    IN_PROGRESS = "in_progress",
    COMPLETED = "completed",
    FAILED = "failed",
    CANCELLED = "cancelled",
    ROLLED_BACK = "rolled_back"
}
export declare class OtaTask {
    id: string;
    name: string;
    firmware_id: number;
    created_by: number;
    status: OtaTaskStatus;
    total_devices: number;
    success_count: number;
    failed_count: number;
    push_strategy: string;
    push_percentage: number;
    batch_size: number;
    created_at: Date;
    updated_at: Date;
}
