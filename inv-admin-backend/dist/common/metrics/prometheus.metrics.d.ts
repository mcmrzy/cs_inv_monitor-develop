import { Registry, Counter, Histogram, Gauge } from 'prom-client';
export declare class PrometheusMetrics {
    private registry;
    httpRequestCount: Counter<"path" | "status" | "method">;
    httpRequestDuration: Histogram<"path" | "method">;
    deviceOnlineCount: Gauge<string>;
    deviceTotalCount: Gauge<string>;
    mqttMessagesTotal: Counter<string>;
    alertsActiveCount: Gauge<string>;
    getRegistry(): Registry;
    getMetrics(): Promise<string>;
}
