import { afterEach, describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderAsAdmin } from '@/test/test-utils'
import { hardwareApi } from '@/services/hardwareApi'
import HardwareImportModal, { parseHardwareCsv } from './HardwareImportModal'

describe('HardwareImportModal', () => {
  afterEach(() => vi.restoreAllMocks())
  it('preserves quoted evidence and groups multiple modules into one SN row', () => {
    expect(parseHardwareCsv('sn,verified_model,target_chip,board_code,board_uid,evidence_ref\nSN-A,L10,DSP,DSP-A,UID-A,"Factory,2026"\nSN-A,L10,ESP,ESP-A,UID-B,"Factory,2026"')).toEqual([{ sn: 'SN-A', verified_model: 'L10', evidence_ref: 'Factory,2026', source: 'factory', reason: 'factory ledger import', modules: [{ target_chip: 'dsp', board_code: 'DSP-A', board_uid: 'UID-A', state: 'verified', protection_level: 'registry_verified' }, { target_chip: 'esp', board_code: 'ESP-A', board_uid: 'UID-B', state: 'verified', protection_level: 'registry_verified' }] }])
  })
  it('rejects inconsistent evidence for the same SN', () => {
    expect(() => parseHardwareCsv('sn,verified_model,target_chip,board_code,board_uid,evidence_ref\nSN-A,L10,DSP,A,U1,E1\nSN-A,L10,ESP,B,U2,E2')).toThrow()
  })
  it('submits only server validated rows with a stable idempotency key', async () => {
    const preview = vi.spyOn(hardwareApi, 'previewImport').mockResolvedValue({ id: 'staging-1', rows: [{ row_index: 1, data: { sn: 'SN-A' }, valid: true, errors: [], status: 'new' }, { row_index: 2, data: { sn: 'SN-B' }, valid: false, errors: ['existing verified registry'], status: 'conflict' }] } as any)
    const commit = vi.spyOn(hardwareApi, 'commitImport').mockResolvedValue({ id: 'staging-1', rows: [{ row_index: 1, data: { sn: 'SN-A' }, valid: true, status: 'committed', errors: [] }] } as any)
    renderAsAdmin(<HardwareImportModal open onClose={() => {}} />)
    await userEvent.type(screen.getByLabelText('CSV 台账内容'), 'sn,verified_model,target_chip,board_code,board_uid,evidence_ref\nSN-A,L10,DSP,DSP-A,UID-A,E1')
    await userEvent.click(screen.getByRole('button', { name: '服务端预览' }))
    await screen.findByText('SN-B')
    expect(preview).toHaveBeenCalled()
    await waitFor(() => expect(screen.getByRole('button', { name: '提交选中有效行' })).toBeEnabled(), { timeout: 5000 })
    await userEvent.click(screen.getByRole('button', { name: '提交选中有效行' }))
    await waitFor(() => expect(commit).toHaveBeenCalledWith('staging-1', [1], expect.any(String)))
    expect(await screen.findByText('已提交')).toBeInTheDocument()
  })
})
