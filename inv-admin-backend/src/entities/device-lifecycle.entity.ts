import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('device_lifecycle')
export class DeviceLifecycle {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'varchar', length: 50, name: 'event_type' })
  event_type: string;

  @Column({ type: 'text', nullable: true })
  description: string;

  @Column({ type: 'bigint', nullable: true, name: 'triggered_by' })
  triggered_by: number;

  @Column({ type: 'jsonb', nullable: true, name: 'metadata' })
  metadata: any;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  created_at: Date;
}
