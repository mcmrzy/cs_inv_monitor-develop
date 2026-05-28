import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { PrometheusMetrics } from '../metrics/prometheus.metrics';

@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  constructor(private readonly metrics: PrometheusMetrics) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const { method, path: rawPath } = request;
    const path = rawPath as string;

    if (path === '/admin/metrics' || path === '/api/admin/metrics') {
      return next.handle();
    }

    const startTime = Date.now();

    return next.handle().pipe(
      tap(() => {
        const response = context.switchToHttp().getResponse();
        const statusCode = response.statusCode.toString();
        const duration = Date.now() - startTime;
        this.metrics.httpRequestCount.inc({ method, path, status: statusCode });
        this.metrics.httpRequestDuration.observe({ method, path }, duration);
      }),
    );
  }
}
