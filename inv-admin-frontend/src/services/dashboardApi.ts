import api from './api'

export const dashboardApi = {
  getStatistics: () => api.get('/dashboard/statistics', { expectedDataShape: 'object' }),
  getTrend: (type: string) => api.get('/dashboard/trend', { params: { type }, expectedDataShape: 'array' }),
  getDeviceDistribution: () => api.get('/dashboard/device-distribution', { expectedDataShape: 'object' }),
  getBigScreen: () => api.get('/dashboard/big-screen', { expectedDataShape: 'object' }),
  compareDevices: (params: any) => api.get('/dashboard/compare', { params }),
  getEnergyStats: (params?: { type?: string; stationId?: number }) => api.get('/dashboard/energy-stats', { params, expectedDataShape: 'object' }),
  getStationRanking: (params?: { period?: string; limit?: number }) => api.get('/dashboard/station-ranking', { params, expectedDataShape: 'array' }),
  getEnergyFlow: (params: { date: string; stationId?: string; deviceSn?: string }) => api.get('/dashboard/energy-flow', { params, expectedDataShape: 'object' }),
}
