"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.MetricsInterceptor = void 0;
const common_1 = require("@nestjs/common");
const operators_1 = require("rxjs/operators");
const prometheus_metrics_1 = require("../metrics/prometheus.metrics");
let MetricsInterceptor = class MetricsInterceptor {
    constructor(metrics) {
        this.metrics = metrics;
    }
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        const { method, path: rawPath } = request;
        const path = rawPath;
        if (path === '/admin/metrics' || path === '/api/admin/metrics') {
            return next.handle();
        }
        const startTime = Date.now();
        return next.handle().pipe((0, operators_1.tap)(() => {
            const response = context.switchToHttp().getResponse();
            const statusCode = response.statusCode.toString();
            const duration = Date.now() - startTime;
            this.metrics.httpRequestCount.inc({ method, path, status: statusCode });
            this.metrics.httpRequestDuration.observe({ method, path }, duration);
        }));
    }
};
exports.MetricsInterceptor = MetricsInterceptor;
exports.MetricsInterceptor = MetricsInterceptor = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prometheus_metrics_1.PrometheusMetrics])
], MetricsInterceptor);
//# sourceMappingURL=metrics.interceptor.js.map