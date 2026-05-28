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
exports.EventsGateway = void 0;
const common_1 = require("@nestjs/common");
const websockets_1 = require("@nestjs/websockets");
const socket_io_1 = require("socket.io");
const jwt_1 = require("@nestjs/jwt");
let EventsGateway = class EventsGateway {
    constructor(jwtService) {
        this.jwtService = jwtService;
        this.logger = new common_1.Logger('WebSocketGateway');
        this.onlineClients = new Map();
    }
    afterInit(server) {
        this.logger.log('WebSocket Gateway initialized');
    }
    handleConnection(client) {
        const token = client.handshake.auth?.token;
        if (!token) {
            this.logger.warn(`客户端 ${client.id} 未提供token，断开连接`);
            client.disconnect();
            return;
        }
        try {
            const payload = this.jwtService.verify(token);
            const userId = payload.sub ?? payload.id;
            this.onlineClients.set(client.id, userId);
            this.logger.log(`Client connected: ${client.id}, userId: ${userId}`);
        }
        catch {
            this.logger.warn(`客户端 ${client.id} token验证失败，断开连接`);
            client.disconnect();
        }
    }
    handleDisconnect(client) {
        this.onlineClients.delete(client.id);
        this.logger.log(`Client disconnected: ${client.id}`);
    }
    broadcastTelemetryUpdate(deviceSn, data) {
        this.server.emit('telemetry:update', { deviceSn, data });
    }
    sendAlertNotification(alert) {
        this.server.emit('alert:new', alert);
    }
    sendOtaProgress(taskId, deviceSn, progress, status) {
        this.server.emit('ota:progress', { taskId, deviceSn, progress, status });
    }
    getOnlineClientCount() {
        return this.onlineClients.size;
    }
};
exports.EventsGateway = EventsGateway;
__decorate([
    (0, websockets_1.WebSocketServer)(),
    __metadata("design:type", socket_io_1.Server)
], EventsGateway.prototype, "server", void 0);
exports.EventsGateway = EventsGateway = __decorate([
    (0, websockets_1.WebSocketGateway)({ namespace: '/ws', cors: true }),
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [jwt_1.JwtService])
], EventsGateway);
//# sourceMappingURL=websocket.gateway.js.map