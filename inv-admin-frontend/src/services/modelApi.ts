import api from './api'

export interface DeviceModelItem {
  id: number
  model_code: string
  model_name: string
  manufacturer: string
  category: string
  rated_power_kw: number
  description: string
  is_active: boolean
  created_at: string
  updated_at: string
  device_count?: number
}

export interface DeviceModelFieldItem {
  id: number
  model_id: number
  field_key: string
  field_name: string
  field_type: 'int' | 'float' | 'string' | 'bool'
  unit: string
  sort: number
  is_show: boolean
  is_control: boolean
  parse_rule: string
  created_at: string
  updated_at: string
}

export const modelApi = {
  listModels: () => api.get('/models'),
  getModel: (id: number) => api.get(`/models/${id}`),
  createModel: (data: Partial<DeviceModelItem>) => api.post('/models', data),
  updateModel: (id: number, data: Partial<DeviceModelItem>) => api.put(`/models/${id}`, data),
  deleteModel: (id: number) => api.delete(`/models/${id}`),

  getFields: (modelId: number) => api.get(`/models/${modelId}/fields`),
  createField: (modelId: number, data: Partial<DeviceModelFieldItem>) => api.post(`/models/${modelId}/fields`, data),
  updateField: (modelId: number, fieldId: number, data: Partial<DeviceModelFieldItem>) => api.put(`/models/${modelId}/fields/${fieldId}`, data),
  deleteField: (modelId: number, fieldId: number) => api.delete(`/models/${modelId}/fields/${fieldId}`),
  batchUpdateFields: (modelId: number, fields: Partial<DeviceModelFieldItem>[]) => api.put(`/models/${modelId}/fields/batch`, { fields }),
}
