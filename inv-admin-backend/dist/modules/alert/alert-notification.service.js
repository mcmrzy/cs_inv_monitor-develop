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
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var AlertNotificationService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.AlertNotificationService = void 0;
const common_1 = require("@nestjs/common");
const typeorm_1 = require("@nestjs/typeorm");
const typeorm_2 = require("typeorm");
const alert_notification_entity_1 = require("../../entities/alert-notification.entity");
const device_entity_1 = require("../../entities/device.entity");
const user_entity_1 = require("../../entities/user.entity");
const websocket_gateway_1 = require("../websocket/websocket.gateway");
let AlertNotificationService = AlertNotificationService_1 = class AlertNotificationService {
    constructor(notificationRepo, deviceRepo, userRepo, eventsGateway) {
        this.notificationRepo = notificationRepo;
        this.deviceRepo = deviceRepo;
        this.userRepo = userRepo;
        this.eventsGateway = eventsGateway;
        this.logger = new common_1.Logger(AlertNotificationService_1.name);
    }
    async sendNotifications(alert) {
        try {
            const ownerIds = await this.getNotificationRecipients(alert);
            this.logger.log(`Sending notifications for alert ${alert.id} to ${ownerIds.length} recipients`);
            for (const userId of ownerIds) {
                await this.createNotification(alert.id, userId, 'push');
                await this.createNotification(alert.id, userId, 'sms');
                await this.createNotification(alert.id, userId, 'email');
                await this.sendPush(userId, alert);
            }
        }
        catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            this.logger.error(`Failed to send notifications for alert ${alert.id}: ${msg}`);
        }
    }
    async sendPush(userId, alert) {
        try {
            this.eventsGateway.sendAlertNotification({
                id: alert.id,
                deviceSn: alert.device_sn,
                alarmLevel: alert.alarm_level,
                faultCode: alert.fault_code,
                faultMessage: alert.fault_message,
                occurredAt: alert.occurred_at,
            });
            await this.notificationRepo.update({ alert_id: alert.id, user_id: userId, notify_type: 'push' }, { status: 'sent', sent_at: new Date() });
        }
        catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            this.logger.error(`Push notification failed for user ${userId}: ${msg}`);
            await this.notificationRepo.update({ alert_id: alert.id, user_id: userId, notify_type: 'push' }, { status: 'failed', error_message: msg });
        }
    }
    async sendSMS(phone, message) {
        this.logger.log(`[SMS PLACEHOLDER] To: ${phone}, Message: ${message}`);
    }
    async sendEmail(email, alert) {
        this.logger.log(`[EMAIL PLACEHOLDER] To: ${email}, Alert: ${alert.fault_code} - ${alert.fault_message}`);
    }
    async retryFailed() {
        const failedNotifications = await this.notificationRepo.find({
            where: { status: 'failed' },
        });
        this.logger.log(`Retrying ${failedNotifications.length} failed notifications`);
        for (const notification of failedNotifications) {
            notification.status = 'pending';
            await this.notificationRepo.save(notification);
        }
    }
    async getNotificationRecipients(alert) {
        const device = await this.deviceRepo.findOne({
            where: { sn: alert.device_sn },
            select: ['user_id', 'installer_id'],
        });
        if (!device) {
            return [];
        }
        const recipientIds = new Set();
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
    async createNotification(alertId, userId, type) {
        try {
            const notification = this.notificationRepo.create({
                alert_id: alertId,
                user_id: userId,
                notify_type: type,
                status: 'pending',
            });
            await this.notificationRepo.save(notification);
        }
        catch (error) {
            const msg = error instanceof Error ? error.message : String(error);
            this.logger.error(`Failed to create ${type} notification for alert ${alertId}, user ${userId}: ${msg}`);
        }
    }
};
exports.AlertNotificationService = AlertNotificationService;
exports.AlertNotificationService = AlertNotificationService = AlertNotificationService_1 = __decorate([
    (0, common_1.Injectable)(),
    __param(0, (0, typeorm_1.InjectRepository)(alert_notification_entity_1.AlertNotification)),
    __param(1, (0, typeorm_1.InjectRepository)(device_entity_1.Device)),
    __param(2, (0, typeorm_1.InjectRepository)(user_entity_1.User)),
    __metadata("design:paramtypes", [typeorm_2.Repository,
        typeorm_2.Repository,
        typeorm_2.Repository,
        websocket_gateway_1.EventsGateway])
], AlertNotificationService);
//# sourceMappingURL=alert-notification.service.js.map