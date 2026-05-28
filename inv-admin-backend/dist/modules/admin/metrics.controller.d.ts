import { Response } from 'express';
import { PrometheusMetrics } from '../../common/metrics/prometheus.metrics';
export declare class MetricsController {
    private readonly metrics;
    constructor(metrics: PrometheusMetrics);
    getMetrics(res: Response): Promise<void>;
}
