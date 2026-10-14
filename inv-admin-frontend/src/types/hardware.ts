export type TargetChip = 'esp' | 'arm' | 'dsp' | 'bms'
export interface BoardType { model: string; target_chip: TargetChip | string; board_code: string; description: string }
export interface HardwareModule { target_chip: TargetChip | string; board_code: string; board_uid?: string; state?: string; module_revision?: number; protection_level?: string }
export interface HardwareRegistry {
  sn: string; verified_model: string; identity_state: string; identity_revision: number; frozen?: boolean
  source: string; evidence_ref: string; verified_by?: number; verified_at?: string
  modules: HardwareModule[]; observations?: Record<string, unknown>[]
}
export interface HardwareHistory { id: number; action: string; identity_revision: number; actor: number; reason: string; evidence_ref: string; created_at: string }
export interface RegistryMutation { expected_revision: number; verified_model?: string; source?: string; evidence_ref: string; reason: string; modules?: HardwareModule[]; frozen?: boolean }
export interface HardwareImportRow { sn: string; verified_model: string; source?: string; evidence_ref: string; reason?: string; modules: HardwareModule[] }
export interface ImportPreviewRow { row_index: number; data: HardwareImportRow; valid: boolean; errors: string[]; status: string }
export interface HardwareImportPreview { id: string; rows: ImportPreviewRow[] }
export interface CompatibilityWindow { id?: number; sn: string; target_chip: string; firmware_id: number; file_sha256: string; identity_revision: number; expires_at: string; reason: string; evidence_ref: string }
