export declare class AuditLog {
    id: number;
    user_id: number;
    username: string;
    action: string;
    resource: string;
    resource_id: string;
    details: Record<string, unknown>;
    ip_address: string;
    created_at: Date;
}
