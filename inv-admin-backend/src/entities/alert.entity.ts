import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('alarms')
export class Alert {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index()
  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'bigint', nullable: true, name: 'station_id' })
  station_id: number;

  @Index()
  @Column({ type: 'bigint', name: 'user_id' })
  user_id: number;

  @Column({ type: 'smallint', name: 'alarm_level' })
  alarm_level: number;

  @Column({ type: 'varchar', length: 20, name: 'fault_code' })
  fault_code: string;

  @Column({ type: 'varchar', length: 200, name: 'fault_message' })
  fault_message: string;

  @Column({ type: 'text', nullable: true, name: 'fault_detail' })
  fault_detail: string;

  @Column({ type: 'smallint', default: 0 })
  status: number;

  @Column({ type: 'timestamp', name: 'occurred_at' })
  occurred_at: Date;

  @Column({ type: 'timestamp', nullable: true, name: 'recovered_at' })
  recovered_at: Date;

  @Column({ type: 'timestamp', nullable: true, name: 'handled_at' })
  handled_at: Date;

  @Column({ type: 'bigint', nullable: true, name: 'handled_by' })
  handled_by: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;
}
