import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
} from 'typeorm';

@Entity('parallel_configs')
export class ParallelConfig {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'varchar', length: 100, name: 'group_name' })
  group_name: string;

  @Column({ type: 'varchar', length: 10, default: 'single' })
  phase_config: string;

  @Column({ type: 'varchar', length: 50, name: 'master_sn' })
  master_sn: string;

  @Column({ type: 'text', nullable: true, name: 'slave_sns' })
  slave_sns: string;

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true, name: 'circulating_current_threshold' })
  circulating_current_threshold: number;

  @Column({ type: 'decimal', precision: 5, scale: 1, nullable: true, name: 'load_balance_deviation' })
  load_balance_deviation: number;

  @Column({ type: 'smallint', default: 1 })
  status: number;

  @Column({ type: 'bigint', nullable: true, name: 'created_by' })
  created_by: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at' })
  created_at: Date;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at' })
  updated_at: Date;
}
