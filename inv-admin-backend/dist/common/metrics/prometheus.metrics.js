"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PrometheusMetrics = void 0;
const common_1 = require("@nestjs/common");
const prom_client_1 = require("prom-client");
let PrometheusMetrics = class PrometheusMetrics {
    constructor() {
        this.registry = new prom_client_1.Registry();
        this.httpRequestCount = new prom_client_1.Counter({
            name: 'http_requests_total',
            help: 'Total HTTP requests',
            labelNames: ['method', 'path', 'status'],
            registers: [this.registry],
        });
        this.httpRequestDuration = new prom_client_1.Histogram({
            name: 'http_request_duration_ms',
            help: 'HTTP request duration in ms',
            labelNames: ['method', 'path'],
            buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000],
            registers: [this.registry],
        });
        this.deviceOnlineCount = new prom_client_1.Gauge({
            name: 'device_online_count',
            help: 'Current online device count',
            registers: [this.registry],
        });
        this.deviceTotalCount = new prom_client_1.Gauge({
            name: 'device_total_count',
            help: 'Total device count',
            registers: [this.registry],
        });
        this.mqttMessagesTotal = new prom_client_1.Counter({
            name: 'mqtt_messages_total',
            help: 'Total MQTT messages',
            registers: [this.registry],
        });
        this.alertsActiveCount = new prom_client_1.Gauge({
            name: 'alerts_active_count',
            help: 'Active alert count',
            registers: [this.registry],
        });
    }
    getRegistry() {
        return this.registry;
    }
    getMetrics() {
        return this.registry.metrics();
    }
};
exports.PrometheusMetrics = PrometheusMetrics;
exports.PrometheusMetrics = PrometheusMetrics = __decorate([
    (0, common_1.Injectable)()
], PrometheusMetrics);
//# sourceMappingURL=prometheus.metrics.js.map