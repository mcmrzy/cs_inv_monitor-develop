import api from './api'

export const otaApi = {
  // 固件管理
  listFirmware: (params?: any) => api.get('/firmwares', { params }),
  getFirmwares: (params?: any) => api.get('/firmwares', { params }),
  uploadFirmware: (formData: FormData) =>
    api.post('/firmwares', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  createFirmware: (data: any) => api.post('/firmwares', data),
  deleteFirmware: (id: string | number) => api.delete(`/firmwares/${id}`),
  getAllFirmware: () => api.get('/firmwares', { params: { pageSize: 9999 } }),

  // 升级管理（替代旧 /tasks）
  getUpgradeDashboard: (params?: any) => api.get('/ota/upgrades/dashboard', { params }),
  pushUpgrade: (data: { firmware_id: number; device_sns: string[]; immediate?: boolean }) =>
    api.post('/ota/upgrades/push', data),
  getFirmwareUpgradeDetails: (firmwareId: number) => api.get(`/ota/upgrades/firmware/${firmwareId}`),
  retryUpgrade: (data: { firmware_id: number; device_sns: string[] }) =>
    api.post('/ota/upgrades/retry', data),
  cancelUpgrade: (data: { device_sn: string; firmware_id: number }) =>
    api.post('/ota/upgrades/cancel', data),
  deleteUpgradeByFirmware: (firmwareId: number) => api.delete(`/ota/upgrades/firmware/${firmwareId}`),

  // App版本管理
  getAppVersions: (platform?: string) => api.get('/ota/app/versions', { params: platform ? { platform } : {} }),
  createAppVersion: (data: any) => api.post('/ota/app/versions', data),
  deleteAppVersion: (id: number) => api.delete(`/ota/app/versions/${id}`),
  updateAppVersionRollout: (id: number, percentage: number) => api.put(`/ota/app/versions/${id}/rollout`, { percentage }),
  rollbackAppVersion: (id: number) => api.post(`/ota/app/versions/${id}/rollback`),
  restoreAppVersion: (id: number, percentage?: number) => api.post(`/ota/app/versions/${id}/restore`, { percentage: percentage || 100 }),

  // 升级包管理
  listPackages: (params?: any) => api.get('/ota/packages', { params }),
  getPackage: (id: number) => api.get(`/ota/packages/${id}`),
  createPackage: (data: { model: string; firmware_ids: number[]; changelog?: string; is_force?: boolean }) =>
    api.post('/ota/packages', data),
  deletePackage: (id: number) => api.delete(`/ota/packages/${id}`),
  pushPackageUpgrade: (data: { package_id: number; device_sns: string[]; immediate?: boolean; rollout_percent?: number }) =>
    api.post('/ota/packages/push', data),
  getPackageUpgradeDetails: (packageId: number) => api.get(`/ota/packages/${packageId}/details`),
  rollbackPackage: (id: number, data: { immediate?: boolean }) => api.post(`/ota/packages/${id}/rollback`, data),

  // 升级任务管理（新统一接口）
  listTasks: (params?: any) => api.get('/ota/tasks', { params }),
  createTask: (data: {
    name?: string
    task_type: 'single' | 'package'
    firmware_id?: number
    package_id?: number
    device_sns: string[]
    execute_mode?: string
    scheduled_at?: string
    rollout_percent?: number
  }) => api.post('/ota/tasks', data),
  getTask: (id: number | string) => api.get(`/ota/tasks/${id}`),
  getTaskDevices: (id: number | string, params?: any) => api.get(`/ota/tasks/${id}/devices`, { params }),
  executeTask: (id: number | string) => api.post(`/ota/tasks/${id}/execute`),
  cancelTask: (id: number | string) => api.post(`/ota/tasks/${id}/cancel`),
  retryTask: (id: number | string) => api.post(`/ota/tasks/${id}/retry`),
  deleteTask: (id: number | string) => api.delete(`/ota/tasks/${id}`),
  getTaskStats: () => api.get('/ota/tasks/stats'),
}
