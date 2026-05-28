import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkOrder, WorkOrderPriority, WorkOrderStatus } from '../../entities/work-order.entity';

@Injectable()
export class SlaEngineService {
  private readonly logger = new Logger(SlaEngineService.name);

  constructor(
    @InjectRepository(WorkOrder)
    private workOrderRepo: Repository<WorkOrder>,
  ) {}

  calculateDeadline(priority: number): Date {
    const now = new Date();
    switch (priority) {
      case WorkOrderPriority.LOW:
        return new Date(now.getTime() + 48 * 60 * 60 * 1000);
      case WorkOrderPriority.MEDIUM:
        return new Date(now.getTime() + 24 * 60 * 60 * 1000);
      case WorkOrderPriority.HIGH:
        return new Date(now.getTime() + 8 * 60 * 60 * 1000);
      case WorkOrderPriority.URGENT:
        return new Date(now.getTime() + 2 * 60 * 60 * 1000);
      default:
        return new Date(now.getTime() + 48 * 60 * 60 * 1000);
    }
  }

  async checkOverdue(): Promise<number> {
    const now = new Date();
    const overdueWorkOrders = await this.workOrderRepo
      .createQueryBuilder('wo')
      .where('wo.status IN (:...statuses)', { statuses: [WorkOrderStatus.OPEN, WorkOrderStatus.IN_PROGRESS] })
      .andWhere('wo.sla_deadline IS NOT NULL')
      .andWhere('wo.sla_deadline < :now', { now })
      .getMany();

    let escalatedCount = 0;

    for (const wo of overdueWorkOrders) {
      wo.sla_overdue_count = (wo.sla_overdue_count || 0) + 1;
      this.logger.warn(
        `SLA breach: work order ${wo.id}, overdue count: ${wo.sla_overdue_count}, current priority: ${wo.priority}`,
      );

      const overdueHours = (now.getTime() - wo.sla_deadline!.getTime()) / (1000 * 60 * 60);
      if (overdueHours > 24 && wo.priority < WorkOrderPriority.URGENT) {
        wo.priority = Math.min(wo.priority + 1, WorkOrderPriority.URGENT);
        this.logger.warn(
          `Work order ${wo.id} auto-escalated to priority ${wo.priority} due to ${overdueHours.toFixed(1)}h overdue`,
        );
        escalatedCount++;
      }
    }

    if (overdueWorkOrders.length > 0) {
      await this.workOrderRepo.save(overdueWorkOrders);
      this.logger.log(`SLA check complete: ${overdueWorkOrders.length} overdue, ${escalatedCount} escalated`);
    }

    return overdueWorkOrders.length;
  }

  onSlaBreach(workOrder: WorkOrder): void {
    this.logger.error(
      `SLA BREACH: Work order "${workOrder.title}" (${workOrder.id}) is overdue. ` +
      `Priority: ${workOrder.priority}, Assignee: ${workOrder.assigned_to}, ` +
      `Created: ${workOrder.created_at}, Deadline: ${workOrder.sla_deadline}`,
    );
  }
}
