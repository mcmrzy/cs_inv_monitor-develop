import api from './api'
import type {
  FirmwareTaskRef,
  RollbackFirmwareRequest,
  TriggerFirmwareRequest,
  UpgradeHistoryQuery,
} from '@/types'

/**
 * 序列化升级历史筛选参数：省略空值，保证筛选在 API 层统一处理，
 * 组件不要自行拼接 query string。
 */
export function serializeUpgradeHistoryParams(
  params?: UpgradeHistoryQuery,
): Record<string, string | number> {
  const out: Record<string, string | number> = {}
  if (!params) return out
  if (params.device_sn) out.device_sn = params.device_sn
  if (params.target_chip) out.target_chip = params.target_chip
  if (params.status) out.status = params.status
  if (params.start_time) out.start_time = params.start_time
  if (params.end_time) out.end_time = params.end_time
  if (typeof params.page === 'number' && Number.isFinite(params.page)) out.page = params.page
  if (typeof params.page_size === 'number' && Number.isFinite(params.page_size)) out.page_size = params.page_size
  return out
}

/** 生成 OTA 写操作幂等键（trigger / rollback 共用） */
export function createOtaIdempotencyKey(prefix: string): string {
  const unique =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
  return `${prefix}-${unique}`
}

export const otaApi = {
  // ── 固件管理 ──
  listFirmware: (params?: any) => api.get('/ota/firmware', { params, expectedDataShape: 'array' }),
  getFirmwares: (params?: any) => api.get('/ota/firmware', { params, expectedDataShape: 'array' }),
  uploadFirmware: (formData: FormData) =>
    api.post('/ota/firmware', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  createFirmware: (data: any) => api.post('/ota/firmware', data),
  /** 仅 draft 可删除 */
  deleteFirmware: (id: string | number) => api.delete(`/ota/firmware/${id}`),
  getAllFirmware: () => api.get('/ota/firmware', { params: { page_size: 9999 }, expectedDataShape: 'array' }),
  /** 发布固件（draft/disabled → published） */
  publishFirmware: (id: string | number) => api.post(`/ota/firmware/${id}/publish`),
  /** 停用固件（published → disabled，保留历史） */
  disableFirmware: (id: string | number) => api.post(`/ota/firmware/${id}/disable`),

  // ── 独立模块固件升级 ──
  /** 设备四模块固件概览 */
  getFirmwareOverview: (sn: string) =>
    api.get(`/ota/devices/${encodeURIComponent(sn)}/firmware-overview`, { expectedDataShape: 'object' }),
  /** 设备可安装固件资源（可按 target_chip 过滤） */
  getFirmwareResources: (sn: string, targetChip?: string) =>
    api.get(`/ota/devices/${encodeURIComponent(sn)}/firmware-resources`, {
      params: targetChip ? { target_chip: targetChip } : {},
      expectedDataShape: 'array',
    }),
  /** 触发单模块/多模块固件升级 */
  triggerFirmwareUpgrade: (data: TriggerFirmwareRequest) =>
    api.post('/ota/trigger', data),
  /** 单模块固件回退（替代旧 package 回退） */
  rollbackFirmware: (data: RollbackFirmwareRequest) =>
    api.post('/ota/firmware/rollback', data),

  // ── 升级历史（筛选在 API 层序列化） ──
  /** 指定设备升级历史 */
  getDeviceUpgradeHistory: (sn: string, params?: UpgradeHistoryQuery) =>
    api.get(`/ota/devices/${encodeURIComponent(sn)}/history`, {
      params: serializeUpgradeHistoryParams(params),
      expectedDataShape: 'page',
    }),
  /** 授权范围内聚合升级历史 */
  listUpgradeHistory: (params?: UpgradeHistoryQuery) =>
    api.get('/ota/history', {
      params: serializeUpgradeHistoryParams(params),
      expectedDataShape: 'page',
    }),

  // ── 升级管理（保留既有推送/重试/取消，供任务态使用） ──
  getUpgradeDashboard: (params?: any) => api.get('/ota/upgrades/dashboard', { params, expectedDataShape: 'object' }),
  pushUpgrade: (data: { firmware_id: number; device_sns: string[]; immediate?: boolean }) =>
    api.post('/ota/upgrades/push', data),
  getFirmwareUpgradeDetails: (firmwareId: number) => api.get(`/ota/upgrades/firmware/${firmwareId}`, { expectedDataShape: 'object' }),
  retryUpgrade: (data: { firmware_id: number; device_sns: string[] }) =>
    api.post('/ota/upgrades/retry', data),
  cancelUpgrade: (data: { device_sn: string; firmware_id: number }) =>
    api.post('/ota/upgrades/cancel', data),
  deleteUpgradeByFirmware: (firmwareId: number) => api.delete(`/ota/upgrades/firmware/${firmwareId}`),

  // ── App 版本管理 ──
  getAppVersions: (platform?: string) => api.get('/ota/app/versions', { params: platform ? { platform } : {}, expectedDataShape: 'array' }),
  /** 上传 Android 安装包：版本号/包名/体积/SHA-256 由服务端从 APK 解析 */
  uploadAppPackage: (formData: FormData) =>
    api.post('/ota/app/versions', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  createAppVersion: (data: any) => api.post('/ota/app/versions', data),
  deleteAppVersion: (id: number) => api.delete(`/ota/app/versions/${id}`),
  updateAppVersionRollout: (id: number, percentage: number) => api.put(`/ota/app/versions/${id}/rollout`, { percentage }),
  rollbackAppVersion: (id: number) => api.post(`/ota/app/versions/${id}/rollback`),
  restoreAppVersion: (id: number, percentage?: number) => api.post(`/ota/app/versions/${id}/restore`, { percentage: percentage || 100 }),

  // ── 升级任务管理 ──
  listTasks: (params?: any) => api.get('/ota/tasks', { params, expectedDataShape: 'page' }),
  createTask: (data: {
    name?: string
    task_type: 'single'
    firmware_id?: number
    device_sns: string[]
    execute_mode?: string
    scheduled_at?: string
    rollout_percent?: number
  }) => api.post('/ota/tasks', data),
  getTask: (id: number | string) => api.get(`/ota/tasks/${id}`, { expectedDataShape: 'object' }),
  getTaskDevices: (id: number | string, params?: any) => api.get(`/ota/tasks/${id}/devices`, { params, expectedDataShape: 'object' }),
  executeTask: (id: number | string) => api.post(`/ota/tasks/${id}/execute`),
  cancelTask: (id: number | string) => api.post(`/ota/tasks/${id}/cancel`),
  retryTask: (id: number | string) => api.post(`/ota/tasks/${id}/retry`),
  deleteTask: (id: number | string) => api.delete(`/ota/tasks/${id}`),
  getTaskStats: () => api.get('/ota/task-stats', { expectedDataShape: 'object' }),

  // ── 固件-设备关联查询 ──
  getDevicesByFirmware: (model: string, targetChip: string, version: string) =>
    api.get('/ota/firmware/by-device', { params: { model, target_chip: targetChip, version }, expectedDataShape: 'object' }),
}

export type OtaApi = typeof otaApi
export type { FirmwareTaskRef }
