import api from './api'

export const dashboardApi = {
  getStatistics: () => api.get('/dashboard/statistics'),
  getTrend: (type: string) => api.get('/dashboard/trend', { params: { type } }),
  getDeviceDistribution: () => api.get('/dashboard/device-distribution'),
  getBigScreen: () => api.get('/dashboard/big-screen'),
  compareDevices: (params: any) => api.get('/dashboard/compare', { params }),
  getEnergyStats: (params?: { type?: string; stationId?: number }) => api.get('/dashboard/energy-stats', { params }),
  getStationRanking: (params?: { period?: string; limit?: number }) => api.get('/dashboard/station-ranking', { params }),
  getEnergyFlow: (params: { date: string; stationId?: string; deviceSn?: string }) => api.get('/dashboard/energy-flow', { params }),
}
