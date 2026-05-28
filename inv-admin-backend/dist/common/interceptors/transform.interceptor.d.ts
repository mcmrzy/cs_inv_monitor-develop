import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
export declare class TransformInterceptor<T> implements NestInterceptor<T, unknown> {
    intercept(_context: ExecutionContext, next: CallHandler<T>): Observable<unknown>;
}
