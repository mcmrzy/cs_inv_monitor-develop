import api from './api'

export const userApi = {
  getUsers: (params?: any) => api.get('/users', { params }),
  getUser: (id: number) => api.get(`/users/${id}`),
  createUser: (data: any) => api.post('/users', data),
  updateUser: (id: number, data: any) => api.patch(`/users/${id}`, data),
  deleteUser: (id: number) => api.delete(`/users/${id}`),
  resetPassword: (id: number, data: { password: string }) => api.put(`/users/${id}/password`, { newPassword: data.password }),
  list: (params?: any) => api.get('/users', { params }),
  create: (data: any) => api.post('/users', data),
  update: (id: string | number, data: any) => api.patch(`/users/${id}`, data),
  delete: (id: string | number) => api.delete(`/users/${id}`),
  toggleStatus: (id: string | number, newStatus: number) => api.put(`/users/${id}/toggle`, { status: newStatus }),
  getInstallers: () => api.get('/users', { params: { role: 2 } }),
}
