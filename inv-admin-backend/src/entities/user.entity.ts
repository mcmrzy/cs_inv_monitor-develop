import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
  Index,
} from 'typeorm';
import { Exclude } from 'class-transformer';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'varchar', length: 20, unique: true })
  phone: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  email: string | null;

  @Exclude()
  @Column({ type: 'varchar', length: 255, name: 'password_hash' })
  password_hash: string;

  @Column({ type: 'varchar', length: 50, nullable: true })
  nickname: string | null;

  @Column({ type: 'varchar', length: 500, nullable: true })
  avatar: string | null;

  @Column({ type: 'smallint', default: 3 })
  role: number;

  @Column({ type: 'bigint', nullable: true, name: 'parent_id' })
  parent_id: number | null;

  @Column({ type: 'bigint', nullable: true, name: 'region_id' })
  region_id: number | null;

  @Column({ type: 'smallint', default: 1 })
  status: number;

  @Column({ type: 'timestamp', nullable: true, name: 'last_login_at' })
  last_login_at: Date;

  @Column({ type: 'varchar', length: 45, nullable: true, name: 'last_login_ip' })
  last_login_ip: string | null;

  @Column({ type: 'int', default: 0, name: 'login_fail_count' })
  login_fail_count: number;

  @Column({ type: 'timestamp', nullable: true, name: 'locked_until' })
  locked_until: Date | null;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' })
  updated_at: Date;

  @DeleteDateColumn({ type: 'timestamp', nullable: true, name: 'deleted_at' })
  deleted_at: Date;
}
