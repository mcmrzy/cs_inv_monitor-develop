import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

export enum WorkOrderPriority {
  LOW = 1,
  MEDIUM = 2,
  HIGH = 3,
  URGENT = 4,
}

export enum WorkOrderStatus {
  OPEN = 'open',
  IN_PROGRESS = 'in_progress',
  RESOLVED = 'resolved',
  CLOSED = 'closed',
}

@Entity('work_orders')
export class WorkOrder {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 200 })
  title: string;

  @Column({ type: 'text', nullable: true })
  description: string;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'bigint', nullable: true, name: 'station_id' })
  station_id: number;

  @Column({ type: 'bigint', name: 'created_by' })
  created_by: number;

  @Column({ type: 'bigint', nullable: true, name: 'assigned_to' })
  assigned_to: number;

  @Column({ type: 'smallint', default: WorkOrderPriority.LOW })
  priority: number;

  @Column({ type: 'enum', enum: WorkOrderStatus, default: WorkOrderStatus.OPEN })
  status: WorkOrderStatus;

  @Column({ type: 'text', nullable: true })
  resolution: string;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' })
  updated_at: Date;

  @Column({ type: 'timestamp', nullable: true, name: 'resolved_at' })
  resolved_at: Date;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'template_type' })
  template_type: string | null;

  @Column({ type: 'timestamp', nullable: true, name: 'sla_deadline' })
  sla_deadline: Date | null;

  @Column({ type: 'int', default: 0, name: 'sla_overdue_count' })
  sla_overdue_count: number;

  @Column({ type: 'jsonb', nullable: true, name: 'attachments' })
  attachments: { name: string; url: string; type: string; uploadedAt: string }[] | null;
}
