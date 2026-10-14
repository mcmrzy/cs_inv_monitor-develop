import api from './api'
import type { BoardType, CompatibilityWindow, HardwareHistory, HardwareImportPreview, HardwareImportRow, HardwareRegistry, RegistryMutation } from '@/types/hardware'
const data = <T,>(response: { data: { data?: T } }): T => response.data.data as T
export const hardwareApi = {
  getRegistry: (sn: string) => api.get(`/hardware/devices/${encodeURIComponent(sn)}`, { expectedDataShape: 'object' }).then(data<HardwareRegistry>),
  getHistory: (sn: string, page = 1) => api.get(`/hardware/devices/${encodeURIComponent(sn)}/history`, { params: { page, page_size: 10 }, expectedDataShape: 'page' }).then(data<{ items: HardwareHistory[]; total: number }>),
  listBoardTypes: (model?: string, target_chip?: string) => api.get('/hardware/board-types', { params: { model, target_chip }, expectedDataShape: 'array' }).then(data<BoardType[]>),
  createBoardType: (body: BoardType) => api.post('/hardware/board-types', body).then(data<BoardType>),
  mutateRegistry: (sn: string, action: 'verify' | 'corrections' | 'service-changes' | 'freeze', body: RegistryMutation) => api.post(`/hardware/devices/${encodeURIComponent(sn)}/${action}`, body).then(data<HardwareRegistry>),
  previewImport: (rows: HardwareImportRow[]) => api.post('/hardware/imports', { rows }).then(data<HardwareImportPreview>),
  commitImport: (id: string, row_indexes: number[], idempotency_key: string) => api.post(`/hardware/imports/${encodeURIComponent(id)}/commit`, { row_indexes, idempotency_key }).then(data<HardwareImportPreview>),
  getFirmwareBoardTypes: (id: string | number) => api.get(`/ota/firmware/${id}/board-types`).then(data<{ board_codes: string[] }>).then(d => d.board_codes),
  setFirmwareBoardTypes: (id: string | number, board_codes: string[], evidence_ref: string, reason: string) => api.put(`/ota/firmware/${id}/board-types`, { board_codes, evidence_ref, reason }).then(data<{ board_codes: string[] }>).then(d => d.board_codes),
  listCompatibilityWindows: (sn?: string) => api.get('/ota/compatibility-windows', { params: { sn }, expectedDataShape: 'array' }).then(data<CompatibilityWindow[]>),
  createCompatibilityWindow: (body: CompatibilityWindow) => api.post('/ota/compatibility-windows', body).then(data<CompatibilityWindow>),
}
export function hardwareError(error: unknown): string {
  const e = error as { response?: { data?: { message?: string } }; message?: string }
  return e.response?.data?.message || e.message || 'Request failed'
}
