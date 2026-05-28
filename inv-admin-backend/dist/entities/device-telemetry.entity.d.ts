export declare class DeviceTelemetry {
    id: number;
    device_sn: string;
    model_code: string;
    topic: string;
    data: Record<string, unknown>;
    total_active_power: number;
    daily_energy: number;
    work_state: string;
    fault_code: string;
    internal_temperature: number;
    time: Date;
    created_at: Date;
}
