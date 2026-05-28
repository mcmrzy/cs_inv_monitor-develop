import { NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { Observable } from 'rxjs';
import { PrometheusMetrics } from '../metrics/prometheus.metrics';
export declare class MetricsInterceptor implements NestInterceptor {
    private readonly metrics;
    constructor(metrics: PrometheusMetrics);
    intercept(context: ExecutionContext, next: CallHandler): Observable<unknown>;
}
