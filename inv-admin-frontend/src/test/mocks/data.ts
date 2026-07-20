/**
 * 标准测试数据集
 *
 * 提供项目中各实体类型的 mock 数据，用于单元测试和集成测试。
 * 所有数据均符合 `@/types` 中定义的接口结构。
 */

import type { User, Device, Firmware, Alert, WorkOrder, UpgradeTask, PaginatedResponse } from '@/types'
import { Role } from '@/types'

/** 超级管理员用户 */
export const mockAdminUser: User = {
  id: '1',
  phone: '13800000001',
  email: 'admin@example.com',
  nickname: '超级管理员',
  avatar: '',
  role: Role.SUPER_ADMIN,
  status: 1,
  timezone: 'Asia/Shanghai',
  lastLoginAt: '2026-01-01T00:00:00Z',
  createdAt: '2025-01-01T00:00:00Z',
}

/** 管理员用户 */
export const mockManagerUser: User = {
  id: '2',
  phone: '13800000002',
  email: 'manager@example.com',
  nickname: '测试管理员',
  avatar: '',
  role: Role.ADMIN,
  status: 1,
  timezone: 'Asia/Shanghai',
  lastLoginAt: '2026-01-01T00:00:00Z',
  createdAt: '2025-01-01T00:00:00Z',
}

/** 普通安装商用户 */
export const mockInstallerUser: User = {
  id: '3',
  phone: '13800000003',
  email: 'installer@example.com',
  nickname: '测试安装商',
  avatar: '',
  role: Role.INSTALLER,
  parentId: '2',
  status: 1,
  timezone: 'Asia/Shanghai',
  lastLoginAt: '2026-01-01T00:00:00Z',
  createdAt: '2025-01-01T00:00:00Z',
}

/** 终端用户 */
export const mockEndUser: User = {
  id: '4',
  phone: '13800000004',
  email: 'user@example.com',
  nickname: '测试终端用户',
  avatar: '',
  role: Role.END_USER,
  parentId: '3',
  status: 1,
  timezone: 'Asia/Shanghai',
  lastLoginAt: '2026-01-01T00:00:00Z',
  createdAt: '2025-01-01T00:00:00Z',
}

/** 用户列表 */
export const mockUsers: User[] = [mockAdminUser, mockManagerUser, mockInstallerUser, mockEndUser]

/** 在线设备 */
export const mockOnlineDevice: Device = {
  id: '1',
  sn: 'INV20250001',
  model: 'SG-5K-D',
  ratedPower: 5000,
  firmwareVersion: '1.2.3',
  firmware_arm: '1.2.3',
  firmware_esp: '1.0.1',
  main_version: '1.2.3',
  status: 'online',
  lastOnlineAt: '2026-01-01T12:00:00Z',
  userId: '4',
  installerId: '3',
  stationId: '1',
}

/** 离线设备 */
export const mockOfflineDevice: Device = {
  id: '2',
  sn: 'INV20250002',
  model: 'SG-10K-D',
  ratedPower: 10000,
  firmwareVersion: '1.1.0',
  firmware_arm: '1.1.0',
  firmware_esp: '1.0.0',
  main_version: '1.1.0',
  status: 'offline',
  lastOnlineAt: '2025-12-31T12:00:00Z',
  userId: '4',
  installerId: '3',
  stationId: '1',
}

/** 故障设备 */
export const mockFaultDevice: Device = {
  id: '3',
  sn: 'INV20250003',
  model: 'SG-5K-D',
  ratedPower: 5000,
  firmwareVersion: '1.0.0',
  firmware_arm: '1.0.0',
  firmware_esp: '1.0.0',
  main_version: '1.0.0',
  status: 'fault',
  lastOnlineAt: '2025-12-30T12:00:00Z',
  userId: '4',
  installerId: '3',
  stationId: '1',
}

/** 设备列表 */
export const mockDevices: Device[] = [mockOnlineDevice, mockOfflineDevice, mockFaultDevice]

/** ARM 固件 */
export const mockArmFirmware: Firmware = {
  id: '1',
  model: 'SG-5K-D',
  version: '2.0.0',
  main_version: '2.0.0',
  target_chip: 'arm',
  fileUrl: '/firmwares/arm-2.0.0.bin',
  fileSize: 1024000,
  fileMd5: 'd41d8cd98f00b204e9800998ecf8427e',
  fileSha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  security_version: 2,
  release_signature: 'mock-ed25519-signature',
  changelog: '修复了通信模块的稳定性问题',
  forceUpdate: false,
  createdAt: '2026-01-01T00:00:00Z',
}

