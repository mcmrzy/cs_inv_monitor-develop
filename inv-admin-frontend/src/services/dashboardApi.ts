import api from './api'

export const dashboardApi = {
  getStatistics: () => api.get('/dashboard/statistics'),
  getTrend: (type: string) => api.get('/dashboard/trend', { params: { type } }),
  getDeviceDistribution: () => api.get('/dashboard/device-distribution'),
  getBigScreen: () => api.get('/dashboard/big-screen'),
  compareDevices: (params: any) => api.get('/dashboard/compare', { params }),
}
