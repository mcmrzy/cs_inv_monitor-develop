import api from './api'

export const otaApi = {
  getFirmwares: (params?: any) => api.get('/firmwares', { params }),
  uploadFirmware: (formData: FormData) =>
    api.post('/firmwares', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  deleteFirmware: (id: string | number) => api.delete(`/firmwares/${id}`),
  getTasks: (params?: any) => api.get('/ota/tasks', { params }),
  getTaskDetail: (id: string) => api.get(`/ota/tasks/${id}`),
  getTaskDevices: (id: string, params?: any) => api.get(`/ota/tasks/${id}/devices`, { params }),
  createTask: (data: any) => api.post('/ota/tasks', data),
  executeTask: (id: string) => api.post(`/ota/tasks/${id}/execute`),
  cancelTask: (id: string) => api.post(`/ota/tasks/${id}/cancel`),
  retryDevice: (taskId: string, deviceSn: string) => api.post(`/ota/tasks/${taskId}/retry/${deviceSn}`),
  rollbackTask: (id: string) => api.post(`/ota/tasks/${id}/rollback`),
  listFirmware: (params?: any) => api.get('/firmwares', { params }),
  listTasks: (params?: any) => api.get('/ota/tasks', { params }),
  getTask: (id: string) => api.get(`/ota/tasks/${id}`),
  getAllFirmware: () => api.get('/firmwares', { params: { pageSize: 9999 } }),
}
