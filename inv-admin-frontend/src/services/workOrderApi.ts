import api from './api'

export interface WorkOrderTimelineItem {
  status: string
  operator: string
  timestamp: string
  remark?: string
}

export interface WorkOrderAttachment {
  name: string
  url: string
  type: string
  uploadedAt: string
}

export interface WorkOrderDetail {
  id: string
  title: string
  description: string
  status: string
  priority: string
  assigneeId: number
  assigneeName: string
  creatorId: number
  creatorName: string
  deviceSn: string
  createdAt: string
  updatedAt: string
  slaDeadline?: string
  slaOverdueCount?: number
  templateType?: string
  resolution?: string
  timeline?: WorkOrderTimelineItem[]
  attachments?: WorkOrderAttachment[]
}

export interface WorkOrderTemplate {
  templateId: string
  title: string
  description: string
  priority: number
  defaultFields: string[]
  estimatedHours: number
}

export const workOrderApi = {
  list: (params?: any) => api.get('/work-orders', { params }),
  getDetail: (id: string) => api.get(`/work-orders/${id}`),
  create: (data: any) => api.post('/work-orders', data),
  update: (id: string, data: any) => api.patch(`/work-orders/${id}`, data),
  updateStatus: (id: string, status: string) => api.patch(`/work-orders/${id}/status`, { status }),
  getStats: () => api.get('/work-orders/stats'),
  getTemplates: () => api.get('/work-orders/templates'),
  uploadAttachment: (id: string, formData: FormData) =>
    api.post(`/work-orders/${id}/attachments`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  escalate: (id: string) => api.post(`/work-orders/${id}/escalate`),
}
