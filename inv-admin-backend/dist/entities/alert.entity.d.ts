export declare class Alert {
    id: number;
    device_sn: string;
    station_id: number;
    user_id: number;
    alarm_level: number;
    fault_code: string;
    fault_message: string;
    fault_detail: string;
    status: number;
    occurred_at: Date;
    recovered_at: Date;
    handled_at: Date;
    handled_by: number;
    created_at: Date;
}