/** ESP 固件 */
export const mockEspFirmware: Firmware = {
  id: '2',
  model: 'SG-5K-D',
  version: '1.5.0',
  main_version: '1.5.0',
  target_chip: 'esp',
  fileUrl: '/firmwares/esp-1.5.0.bin',
  fileSize: 512000,
  fileMd5: '098f6bcd4621d373cade4e832627b4f6',
  fileSha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
  security_version: 2,
  release_signature: 'mock-ed25519-signature',
  changelog: '新增 Wi-Fi 配网功能',
  forceUpdate: false,
  createdAt: '2026-01-02T00:00:00Z',
}

/** 固件列表 */
export const mockFirmwares: Firmware[] = [mockArmFirmware, mockEspFirmware]

/** 告警记录（同时包含 camelCase 和 snake_case 字段，兼容表格 dataIndex） */
export const mockAlert: Alert = {
  id: '1',
  deviceSn: 'INV20250001',
  device_sn: 'INV20250001',
  alarmLevel: 'warning',
  alarm_level: 'warning',
  faultCode: '6',
  fault_code: '6',
  faultMessage: '逆变器温度过高',
  fault_message: '逆变器温度过高',
  status: 0,
  occurredAt: '2026-01-01T10:00:00Z',
  occurred_at: '2026-01-01T10:00:00Z',
} as unknown as Alert

export const mockCriticalAlert: Alert = {
  id: '2',
  deviceSn: 'INV20250003',
  device_sn: 'INV20250003',
  alarmLevel: 'fault',
  alarm_level: 'fault',
  faultCode: '1',
  fault_code: '1',
  faultMessage: '逆变器过温保护',
  fault_message: '逆变器过温保护',
  status: 0,
  occurredAt: '2026-01-01T09:00:00Z',
  occurred_at: '2026-01-01T09:00:00Z',
} as unknown as Alert

/** 告警列表 */
export const mockAlerts: Alert[] = [mockAlert, mockCriticalAlert]

/** 工单 */
export const mockWorkOrder: WorkOrder = {
  id: '1',
  title: '设备离线故障排查',
  description: 'INV20250002 设备自 2025-12-31 起持续离线，需现场排查',
  priority: 'high',
  status: 'open',
  createdAt: '2026-01-01T08:00:00Z',
}

/** 工单列表 */
export const mockWorkOrders: WorkOrder[] = [mockWorkOrder]

/** OTA 升级任务 */
export const mockUpgradeTask: UpgradeTask = {
  id: '1',
  name: '批量升级 SG-5K-D',
  task_type: 'single',
  firmware_id: 1,
  model: 'SG-5K-D',
  target_version: '2.0.0',
  status: 'running',
  execute_mode: 'immediate',
  rollout_percent: 100,
  total_devices: 2,
  success_count: 1,
  failed_count: 0,
  created_at: '2026-01-01T08:00:00Z',
  updated_at: '2026-01-01T08:10:00Z',
}

/** 升级任务列表 */
export const mockUpgradeTasks: UpgradeTask[] = [mockUpgradeTask]

/**
 * 模拟登录响应数据
 */
export const mockLoginResponse = {
  code: 0,
  message: 'success',
  data: {
    token: 'mock-jwt-token',
    refresh_token: 'mock-refresh-token',
    user: mockAdminUser,
    permissions: ['dashboard:view', 'devices:view', 'firmware:view', 'alerts:view', 'users:view', 'admin:view'],
  },
}

/** 告警统计 */
export const mockAlertStats = {
  total: 15,
  unhandled: 5,
  handled: 8,
  critical: 2,
}

/** 仪表盘统计 */
export const mockDashboardStats = {
  totalDevices: 120,
  onlineDevices: 95,
  offlineDevices: 20,
  faultDevices: 5,
  totalStations: 8,
  totalEnergy: 12500.5,
}

/**
 * 构造分页响应
 */
export function paginatedResponse<T>(items: T[], total?: number): PaginatedResponse<T> {
  return {
    items,
    total: total ?? items.length,
    page: 1,
    page_size: 20,
  }
}
