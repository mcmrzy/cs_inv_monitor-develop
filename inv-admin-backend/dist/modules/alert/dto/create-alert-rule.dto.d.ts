export declare class CreateAlertRuleDto {
    name: string;
    field_name: string;
    operator: string;
    threshold_value: number;
    alarm_level?: number;
    fault_code: string;
    fault_message: string;
    device_model?: string;
    is_active?: boolean;
    cooldown_minutes?: number;
}
