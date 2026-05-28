import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('command_logs')
export class CommandLog {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index()
  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'varchar', length: 50, name: 'command_name' })
  command_name: string;

  @Column({ type: 'varchar', length: 100, name: 'command_label' })
  command_label: string;

  @Column({ type: 'jsonb', nullable: true })
  params: any;

  @Column({ type: 'varchar', length: 50, name: 'req_id' })
  req_id: string;

  @Column({ type: 'varchar', length: 20, default: 'pending' })
  status: string;

  @Column({ type: 'text', nullable: true, name: 'result_message' })
  result_message: string;

  @Index()
  @Column({ type: 'bigint', name: 'executed_by' })
  executed_by: number;

  @Column({ type: 'varchar', length: 45, nullable: true, name: 'ip_address' })
  ip_address: string;

  @Column({ type: 'int', default: 0, name: 'retry_count' })
  retry_count: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @Column({ type: 'timestamp', nullable: true, name: 'completed_at' })
  completed_at: Date;
}
