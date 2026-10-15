import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import type { Firmware } from '@/types'
import FirmwarePublishModal from './FirmwarePublishModal'

const source = {
  id: '1', model: 'L10', target_chip: 'esp', version: '2.0', created_at: '2026-10-01T00:00:00Z',
  hardware_versions: [], board_codes: ['HW-1', 'HW-2'], release_status: 'draft',
} as unknown as Firmware

describe('firmware publication', () => {
  it('offers every published rollback in the same model/module regardless of board range', async () => {
    const peers = [
      { ...source, id: '2', version: 'full-range', release_status: 'published' },
      { ...source, id: '3', version: 'partial-range', board_codes: ['HW-1'], release_status: 'published' },
      { ...source, id: '4', version: 'wrong-model', model: 'L20', release_status: 'published' },
      { ...source, id: '5', version: 'disabled-file', release_status: 'disabled' },
      { ...source, id: '6', version: 'no-range', board_codes: [], hardware_versions: [], release_status: 'published' },
      { ...source, id: '7', version: 'wrong-module', target_chip: 'dsp', release_status: 'published' },
    ]
    renderAsAdmin(<FirmwarePublishModal open firmware={source} publishedPeers={peers} onOk={vi.fn()} onCancel={vi.fn()} />)
    fireEvent.mouseDown(screen.getAllByRole('combobox')[1])
    expect(await screen.findByText(/full-range/, { selector: '.ant-select-item-option-content' })).toBeInTheDocument()
    expect(screen.getByText(/partial-range/, { selector: '.ant-select-item-option-content' })).toBeInTheDocument()
    expect(screen.getByText(/no-range/, { selector: '.ant-select-item-option-content' })).toBeInTheDocument()
    expect(screen.queryByText(/wrong-model/)).not.toBeInTheDocument()
    expect(screen.queryByText(/disabled-file/)).not.toBeInTheDocument()
    expect(screen.queryByText(/wrong-module/)).not.toBeInTheDocument()
  })
  it('publishes firmware without any hardware or board range', async () => {
    const onOk = vi.fn()
    renderAsAdmin(<FirmwarePublishModal open firmware={{ ...source, hardware_versions: [], board_codes: [] }} onOk={onOk} onCancel={vi.fn()} />)
    fireEvent.click(await screen.findByRole('button', { name: /发.*布/ }))
    expect(onOk).toHaveBeenCalledWith({ rollout_percent: 100, rollout_type: 'all', rollout_targets: '', rollback_to_firmware_id: null })
    expect(screen.queryByText('未配置板卡范围')).not.toBeInTheDocument()
  })
})
