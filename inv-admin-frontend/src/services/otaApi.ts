import api from './api'

export const otaApi = {
  getFirmwares: (params?: any) => api.get('/firmwares', { params }),
  uploadFirmware: (formData: FormData) =>
    api.post('/firmwares', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  createFirmware: (data: any) => api.post('/firmwares', data),
  deleteFirmware: (id: string | number) => api.delete(`/firmwares/${id}`),
  getTasks: (params?: any) => api.get('/ota/tasks', { params }),
  getTaskDetail: (id: string) => api.get(`/ota/tasks/${id}`),
  getTaskDevices: (id: string, params?: any) => api.get(`/ota/tasks/${id}/devices`, { params }),
  createTask: (data: any) => api.post('/ota/tasks', data),
  executeTask: (id: string) => api.post(`/ota/tasks/${id}/dispatch`),
  notifyDevices: (id: string) => api.post(`/ota/tasks/${id}/notify`),
  cancelTask: (id: string) => api.post(`/ota/tasks/${id}/cancel`),
  deleteTask: (id: string) => api.delete(`/ota/tasks/${id}`),
  retryDevice: (taskId: string, deviceSn: string) => api.post(`/ota/tasks/${taskId}/retry/${deviceSn}`),
  rollbackTask: (id: string) => api.post(`/ota/tasks/${id}/rollback`),
  listFirmware: (params?: any) => api.get('/firmwares', { params }),
  listTasks: (params?: any) => api.get('/ota/tasks', { params }),
  getTask: (id: string) => api.get(`/ota/tasks/${id}`),
  getAllFirmware: () => api.get('/firmwares', { params: { pageSize: 9999 } }),

  // App版本管理
  getAppVersions: (platform?: string) => api.get('/ota/app/versions', { params: platform ? { platform } : {} }),
  createAppVersion: (data: any) => api.post('/ota/app/versions', data),
  deleteAppVersion: (id: number) => api.delete(`/ota/app/versions/${id}`),
  updateAppVersionRollout: (id: number, percentage: number) => api.put(`/ota/app/versions/${id}/rollout`, { percentage }),
  rollbackAppVersion: (id: number) => api.post(`/ota/app/versions/${id}/rollback`),
  restoreAppVersion: (id: number, percentage?: number) => api.post(`/ota/app/versions/${id}/restore`, { percentage: percentage || 100 }),
}
