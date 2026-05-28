import { OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtService } from '@nestjs/jwt';
export declare class EventsGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
    private readonly jwtService;
    server: Server;
    private logger;
    private onlineClients;
    constructor(jwtService: JwtService);
    afterInit(server: Server): void;
    handleConnection(client: Socket): void;
    handleDisconnect(client: Socket): void;
    broadcastTelemetryUpdate(deviceSn: string, data: any): void;
    sendAlertNotification(alert: any): void;
    sendOtaProgress(taskId: string, deviceSn: string, progress: number, status: string): void;
    getOnlineClientCount(): number;
}
