import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
export interface DataScope {
    userId?: number;
    allowedUserIds?: number[];
    installerId?: number;
    allowedInstallerIds?: number[];
}
export declare class DataScopeInterceptor implements NestInterceptor {
    intercept(context: ExecutionContext, next: CallHandler): Observable<unknown>;
    private buildDataScope;
}
