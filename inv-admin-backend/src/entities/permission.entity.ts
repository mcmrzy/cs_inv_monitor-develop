import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export enum PermissionAction {
  VIEW = 'view',
  CREATE = 'create',
  EDIT = 'edit',
  DELETE = 'delete',
  EXPORT = 'export',
  CONTROL = 'control',
  MANAGE = 'manage',
}

export enum PermissionResource {
  DEVICES = 'devices',
  USERS = 'users',
  ALERTS = 'alerts',
  WORK_ORDERS = 'work_orders',
  OTA = 'ota',
  STATIONS = 'stations',
  DASHBOARD = 'dashboard',
  PARALLEL = 'parallel',
  ADMIN = 'admin',
  AUDIT = 'audit',
  ALERT_RULES = 'alert_rules',
  FIRMWARE = 'firmware',
}

@Entity('role_permissions')
@Index('idx_permissions_role', ['role'])
@Index('uq_role_resource_action', ['role', 'resource', 'action'], { unique: true })
export class RolePermission {
  @PrimaryGeneratedColumn({ type: 'bigint' })
  id: number;

  @Column({ type: 'smallint' })
  role: number;

  @Column({ type: 'varchar', length: 50 })
  resource: string;

  @Column({ type: 'varchar', length: 50 })
  action: string;

  @Column({ type: 'boolean', default: true, name: 'is_allowed' })
  is_allowed: boolean;

  @UpdateDateColumn({ type: 'timestamp', name: 'updated_at' })
  updated_at: Date;
}
