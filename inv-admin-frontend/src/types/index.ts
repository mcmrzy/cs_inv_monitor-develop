export enum Role {
  SUPER_ADMIN = 0,
  ADMIN = 1,
  OPERATOR = 2,
  DEALER = 3,
  INSTALLER = 4,
  END_USER = 5,
}

export interface User {
  id: string
  phone: string
  email: string
  nickname: string
  avatar: string
  role: Role
  parentId?: string
  regionId?: string
  status: number
  timezone: string
  lastLoginAt: string
  createdAt: string
}

export interface Device {
  id: string
  sn: string
  model: string
  ratedPower: number
  firmwareVersion: string
  firmware_arm?: string
  firmware_esp?: string
  main_version?: string
  status: 'online' | 'offline' | 'fault'
  lastOnlineAt: string
  userId: string
  installerId: string
  stationId: string
}

export interface Firmware {
  id: string
  model: string
  version: string
  main_version: string
  target_chip: string
  fileUrl: string
  fileSize: number
  fileMd5: string
  fileSha256: string
  changelog: string
  forceUpdate: boolean
  createdAt: string
}

export interface DeviceUpgrade {
  id: string
  device_sn: string
  firmware_id: number
  firmware_version: string
  target_chip: string
  old_version: string
  status: string // pending/downloading/upgrading/success/failed/cancelled
  progress: number
  error_message: string
  retry_count: number
  pushed_by: string | null
  started_at: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
  upgrade_package_id?: number | null
  task_id?: number | null
  // 聚合字段（Dashboard 列表用）
  device_model?: string
  total_devices?: number
  success_count?: number
  failed_count?: number
  pending_count?: number
  // 设备当前芯片版本（详情用）
  current_arm_version?: string
  current_esp_version?: string
  // 升级包相关
  package_main_version?: string
}

export interface UpgradeTask {
  id: string
  name: string
  task_type: 'single' | 'package'
  firmware_id?: number | null
  package_id?: number | null
  model: string
  target_version: string
  status: string // draft/pending/scheduled/running/completed/partial_success/failed/cancelled
  execute_mode: string // immediate/scheduled/manual
  scheduled_at?: string | null
  rollout_percent: number
  total_devices: number
  success_count: number
  failed_count: number
  created_by?: number | null
  created_at: string
  executed_at?: string | null
  completed_at?: string | null
  updated_at: string
  // 关联信息
  firmware_version?: string
  firmware_target_chip?: string
  package_main_version?: string
  package_items?: UpgradePackageItem[]
  // 来源（新增）
  source?: 'admin' | 'app' | 'local'
}

export interface UpgradePackage {
  id: string
  model: string
  main_version: string
  changelog: string
  is_force: boolean
  status: number
  created_by: number
  created_at: string
  updated_at: string
  items?: UpgradePackageItem[]
  // 新增字段
  user_version?: string
  user_changelog?: string
  is_published?: boolean
  rollout_type?: 'all' | 'model' | 'user' | 'device'
  rollout_targets?: any
}

export interface UpgradePackageItem {
  id: string
  package_id: number
  firmware_id: number
  target_chip: string
  firmware_version: string
  file_url?: string
  file_size?: number
  file_md5?: string
  file_sha256?: string
}

export interface Alert {
  id: string
  deviceSn: string
  alarmLevel: string
  faultCode: string
  faultMessage: string
  status: string
  occurredAt: string
}

export interface WorkOrder {
  id: string
  title: string
  description: string
  priority: string
  status: string
  createdAt: string
  sla_deadline?: string
  sla_overdue_count?: number
  template_type?: string
  attachments?: { name: string; url: string; type: string; uploadedAt: string }[]
}

export interface PaginatedResponse<T> {
  items: T[]
  total: number
  page: number
  page_size: number
}

export interface PublishPackageRequest {
  is_published: boolean
  rollout_type: 'all' | 'model' | 'user' | 'device'
  rollout_targets?: string
  auto_push?: boolean
  rollout_percent?: number
}

export interface ApiResponse<T> {
  code: number;      // 后端返回 0=成功，非0=错误
  message: string;
  data?: T;
}
