import api from './api'
import { Role } from '@/types'

export const userApi = {
  list: (params?: any) => api.get('/users', { params, expectedDataShape: 'page' }),
  get: (id: number) => api.get(`/users/${id}`, { expectedDataShape: 'object' }),
  create: (data: any) => api.post('/users', data),
  update: (id: string | number, data: any) => api.patch(`/users/${id}`, data),
  delete: (id: string | number) => api.delete(`/users/${id}`),
  resetPassword: (id: number, data: { password: string }) => api.put(`/users/${id}/password`, { newPassword: data.password }),
  toggleStatus: (id: string | number, newStatus: number) => api.put(`/users/${id}/toggle`, { status: newStatus }),
  getInstallers: () => api.get('/users', { params: { role: Role.INSTALLER }, expectedDataShape: 'page' }),
  getChildren: (id: string | number, params?: any) => api.get(`/users/${id}/children`, { params, expectedDataShape: 'page' }),
  updateParent: (id: string | number, parentId: number | null) => api.put(`/users/${id}/parent`, { parentId }),
  getStationOwners: () => api.get('/users', { params: { role: 'station_owner' }, expectedDataShape: 'page' }),
}
