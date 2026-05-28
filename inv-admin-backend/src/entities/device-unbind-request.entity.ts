import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

@Entity('device_unbind_requests')
export class DeviceUnbindRequest {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'bigint', name: 'requested_by' })
  requested_by: number;

  @Column({ type: 'text', nullable: true })
  reason: string | null;

  @Column({ type: 'varchar', length: 20, default: 'pending' })
  status: string;

  @Column({ type: 'bigint', nullable: true, name: 'reviewed_by' })
  reviewed_by: number | null;

  @Column({ type: 'text', nullable: true, name: 'review_comment' })
  review_comment: string | null;

  @Column({ type: 'timestamp', nullable: true, name: 'reviewed_at' })
  reviewed_at: Date;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  created_at: Date;
}
