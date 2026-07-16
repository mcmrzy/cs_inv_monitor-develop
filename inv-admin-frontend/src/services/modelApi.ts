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
  lifecycle_status?: 'draft' | 'active' | 'retired'
  heartbeat_protocol_id?: number
  lock_version?: number
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
  group_name: string
  control_params: Record<string, any>
  created_at: string
  updated_at: string
}

export interface DeviceModelProtocolItem {
  id: number
  model_id: number
  topic_pattern: string
  parse_type: 'json' | 'modbus' | 'custom'
  parse_config: Record<string, any>
  is_active: boolean
  created_at: string
}

export interface FieldCatalogItem {
  field_key: string
  field_type: string
  base_unit?: string
  category: string
  description?: string
  is_timeseries: boolean
  is_aggregatable: boolean
  allowed_aggregates: string[]
  status: 'active' | 'deprecated'
}

export interface ProtocolVersionItem {
  id: number
  protocol_code: string
  version: number
  schema_hash: string
  status: 'draft' | 'released' | 'retired'
  released_at?: string
  field_count: number
}

export interface ProtocolFieldInput {
  group_code: string
  field_index: number
  field_key: string
  wire_type: string
  scale?: number
  minimum?: number
  maximum?: number
  nullable?: boolean
  status?: string
}

export interface ModelFieldCapability {
  id: number
  model_id: number
  field_key: string
  field_type: string
  base_unit?: string
  category: string
  display_name_key?: string
  group_code: string
  display_unit?: string
  decimal_places: number
  sort_order: number
  is_supported: boolean
  is_visible: boolean
  show_realtime: boolean
  show_history: boolean
  allow_compare: boolean
  allow_alarm_rule: boolean
  default_chart: boolean
}

export interface ModelCommandCapability {
  id: number
  command_code: string
  display_name_key: string
  parameter_schema: Record<string, any>
  timeout_seconds: number
  risk_level: number
  requires_online: boolean
  is_enabled: boolean
}

export const modelApi = {
  // 型号 CRUD
  listModels: () => api.get('/models', { expectedDataShape: 'array' }),
  listModelsPublic: () => api.get('/models', { expectedDataShape: 'array' }),  // 不需要管理员权限，所有登录用户可用
  getModel: (id: number) => api.get(`/models/${id}`, { expectedDataShape: 'object' }),
  createModel: (data: Partial<DeviceModelItem>) => api.post('/models', data),
  updateModel: (id: number, data: Partial<DeviceModelItem>) => api.put(`/models/${id}`, data),
  deleteModel: (id: number) => api.delete(`/models/${id}`),

  // 字段 CRUD
  getFields: (modelId: number) => api.get(`/models/${modelId}/fields`, { expectedDataShape: 'array' }),
  createField: (modelId: number, data: Partial<DeviceModelFieldItem>) => api.post(`/models/${modelId}/fields`, data),
  updateField: (modelId: number, fieldId: number, data: Partial<DeviceModelFieldItem>) => api.put(`/models/${modelId}/fields/${fieldId}`, data),
  deleteField: (modelId: number, fieldId: number) => api.delete(`/models/${modelId}/fields/${fieldId}`),
  batchUpdateFields: (modelId: number, fields: Partial<DeviceModelFieldItem>[]) => api.put(`/models/${modelId}/fields/batch`, { fields }),
  getFieldCatalog: () => api.get('/field-catalog', { expectedDataShape: 'array' }),
  saveFieldCatalog: (data: Partial<FieldCatalogItem>) => api.post('/field-catalog', data),
  getFieldCapabilities: (modelId: number) => api.get(`/models/${modelId}/field-capabilities`, { expectedDataShape: 'array' }),
  updateFieldCapability: (modelId: number, fieldKey: string, data: Partial<ModelFieldCapability>) =>
    api.put(`/models/${modelId}/field-capabilities/${fieldKey}`, data),
  batchUpdateFieldCapabilities: (modelId: number, fields: Partial<ModelFieldCapability>[]) =>
    api.put(`/models/${modelId}/field-capabilities`, { fields }),
  getCommandCapabilities: (modelId: number) => api.get(`/models/${modelId}/commands-v2`, { expectedDataShape: 'array' }),
  updateCommandCapability: (modelId: number, commandCode: string, data: Partial<ModelCommandCapability>) =>
    api.put(`/models/${modelId}/commands-v2/${commandCode}`, data),
  saveCommandCapability: (modelId: number, data: Partial<ModelCommandCapability>) =>
    api.post(`/models/${modelId}/commands-v2`, data),
  getProtocolSchema: (modelId: number) => api.get(`/models/${modelId}/protocol-schema`, { expectedDataShape: 'object' }),
  listProtocolVersions: () => api.get('/protocol-versions', { expectedDataShape: 'array' }),
  createProtocolVersion: (data: { protocol_code: string; version: number; schema_hash: string; fields: ProtocolFieldInput[] }) =>
    api.post('/protocol-versions', data),
  releaseProtocolVersion: (protocolId: number) => api.post(`/protocol-versions/${protocolId}/release`),
  bindProtocolVersion: (modelId: number, protocolId: number) => api.put(`/models/${modelId}/protocol-version`, { protocol_id: protocolId }),
  getMigrationReport: (modelId: number) => api.get(`/models/${modelId}/migration-report`, { expectedDataShape: 'object' }),
  getDataPreview: (modelId: number) => api.get(`/models/${modelId}/data-preview`, { expectedDataShape: 'object' }),
  validateRegistry: (modelId: number) => api.post(`/models/${modelId}/validate`),
  activateRegistry: (modelId: number) => api.post(`/models/${modelId}/activate`),

  // 型号完整配置（字段列表）
  getModelConfig: (modelId: number) => api.get(`/models/${modelId}/config`, { expectedDataShape: 'object' }),

  // 协议 CRUD
  getProtocols: (modelId: number) => api.get(`/models/${modelId}/protocols`, { expectedDataShape: 'array' }),
  createProtocol: (modelId: number, data: Partial<DeviceModelProtocolItem>) => api.post(`/models/${modelId}/protocols`, data),
  updateProtocol: (modelId: number, protocolId: number, data: Partial<DeviceModelProtocolItem>) => api.put(`/models/${modelId}/protocols/${protocolId}`, data),
  deleteProtocol: (modelId: number, protocolId: number) => api.delete(`/models/${modelId}/protocols/${protocolId}`),
}
