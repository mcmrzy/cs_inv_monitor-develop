import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Alert } from '../../entities/alert.entity';
import { WorkOrder } from '../../entities/work-order.entity';
import { Device } from '../../entities/device.entity';
import { AlertRule } from '../../entities/alert-rule.entity';
import { AlertNotification } from '../../entities/alert-notification.entity';
import { User } from '../../entities/user.entity';
import { AlertService } from './alert.service';
import { AlertController } from './alert.controller';
import { WorkOrderController } from './work-order.controller';
import { AlertRuleService } from './alert-rule.service';
import { AlertRuleController } from './alert-rule.controller';
import { AlertNotificationService } from './alert-notification.service';
import { SlaEngineService } from './sla-engine.service';
import { WorkOrderTemplateService } from './work-order-template.service';
import { SlaCronService } from './sla-cron.service';
import { WebSocketModule } from '../websocket/websocket.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Alert, WorkOrder, Device, AlertRule, AlertNotification, User]),
    WebSocketModule,
  ],
  controllers: [AlertController, WorkOrderController, AlertRuleController],
  providers: [AlertService, AlertRuleService, AlertNotificationService, SlaEngineService, WorkOrderTemplateService, SlaCronService],
  exports: [AlertService, AlertRuleService, AlertNotificationService, SlaEngineService],
})
export class AlertModule {}
