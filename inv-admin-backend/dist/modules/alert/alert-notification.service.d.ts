import { Repository } from 'typeorm';
import { AlertNotification } from '../../entities/alert-notification.entity';
import { Alert } from '../../entities/alert.entity';
import { Device } from '../../entities/device.entity';
import { User } from '../../entities/user.entity';
import { EventsGateway } from '../websocket/websocket.gateway';
export declare class AlertNotificationService {
    private readonly notificationRepo;
    private readonly deviceRepo;
    private readonly userRepo;
    private readonly eventsGateway;
    private readonly logger;
    constructor(notificationRepo: Repository<AlertNotification>, deviceRepo: Repository<Device>, userRepo: Repository<User>, eventsGateway: EventsGateway);
    sendNotifications(alert: Alert): Promise<void>;
    sendPush(userId: number, alert: Alert): Promise<void>;
    sendSMS(phone: string, message: string): Promise<void>;
    sendEmail(email: string, alert: Alert): Promise<void>;
    retryFailed(): Promise<void>;
    private getNotificationRecipients;
    private createNotification;
}
