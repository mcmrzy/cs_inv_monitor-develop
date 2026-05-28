import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
} from 'typeorm';

export enum OtaTaskDeviceStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  INSTALLING = 'installing',
  SUCCESS = 'success',
  FAILED = 'failed',
}

@Entity('ota_task_devices')
export class OtaTaskDevice {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'uuid', name: 'task_id' })
  task_id: string;

  @Column({ type: 'varchar', length: 50, name: 'device_sn' })
  device_sn: string;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'old_version' })
  old_version: string | null;

  @Column({ type: 'varchar', length: 50, nullable: true, name: 'new_version' })
  new_version: string | null;

  @Column({ type: 'enum', enum: OtaTaskDeviceStatus, default: OtaTaskDeviceStatus.PENDING })
  status: OtaTaskDeviceStatus;

  @Column({ type: 'integer', default: 0 })
  progress: number;

  @Column({ type: 'text', nullable: true, name: 'error_message' })
  error_message: string | null;

  @Column({ type: 'timestamp', nullable: true, name: 'started_at' })
  started_at: Date | null;

  @Column({ type: 'timestamp', nullable: true, name: 'completed_at' })
  completed_at: Date | null;

  @Column({ type: 'text', nullable: true, name: 'mqtt_message' })
  mqtt_message: string | null;

  @CreateDateColumn({ type: 'timestamp', name: 'created_at', default: () => 'CURRENT_TIMESTAMP' })
  created_at: Date;
}
