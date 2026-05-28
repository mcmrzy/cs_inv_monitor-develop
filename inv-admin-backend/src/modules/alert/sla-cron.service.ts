import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { SlaEngineService } from './sla-engine.service';

@Injectable()
export class SlaCronService {
  private readonly logger = new Logger(SlaCronService.name);

  constructor(private readonly slaEngineService: SlaEngineService) {}

  @Cron(CronExpression.EVERY_10_MINUTES)
  async handleSlaCheck() {
    this.logger.log('Running SLA overdue check...');
    try {
      const overdueCount = await this.slaEngineService.checkOverdue();
      if (overdueCount > 0) {
        this.logger.warn(`SLA check found ${overdueCount} overdue work orders`);
      }
    } catch (error) {
      this.logger.error('SLA check failed', error);
    }
  }
}
