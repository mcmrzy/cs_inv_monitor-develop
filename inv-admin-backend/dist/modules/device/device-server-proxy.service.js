"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var DeviceServerProxyService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.DeviceServerProxyService = void 0;
const common_1 = require("@nestjs/common");
const http = require("http");
let DeviceServerProxyService = DeviceServerProxyService_1 = class DeviceServerProxyService {
    constructor() {
        this.logger = new common_1.Logger(DeviceServerProxyService_1.name);
        this.goAdminBaseUrl = 'http://localhost:8080/admin/api';
        this.commandPath = '/devices';
    }
    async sendCommand(sn, commandName, params, reqId) {
        const url = `${this.goAdminBaseUrl}${this.commandPath}/${encodeURIComponent(sn)}/command`;
        const body = JSON.stringify({
            sn,
            command: commandName,
            params,
            reqId,
        });
        this.logger.log(`Sending command to Go server: ${url} - ${body}`);
        return this.httpPost(url, body);
    }
    async waitForAck(reqId, timeoutMs = 12000) {
        const startTime = Date.now();
        const pollInterval = 3000;
        const maxRetries = Math.ceil(timeoutMs / pollInterval);
        let lastError = null;
        for (let i = 0; i < maxRetries; i++) {
            const elapsed = Date.now() - startTime;
            if (elapsed >= timeoutMs) {
                break;
            }
            try {
                const url = `${this.goAdminBaseUrl}/commands/${reqId}/status`;
                const result = await this.httpGet(url);
                if (result && result.status === 'completed') {
                    return result;
                }
                if (result && result.status === 'failed') {
                    throw new Error(result.message || 'Command execution failed on device');
                }
                if (result && result.status === 'ack_received') {
                    return result;
                }
            }
            catch (err) {
                lastError = err;
            }
            const remaining = timeoutMs - (Date.now() - startTime);
            if (remaining > 0) {
                await this.sleep(Math.min(pollInterval, remaining));
            }
        }
        if (lastError) {
            throw lastError;
        }
        throw new Error(`Command ACK timeout after ${timeoutMs}ms`);
    }
    httpPost(url, body) {
        return new Promise((resolve, reject) => {
            const urlObj = new URL(url);
            const options = {
                hostname: urlObj.hostname,
                port: urlObj.port,
                path: urlObj.pathname,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(body),
                },
                timeout: 10000,
            };
            const req = http.request(options, (res) => {
                let data = '';
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', () => {
                    if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
                        try {
                            resolve(JSON.parse(data));
                        }
                        catch {
                            resolve({ raw: data });
                        }
                    }
                    else {
                        reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                    }
                });
            });
            req.on('error', (err) => {
                reject(err);
            });
            req.on('timeout', () => {
                req.destroy();
                reject(new Error('Request timeout'));
            });
            req.write(body);
            req.end();
        });
    }
    httpGet(url) {
        return new Promise((resolve, reject) => {
            const urlObj = new URL(url);
            const options = {
                hostname: urlObj.hostname,
                port: urlObj.port,
                path: urlObj.pathname + urlObj.search,
                method: 'GET',
                headers: {
                    'Content-Type': 'application/json',
                },
                timeout: 5000,
            };
            const req = http.request(options, (res) => {
                let data = '';
                res.on('data', (chunk) => {
                    data += chunk;
                });
                res.on('end', () => {
                    if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
                        try {
                            resolve(JSON.parse(data));
                        }
                        catch {
                            resolve({ raw: data });
                        }
                    }
                    else {
                        reject(new Error(`HTTP ${res.statusCode}: ${data}`));
                    }
                });
            });
            req.on('error', (err) => {
                reject(err);
            });
            req.on('timeout', () => {
                req.destroy();
                reject(new Error('Request timeout'));
            });
            req.end();
        });
    }
    sleep(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
};
exports.DeviceServerProxyService = DeviceServerProxyService;
exports.DeviceServerProxyService = DeviceServerProxyService = DeviceServerProxyService_1 = __decorate([
    (0, common_1.Injectable)()
], DeviceServerProxyService);
//# sourceMappingURL=device-server-proxy.service.js.map