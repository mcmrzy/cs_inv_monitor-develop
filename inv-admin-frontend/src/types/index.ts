export enum Role {
  SUPER_ADMIN = 0,
  AGENT = 1,
  INSTALLER = 2,
  END_USER = 3,
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
  lastLoginAt: string
  createdAt: string
}

export interface Device {
  id: string
  sn: string
  model: string
  ratedPower: number
  firmwareVersion: string
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
  fileUrl: string
  fileSize: number
  fileMd5: string
  fileSha256: string
  changelog: string
  forceUpdate: boolean
  createdAt: string
}

export interface OtaTask {
  id: string
  name: string
  firmwareId: string
  status: string
  totalDevices: number
  successCount: number
  failedCount: number
  pushStrategy: string
  pushPercentage: number
  batchSize: number
  createdAt: string
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
  pageSize: number
}

export interface ApiResponse<T> {
  success: boolean
  data?: T
  message?: string
}
