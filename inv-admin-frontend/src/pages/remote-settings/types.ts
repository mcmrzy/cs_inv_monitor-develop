// 远程参数设置页面 - 类型定义
import type { DeviceModelItem, ModelFieldCapability, ModelCommandCapability } from '@/services/modelApi'

// Re-export 来自现有类型的定义，方便页面内部引用
export type { SchemaArg } from '@/types'
export type { DeviceModelItem, ModelFieldCapability, ModelCommandCapability }

// 型号配置响应（对应后端 GET /api/v1/admin/models/:id/config）
export interface ModelConfigResponse {
  model: DeviceModelItem
  fields: ModelFieldCapability[]
}

// 页面状态
export type RemoteSettingsTab = 'fields' | 'commands' | 'devices'

// 字段分组颜色映射
export const GROUP_COLORS: Record<string, string> = {
  telemetry: '#4f46e5',
  control: '#10b981',
  status: '#f59e0b',
  grid: '#06b6d4',
  battery: '#7c3aed',
  output: '#ec4899',
  default: '#8c8c8c',
}

// 分组图标映射（Ant Design icon 名称，在组件中动态引用）
export const GROUP_ICONS: Record<string, string> = {
  telemetry: 'DashboardOutlined',
  control: 'ToolOutlined',
  status: 'InfoCircleOutlined',
  grid: 'ThunderboltOutlined',
  battery: 'FireOutlined',
  output: 'ExportOutlined',
}

// 统一视觉规范
export const DS = {
  primary: '#4f46e5',
  primaryLight: '#eef2ff',
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

// 命令风险等级渐变
export const RISK_GRADIENTS: Record<number, string> = {
  1: 'linear-gradient(90deg, #10b981, #34d399)',
  2: 'linear-gradient(90deg, #f59e0b, #fbbf24)',
  3: 'linear-gradient(90deg, #ef4444, #f87171)',
}
