import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Observable } from 'rxjs';
import { tap, catchError } from 'rxjs/operators';
import { AuditLog } from '@entities/audit-log.entity';
import { AUDIT_LOG_KEY, AuditLogMeta } from '@common/decorators/audit-log.decorator';

const MAX_BODY_LENGTH = 1000;

@Injectable()
export class AuditLogInterceptor implements NestInterceptor {
  constructor(
    @InjectRepository(AuditLog)
    private auditLogRepo: Repository<AuditLog>,
    private reflector: Reflector,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const auditLogMeta = this.reflector.get<AuditLogMeta>(
      AUDIT_LOG_KEY,
      context.getHandler(),
    );

    if (!auditLogMeta) {
      return next.handle();
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user as Record<string, unknown> | undefined;

    return next.handle().pipe(
      tap(() => {
        this.createAuditLog(auditLogMeta, request, user, false).catch(() => {});
      }),
      catchError((error: Error) => {
        this.createAuditLog(
          { ...auditLogMeta, action: `${auditLogMeta.action}_FAILED` },
          request,
          user,
          true,
        ).catch(() => {});
        throw error;
      }),
    );
  }

  private async createAuditLog(
    meta: AuditLogMeta,
    request: Record<string, unknown>,
    user: Record<string, unknown> | undefined,
    failed: boolean,
  ): Promise<void> {
    try {
      const method = (request.method as string) || '';
      const body = request.body as Record<string, unknown> | undefined;
      const params = request.params as Record<string, string> | undefined;
      const query = request.query as Record<string, unknown> | undefined;

      let details: Record<string, unknown> = {};

      if (['POST', 'PUT', 'PATCH'].includes(method) && body) {
        const bodyStr = JSON.stringify(body);
        if (bodyStr.length > MAX_BODY_LENGTH) {
          details = {
            body_truncated: true,
            body_preview: bodyStr.substring(0, MAX_BODY_LENGTH) + '...',
          };
        } else {
          details = { body };
        }
      }

      if (params && Object.keys(params).length > 0) {
        details.params = params;
      }

      if (query && Object.keys(query).length > 0) {
        const queryCopy = { ...query };
        delete queryCopy.password;
        delete queryCopy.token;
        if (Object.keys(queryCopy).length > 0) {
          details.query = queryCopy;
        }
      }

      if (failed) {
        details.failed = true;
      }

      const resourceId =
        params?.id ??
        params?.sn ??
        params?.taskId ??
        params?.ruleId ??
        undefined;

      const auditLog = this.auditLogRepo.create({
        user_id: (user?.id as number) ?? 0,
        username: (user?.nickname as string) ?? 'unknown',
        action: meta.action,
        resource: meta.resource,
        resource_id: resourceId,
        details,
        ip_address: (request.ip as string) ?? null,
      });

      await this.auditLogRepo.save(auditLog);
    } catch {
    }
  }
}
