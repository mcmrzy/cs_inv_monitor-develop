// 远程参数设置页面 - 类型定义（v1.0.26 协议）

// ── 控制状态（desired vs reported）──
export interface ControlState {
  device_sn: string
  protocol_version?: number
  desired: Record<string, unknown>
  reported: Record<string, unknown>
  sync_status: 'synced' | 'pending' | 'drifted' | 'unknown'
  desired_version?: number
  reported_revision?: number
  desired_at?: string
  reported_at?: string
  last_task_id?: string
  updated_at?: string
}

// ── 命令执行记录 ──
export interface CommandRecord {
  task_id: string
  command_code: string
  stage: 'pending' | 'acknowledged' | 'executing' | 'completed'
  success?: boolean
  code?: string
  result?: unknown[]
  params?: Record<string, unknown>
  created_at: string
  completed_at?: string
}

// ── 设备信息（对齐后端 Device struct JSON 字段）──
export interface DeviceItem {
  id: number
  sn: string
  model: string
  model_id: number
  manufacturer: string
  firmware_arm: string
  firmware_esp: string
  firmware_dsp: string
  firmware_bms: string
  main_version: string
  device_type: string
  rated_power: number
  rated_voltage: number
  rated_freq: number
  battery_voltage: number
  battery_type: string
  cell_count: number
  station_id?: number
  station_name: string
  status: number
  current_power: number
  daily_energy: number
  last_online_at?: string
  timezone: string
  created_at: string
  updated_at: string
  // 前端扩展（realtime 注入）
  realtime_power?: number
}

// ── 页面 Tab ──
export type RemoteSettingsTab = 'runtime' | 'battery' | 'status' | 'parallel'

// ── 命令下发请求 ──
export interface SendCommandRequest {
  command_code: string
  params?: Record<string, unknown>
}

// ── 命令结果（设备上报） ──
export interface CommandResult {
  task_id: string
  cmd: string
  success: boolean
  message?: string
  data?: string
  timestamp: number
  ack?: boolean
  reason?: string
}

// ── 同步状态颜色映射 ──
export const SYNC_STATUS_MAP: Record<string, { color: string; label_zh: string }> = {
  synced: { color: '#22c55e', label_zh: '已同步' },
  pending: { color: '#f59e0b', label_zh: '等待同步' },
  drifted: { color: '#ef4444', label_zh: '配置偏差' },
  unknown: { color: '#8c8c8c', label_zh: '未知' },
}

// ── 命令阶段颜色映射 ──
export const STAGE_MAP: Record<string, { color: string; label_zh: string }> = {
  pending: { color: 'default', label_zh: '等待中' },
  acknowledged: { color: 'processing', label_zh: '已确认' },
  executing: { color: 'warning', label_zh: '执行中' },
  completed: { color: 'success', label_zh: '已完成' },
}

// ── 统一视觉规范（保留供后续组件使用）──
export const DS = {
  primary: '#4f6ef7',
  primaryLight: '#eef0ff',
  secondary: '#7c3aed',
  success: '#10b981',
  warning: '#f59e0b',
  danger: '#ef4444',
  bgPage: '#f5f7fa',
  bgCard: '#ffffff',
  bgHover: '#f0f5ff',
  bgCode: '#f6f8fa',
  textPrimary: '#111827',
  textSecondary: '#6b7280',
  textMuted: '#9ca3af',
  border: '#e5e7eb',
  radiusCard: 12,
  radiusTag: 6,
  radiusBtn: 8,
  shadowCard: '0 1px 3px rgba(0,0,0,0.08), 0 4px 12px rgba(0,0,0,0.04)',
  shadowCardHover: '0 4px 12px rgba(0,0,0,0.10), 0 8px 24px rgba(0,0,0,0.06)',
  transition: 'all 0.2s ease',
} as const
