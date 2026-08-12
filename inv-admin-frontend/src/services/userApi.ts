import api from './api'

export const userApi = {
  list: (params?: any) => api.get('/users', { params, expectedDataShape: 'page' }),
  get: (id: number) => api.get(`/users/${id}`, { expectedDataShape: 'object' }),
  // TODO: 后端未实现 POST /users 接口，需要添加 CreateUser 方法和路由
  create: (data: any) => api.post('/users', data),
  update: (id: string | number, data: any) => api.patch(`/users/${id}`, data),
  // TODO: 后端未实现 DELETE /users/:id 接口，需要添加 DeleteUser 方法和路由
  delete: (id: string | number) => api.delete(`/users/${id}`),
  resetPassword: (id: number, data: { password: string }) => api.put(`/users/${id}/password`, { newPassword: data.password }),
  toggleStatus: (id: string | number, newStatus: number) => api.put(`/users/${id}/toggle`, { status: newStatus }),
  updateMemberRole: (membershipId: number, role: string) =>
    api.put(`/members/memberships/${membershipId}/role`, { role }),
  getInstallers: () => api.get('/users', { params: { role: 4 }, expectedDataShape: 'page' }),
  getChildren: (id: string | number, params?: any) => api.get(`/users/${id}/children`, { params, expectedDataShape: 'page' }),
  updateParent: (id: string | number, parentId: number | null) => api.put(`/users/${id}/parent`, { parentId }),
  getStationOwners: () => api.get('/users', { params: { role: 'station_owner' }, expectedDataShape: 'page' }),
}
