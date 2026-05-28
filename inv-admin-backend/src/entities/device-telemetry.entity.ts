import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('device_telemetry')
export class DeviceTelemetry {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index()
  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'model_code' })
  model_code: string;

  @Column({ type: 'varchar', length: 200, nullable: true })
  topic: string;

  @Column({ type: 'jsonb' })
  data: Record<string, unknown>;

  @Column({ type: 'decimal', precision: 12, scale: 2, default: 0, name: 'total_active_power' })
  total_active_power: number;

  @Column({ type: 'decimal', precision: 14, scale: 4, default: 0, name: 'daily_energy' })
  daily_energy: number;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'work_state' })
  work_state: string;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'fault_code' })
  fault_code: string;

  @Column({ type: 'decimal', precision: 6, scale: 1, default: 0, name: 'internal_temperature' })
  internal_temperature: number;

  @Index()
  @Column({ type: 'timestamp', default: () => 'NOW()' })
  time: Date;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;
}
