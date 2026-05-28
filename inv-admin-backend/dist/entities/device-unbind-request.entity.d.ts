export declare class DeviceUnbindRequest {
    id: number;
    device_sn: string;
    requested_by: number;
    reason: string | null;
    status: string;
    reviewed_by: number | null;
    review_comment: string | null;
    reviewed_at: Date;
    created_at: Date;
}
