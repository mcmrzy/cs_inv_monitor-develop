import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';

export enum OtaTaskStatus {
  PENDING = 'pending',
  PUSHING = 'pushing',
  IN_PROGRESS = 'in_progress',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  ROLLED_BACK = 'rolled_back',
}

@Entity('ota_tasks')
export class OtaTask {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 200 })
  name: string;

  @Column({ type: 'bigint', name: 'firmware_id' })
  firmware_id: number;

  @Column({ type: 'bigint', name: 'created_by' })
  created_by: number;

  @Column({ type: 'enum', enum: OtaTaskStatus, default: OtaTaskStatus.PENDING })
  status: OtaTaskStatus;

  @Column({ type: 'integer', default: 0, name: 'total_devices' })
  total_devices: number;

  @Column({ type: 'integer', default: 0, name: 'success_count' })
  success_count: number;

  @Column({ type: 'integer', default: 0, name: 'failed_count' })
  failed_count: number;

  @Column({ type: 'varchar', length: 20, default: 'all_at_once', name: 'push_strategy' })
  push_strategy: string;

  @Column({ type: 'int', default: 100, name: 'push_percentage' })
  push_percentage: number;

  @Column({ type: 'int', default: 10, name: 'batch_size' })
  batch_size: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' })
  updated_at: Date;
}
