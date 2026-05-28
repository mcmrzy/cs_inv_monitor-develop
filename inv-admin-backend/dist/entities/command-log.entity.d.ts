export declare class CommandLog {
    id: number;
    device_sn: string;
    command_name: string;
    command_label: string;
    params: any;
    req_id: string;
    status: string;
    result_message: string;
    executed_by: number;
    ip_address: string;
    retry_count: number;
    created_at: Date;
    completed_at: Date;
}
