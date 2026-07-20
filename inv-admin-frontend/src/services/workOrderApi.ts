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
  priority: string
  defaultFields: string[]
  estimatedHours: number
}

const workOrderTransitions: Record<string, string[]> = {
  open: ['in_progress', 'closed'],
  in_progress: ['open', 'resolved', 'closed'],
  resolved: ['in_progress', 'closed'],
  closed: [],
}

export const allowedWorkOrderStatuses = (status: string): string[] =>
  workOrderTransitions[status] ?? []

export const canMutateWorkOrder = (
  userId: string,
  role: number,
  order: Pick<WorkOrderDetail, 'creatorId' | 'assigneeId'>,
): boolean => {
  const id = Number(userId)
  if (!Number.isSafeInteger(id) || id <= 0) return false
  if (role >= 0 && role <= 3) return true
  if (role === 4) return order.assigneeId === id
  if (role === 5) return order.creatorId === id
  return false
}

export const workOrderApi = {
  list: (params?: any) => api.get('/work-orders', { params, expectedDataShape: 'page' }),
  getDetail: (id: string) => api.get(`/work-orders/${id}`, { expectedDataShape: 'object' }),
  create: (data: any) => api.post('/work-orders', data),
  update: (id: string, data: any) => api.patch(`/work-orders/${id}`, data),
  updateStatus: (id: string, status: string, expectedVersion?: number, idempotencyKey?: string) =>
    api.patch(`/work-orders/${id}/status`, {
      status,
      ...(expectedVersion === undefined ? {} : { expectedVersion }),
    }, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined),
  getStats: () => api.get('/work-orders/stats', { expectedDataShape: 'object' }),
  getTemplates: () => api.get('/work-orders/templates', { expectedDataShape: 'array' }),
  uploadAttachment: (id: string, formData: FormData) =>
    api.post(`/work-orders/${id}/attachments`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    }),
  downloadAttachment: (orderId: string, attachmentId: string) =>
    api.get(`/work-orders/${orderId}/attachments/${attachmentId}`, { responseType: 'blob' }),
  escalate: (id: string) => api.post(`/work-orders/${id}/escalate`),
}
