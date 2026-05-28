import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
} from 'typeorm';

@Entity('parallel_status')
export class ParallelStatus {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index()
  @Column({ type: 'bigint', name: 'parallel_id' })
  parallel_id: number;

  @Index()
  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0, name: 'output_power' })
  output_power: number;

  @Column({ type: 'decimal', precision: 5, scale: 1, default: 0, name: 'load_percent' })
  load_percent: number;

  @Column({ type: 'decimal', precision: 10, scale: 4, default: 0, name: 'phase_angle_offset' })
  phase_angle_offset: number;

  @Column({ type: 'decimal', precision: 8, scale: 3, default: 0, name: 'circulating_current' })
  circulating_current: number;

  @Column({ type: 'varchar', length: 20, default: 'synced' })
  sync_status: string;

  @Column({ type: 'varchar', length: 20 })
  role: string;

  @Column({ type: 'timestamp', name: 'data_time' })
  data_time: Date;
}
