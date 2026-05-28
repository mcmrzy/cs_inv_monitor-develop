export declare const AUDIT_LOG_KEY = "audit_log";
export interface AuditLogMeta {
    action: string;
    resource: string;
}
export declare const AuditLog: (meta: AuditLogMeta) => import("@nestjs/common").CustomDecorator<string>;
