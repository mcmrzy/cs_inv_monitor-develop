import api from './api'

export const parallelApi = {
  getGroups: (params?: any) => api.get('/parallel-groups', { params }),
  getGroup: (id: number) => api.get(`/parallel-groups/${id}`),
  createGroup: (data: any) => api.post('/parallel-groups', data),
  updateGroup: (id: number, data: any) => api.patch(`/parallel-groups/${id}`, data),
  deleteGroup: (id: number) => api.delete(`/parallel-groups/${id}`),
  syncParams: (id: number, data?: any) => api.post(`/parallel-groups/${id}/sync`, data || {}),
  getStatus: (id: number) => api.get(`/parallel-groups/${id}/status`),
  getAlerts: (id: number, params?: any) => api.get(`/parallel-groups/${id}/alerts`, { params }),
}
