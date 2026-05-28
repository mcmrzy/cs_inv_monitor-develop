import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import { AlertNotification } from '../../entities/alert-notification.entity';
import { Alert } from '../../entities/alert.entity';
import { Device } from '../../entities/device.entity';
import { User } from '../../entities/user.entity';
import { EventsGateway } from '../websocket/websocket.gateway';

@Injectable()
export class AlertNotificationService {
  private readonly logger = new Logger(AlertNotificationService.name);

  constructor(
    @InjectRepository(AlertNotification)
    private readonly notificationRepo: Repository<AlertNotification>,
    @InjectRepository(Device)
    private readonly deviceRepo: Repository<Device>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    private readonly eventsGateway: EventsGateway,
  ) {}

  async sendNotifications(alert: Alert): Promise<void> {
    try {
      const ownerIds = await this.getNotificationRecipients(alert);
      this.logger.log(`Sending notifications for alert ${alert.id} to ${ownerIds.length} recipients`);

      for (const userId of ownerIds) {
        await this.createNotification(alert.id, userId, 'push');
        await this.createNotification(alert.id, userId, 'sms');
        await this.createNotification(alert.id, userId, 'email');

        await this.sendPush(userId, alert);
      }
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.logger.error(`Failed to send notifications for alert ${alert.id}: ${msg}`);
    }
  }

  async sendPush(userId: number, alert: Alert): Promise<void> {
    try {
      this.eventsGateway.sendAlertNotification({
        id: alert.id,
        deviceSn: alert.device_sn,
        alarmLevel: alert.alarm_level,
        faultCode: alert.fault_code,
        faultMessage: alert.fault_message,
        occurredAt: alert.occurred_at,
      });

      await this.notificationRepo.update(
        { alert_id: alert.id, user_id: userId, notify_type: 'push' },
        { status: 'sent', sent_at: new Date() },
      );
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.logger.error(`Push notification failed for user ${userId}: ${msg}`);
      await this.notificationRepo.update(
        { alert_id: alert.id, user_id: userId, notify_type: 'push' },
        { status: 'failed', error_message: msg },
      );
    }
  }

  async sendSMS(phone: string, message: string): Promise<void> {
    this.logger.log(`[SMS PLACEHOLDER] To: ${phone}, Message: ${message}`);
  }

  async sendEmail(email: string, alert: Alert): Promise<void> {
    this.logger.log(
      `[EMAIL PLACEHOLDER] To: ${email}, Alert: ${alert.fault_code} - ${alert.fault_message}`,
    );
  }

  async retryFailed(): Promise<void> {
    const failedNotifications = await this.notificationRepo.find({
      where: { status: 'failed' },
    });

    this.logger.log(`Retrying ${failedNotifications.length} failed notifications`);

    for (const notification of failedNotifications) {
      notification.status = 'pending';
      await this.notificationRepo.save(notification);
    }
  }

  private async getNotificationRecipients(alert: Alert): Promise<number[]> {
    const device = await this.deviceRepo.findOne({
      where: { sn: alert.device_sn },
      select: ['user_id', 'installer_id'],
    });

    if (!device) {
      return [];
    }

    const recipientIds = new Set<number>();

    if (device.user_id) {
      recipientIds.add(device.user_id);

      const user = await this.userRepo.findOne({
        where: { id: device.user_id },
        select: ['parent_id'],
      });

      if (user?.parent_id) {
        recipientIds.add(user.parent_id);

        const parent = await this.userRepo.findOne({
          where: { id: user.parent_id },
          select: ['parent_id'],
        });

        if (parent?.parent_id) {
          recipientIds.add(parent.parent_id);
        }
      }
    }

    if (device.installer_id) {
      recipientIds.add(device.installer_id);
    }

    return Array.from(recipientIds);
  }

  private async createNotification(
    alertId: number,
    userId: number,
    type: string,
  ): Promise<void> {
    try {
      const notification = this.notificationRepo.create({
        alert_id: alertId,
        user_id: userId,
        notify_type: type,
        status: 'pending',
      });
      await this.notificationRepo.save(notification);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      this.logger.error(
        `Failed to create ${type} notification for alert ${alertId}, user ${userId}: ${msg}`,
      );
    }
  }
}
