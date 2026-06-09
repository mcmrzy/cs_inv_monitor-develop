import api from './api'

export const alertRuleApi = {
  getRules: (params?: any) => api.get('/alert-rules', { params }),
  createRule: (data: any) => api.post('/alert-rules', data),
  updateRule: (id: number, data: any) => api.put('/alert-rules/' + id, data),
  deleteRule: (id: number) => api.delete('/alert-rules/' + id),
}
