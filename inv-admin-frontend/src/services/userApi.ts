import api from './api'

export const userApi = {
  list: (params?: any) => api.get('/users', { params }),
  get: (id: number) => api.get(`/users/${id}`),
  create: (data: any) => api.post('/users', data),
  update: (id: string | number, data: any) => api.patch(`/users/${id}`, data),
  delete: (id: string | number) => api.delete(`/users/${id}`),
  resetPassword: (id: number, data: { password: string }) => api.put(`/users/${id}/password`, { newPassword: data.password }),
  toggleStatus: (id: string | number, newStatus: number) => api.put(`/users/${id}/toggle`, { status: newStatus }),
  getInstallers: () => api.get('/users', { params: { role: 2 } }),
}
