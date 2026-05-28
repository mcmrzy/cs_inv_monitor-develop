import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('alert_rules')
export class AlertRule {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'varchar', length: 100 })
  name: string;

  @Column({ type: 'varchar', length: 100, name: 'field_name' })
  field_name: string;

  @Column({ type: 'varchar', length: 20 })
  operator: string;

  @Column({ type: 'decimal', precision: 12, scale: 4, name: 'threshold_value' })
  threshold_value: number;

  @Column({ type: 'smallint', default: 2 })
  alarm_level: number;

  @Column({ type: 'varchar', length: 200, name: 'fault_code' })
  fault_code: string;

  @Column({ type: 'text', name: 'fault_message' })
  fault_message: string;

  @Index()
  @Column({ type: 'varchar', length: 50, nullable: true, name: 'device_model' })
  device_model: string;

  @Column({ type: 'boolean', default: true, name: 'is_active' })
  is_active: boolean;

  @Column({ type: 'int', default: 5, name: 'cooldown_minutes' })
  cooldown_minutes: number;

  @Column({ type: 'bigint', nullable: true, name: 'created_by' })
  created_by: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  created_at: Date;
}
