import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import type { Firmware } from '@/types'
import FirmwarePublishModal from './FirmwarePublishModal'

const source = {
  id: '1', model: 'L10', target_chip: 'esp', version: '2.0', created_at: '2026-10-01T00:00:00Z',
  hardware_versions: [], board_codes: ['HW-1', 'HW-2'], release_status: 'draft',
} as unknown as Firmware

describe('firmware publication hardware compatibility', () => {
  it('shows the range and only offers rollback covering all hardware in the same model/module', async () => {
    const peers = [
      { ...source, id: '2', version: 'full-range', release_status: 'published' },
      { ...source, id: '3', version: 'partial-range', board_codes: ['HW-1'], release_status: 'published' },
      { ...source, id: '4', version: 'wrong-model', model: 'L20', release_status: 'published' },
      { ...source, id: '5', version: 'disabled-file', release_status: 'disabled' },
    ]
    renderAsAdmin(<FirmwarePublishModal open firmware={source} publishedPeers={peers} onOk={vi.fn()} onCancel={vi.fn()} />)
    expect(await screen.findByText('HW-1, HW-2')).toBeInTheDocument()
    fireEvent.mouseDown(screen.getAllByRole('combobox')[1])
    expect(await screen.findByText(/full-range/, { selector: '.ant-select-item-option-content' })).toBeInTheDocument()
    expect(screen.queryByText(/partial-range/)).not.toBeInTheDocument()
    expect(screen.queryByText(/wrong-model/)).not.toBeInTheDocument()
    expect(screen.queryByText(/disabled-file/)).not.toBeInTheDocument()
  })
  it('blocks a legacy firmware publication without a range', async () => {
    const onOk = vi.fn()
    renderAsAdmin(<FirmwarePublishModal open firmware={{ ...source, hardware_versions: ['HW-1'], board_codes: [] }} onOk={onOk} onCancel={vi.fn()} />)
    fireEvent.click(await screen.findByRole('button', { name: /发.*布/ }))
    expect(onOk).not.toHaveBeenCalled()
    expect(screen.getAllByText('未配置板卡范围').length).toBeGreaterThan(0)
  })
})
