import { Injectable } from '@nestjs/common';
import { Registry, Counter, Histogram, Gauge } from 'prom-client';

@Injectable()
export class PrometheusMetrics {
  private registry = new Registry();

  httpRequestCount = new Counter({
    name: 'http_requests_total',
    help: 'Total HTTP requests',
    labelNames: ['method', 'path', 'status'],
    registers: [this.registry],
  });

  httpRequestDuration = new Histogram({
    name: 'http_request_duration_ms',
    help: 'HTTP request duration in ms',
    labelNames: ['method', 'path'],
    buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000],
    registers: [this.registry],
  });

  deviceOnlineCount = new Gauge({
    name: 'device_online_count',
    help: 'Current online device count',
    registers: [this.registry],
  });

  deviceTotalCount = new Gauge({
    name: 'device_total_count',
    help: 'Total device count',
    registers: [this.registry],
  });

  mqttMessagesTotal = new Counter({
    name: 'mqtt_messages_total',
    help: 'Total MQTT messages',
    registers: [this.registry],
  });

  alertsActiveCount = new Gauge({
    name: 'alerts_active_count',
    help: 'Active alert count',
    registers: [this.registry],
  });

  getRegistry(): Registry {
    return this.registry;
  }

  getMetrics(): Promise<string> {
    return this.registry.metrics();
  }
}
