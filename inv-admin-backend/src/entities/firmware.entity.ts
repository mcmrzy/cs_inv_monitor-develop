import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('firmware_versions')
export class Firmware {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index()
  @Column({ type: 'varchar', length: 100 })
  model: string;

  @Column({ type: 'varchar', length: 50 })
  version: string;

  @Column({ type: 'varchar', length: 500, name: 'file_url' })
  file_url: string;

  @Column({ type: 'bigint', nullable: true, name: 'file_size' })
  file_size: number;

  @Column({ type: 'varchar', length: 32, nullable: true, name: 'file_md5' })
  file_md5: string;

  @Column({ type: 'varchar', length: 64, nullable: true, name: 'file_sha256' })
  file_sha256: string | null;

  @Column({ type: 'text', nullable: true })
  changelog: string;

  @Column({ type: 'boolean', default: false, name: 'is_force' })
  is_force: boolean;

  @Column({ type: 'smallint', default: 1 })
  status: number;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @Column({ type: 'bigint', nullable: true, name: 'uploaded_by' })
  uploaded_by: number;
}
