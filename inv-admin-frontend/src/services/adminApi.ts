import api from './api'

export interface AuditLog {
  id: number
  userId: number
  username: string
  action: string
  resource: string
  resourceId: string
  details: string
  ipAddress: string
  createdAt: string
}

export interface SystemHealth {
  uptime: number
  memoryUsage: number
  cpuUsage: number
  database: boolean
  redis: boolean
  mqtt: boolean
  version: string
  lastCheckAt: string
}

export interface Tenant {
  id: number
  phone: string
  nickname: string
  email: string
  status: number
  subUserCount: number
  deviceCount: number
  deviceLimit: number | null
  userLimit: number | null
  createdAt: string
  lastLoginAt: string
}

export const adminApi = {
  getAuditLogs: (params?: any) => api.get('/admin/logs', { params, expectedDataShape: 'page' }),
  exportAuditLogs: (params?: any) => api.get('/admin/logs/export', { params, responseType: 'blob' }),
  getSystemHealth: () => api.get('/admin/system-health', { expectedDataShape: 'object' }),
  getSystemConfig: () => api.get('/admin/system-config', { expectedDataShape: 'object' }),
  updateSystemConfig: (data: any) => api.patch('/admin/system-config', data),

  getTenants: (params?: any) => api.get('/admin/tenants', { params, expectedDataShape: 'page' }),
  createTenant: (data: any) => api.post('/admin/tenants', data),
  updateTenant: (id: number, data: any) => api.patch(`/admin/tenants/${id}`, data),
  toggleTenant: (id: number) => api.post(`/admin/tenants/${id}/toggle`),
  getMetrics: () => api.get('/admin/metrics', { expectedDataShape: 'object' }),

  getAllPermissions: () => api.get('/admin/permissions', { expectedDataShape: 'array' }),
  getRolePermissions: (role: number) => api.get(`/admin/permissions/${role}`, { expectedDataShape: 'array' }),
  updateRolePermissions: (role: number, data: any) => api.put(`/admin/permissions/${role}`, data),
  togglePermission: (role: number, data: any) => api.post(`/admin/permissions/${role}/toggle`, data),
  getRouteGroups: () => api.get('/admin/route-groups', { expectedDataShape: 'object' }),
}
