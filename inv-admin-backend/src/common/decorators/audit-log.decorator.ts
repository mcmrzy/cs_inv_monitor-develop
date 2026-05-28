import { SetMetadata } from '@nestjs/common';

export const AUDIT_LOG_KEY = 'audit_log';

export interface AuditLogMeta {
  action: string;
  resource: string;
}

export const AuditLog = (meta: AuditLogMeta) =>
  SetMetadata(AUDIT_LOG_KEY, meta);
