import api from './api'

export const alertApi = {
  list: (params?: any) => api.get('/alerts', { params }),
  getStats: () => api.get('/alerts/stats'),
  handle: (id: number) => api.post(`/alerts/${id}/acknowledge`),
  ignore: (id: number) => api.post(`/alerts/${id}/ignore`),
  delete: (id: number) => api.delete(`/alerts/${id}`),
  clearAll: () => api.delete('/alerts/clear'),
}

export const notificationApi = {
  list: (params?: any) => api.get('/notifications', { params }),
  getStats: () => api.get('/notifications/stats'),
  delete: (id: number) => api.delete(`/notifications/${id}`),
  clearAll: () => api.delete('/notifications/clear'),
}
