import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
  Index,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { User } from './user.entity';
import { Station } from './station.entity';

@Entity('devices')
export class Device {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Index({ unique: true })
  @Column({ type: 'varchar', length: 50, unique: true })
  sn: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  model: string;

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true, name: 'rated_power' })
  rated_power: number;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'firmware_version' })
  firmware_version: string;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'hardware_version' })
  hardware_version: string;

  @Column({ type: 'varchar', length: 17, nullable: true, name: 'mac_address' })
  mac_address: string;

  @Column({ type: 'bigint', nullable: true, name: 'station_id' })
  station_id: number | null;

  @ManyToOne(() => Station, { nullable: true, createForeignKeyConstraints: false })
  @JoinColumn({ name: 'station_id' })
  station: Station | null;

  @Column({ type: 'bigint', name: 'user_id' })
  user_id: number;

  @ManyToOne(() => User, { nullable: true, createForeignKeyConstraints: false })
  @JoinColumn({ name: 'user_id' })
  owner: User | null;

  @Column({ type: 'bigint', nullable: true, name: 'installer_id' })
  installer_id: number;

  @ManyToOne(() => User, { nullable: true, createForeignKeyConstraints: false })
  @JoinColumn({ name: 'installer_id' })
  installer: User | null;

  @Column({ type: 'smallint', default: 0 })
  status: number;

  @Column({ type: 'timestamp', nullable: true, name: 'last_online_at' })
  last_online_at: Date;

  @Column({ type: 'varchar', length: 45, nullable: true, name: 'ip_address' })
  ip_address: string | null;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at', default: () => 'CURRENT_TIMESTAMP' })
  updated_at: Date;

  @DeleteDateColumn({ type: 'timestamp', nullable: true, name: 'deleted_at' })
  deleted_at: Date;
}
