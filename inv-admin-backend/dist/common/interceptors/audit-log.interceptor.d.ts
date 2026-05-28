import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Repository } from 'typeorm';
import { Observable } from 'rxjs';
import { AuditLog } from '@entities/audit-log.entity';
export declare class AuditLogInterceptor implements NestInterceptor {
    private auditLogRepo;
    private reflector;
    constructor(auditLogRepo: Repository<AuditLog>, reflector: Reflector);
    intercept(context: ExecutionContext, next: CallHandler): Observable<unknown>;
    private createAuditLog;
}
