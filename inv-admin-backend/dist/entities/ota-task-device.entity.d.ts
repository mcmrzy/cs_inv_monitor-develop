export declare enum OtaTaskDeviceStatus {
    PENDING = "pending",
    DOWNLOADING = "downloading",
    INSTALLING = "installing",
    SUCCESS = "success",
    FAILED = "failed"
}
export declare class OtaTaskDevice {
    id: number;
    task_id: string;
    device_sn: string;
    old_version: string | null;
    new_version: string | null;
    status: OtaTaskDeviceStatus;
    progress: number;
    error_message: string | null;
    started_at: Date | null;
    completed_at: Date | null;
    mqtt_message: string | null;
    created_at: Date;
}
