import {
  Injectable,
  Logger,
} from '@nestjs/common';
import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayInit,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';

@WebSocketGateway({ namespace: '/ws', cors: true })
@Injectable()
export class EventsGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer() server: Server;
  private logger = new Logger('WebSocketGateway');
  private onlineClients = new Map<string, string>();

  constructor(private readonly jwtService: JwtService) {}

  afterInit(server: Server) {
    this.logger.log('WebSocket Gateway initialized');
  }

  handleConnection(client: Socket) {
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
    } catch {
      this.logger.warn(`客户端 ${client.id} token验证失败，断开连接`);
      client.disconnect();
    }
  }

  handleDisconnect(client: Socket) {
    this.onlineClients.delete(client.id);
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  broadcastTelemetryUpdate(deviceSn: string, data: any) {
    this.server.emit('telemetry:update', { deviceSn, data });
  }

  sendAlertNotification(alert: any) {
    this.server.emit('alert:new', alert);
  }

  sendOtaProgress(taskId: string, deviceSn: string, progress: number, status: string) {
    this.server.emit('ota:progress', { taskId, deviceSn, progress, status });
  }

  getOnlineClientCount(): number {
    return this.onlineClients.size;
  }
}
