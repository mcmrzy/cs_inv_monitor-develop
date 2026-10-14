import { afterEach, describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders, renderAsAdmin } from '@/test/test-utils'
import { hardwareApi } from '@/services/hardwareApi'
import HardwareRegistryDrawer from './HardwareRegistryDrawer'

const registry = { sn: 'SN-A', verified_model: 'L10', identity_state: 'conflict', identity_revision: 7, source: 'factory', evidence_ref: 'factory-1', modules: [{ target_chip: 'dsp', board_code: 'DSP-A', board_uid: 'UID-A', state: 'verified', module_revision: 1, protection_level: 'legacy' }], observations: [], history: [] }
describe('HardwareRegistryDrawer', () => {
  afterEach(() => vi.restoreAllMocks())
  it('shows conflict and trusted module identity without write actions to readers', async () => {
    vi.spyOn(hardwareApi, 'getRegistry').mockResolvedValue(registry as any)
    vi.spyOn(hardwareApi, 'getHistory').mockResolvedValue({ items: [], total: 0 })
    renderWithProviders(<HardwareRegistryDrawer sn="SN-A" onClose={() => {}} />, { initialUser: null })
    expect(await screen.findByText('DSP-A')).toBeInTheDocument()
    expect(screen.getAllByText('身份冲突').length).toBeGreaterThan(0)
    expect(screen.queryByRole('button', { name: '核实档案' })).not.toBeInTheDocument()
  })
  it('freezes using the displayed revision and requires evidence and reason', async () => {
    vi.spyOn(hardwareApi, 'getRegistry').mockResolvedValue(registry as any)
    vi.spyOn(hardwareApi, 'getHistory').mockResolvedValue({ items: [], total: 0 })
    vi.spyOn(hardwareApi, 'listBoardTypes').mockResolvedValue([])
    const mutate = vi.spyOn(hardwareApi, 'mutateRegistry').mockResolvedValue(registry as any)
    renderAsAdmin(<HardwareRegistryDrawer sn="SN-A" onClose={() => {}} />)
    await screen.findByText('DSP-A')
    await userEvent.click(screen.getByRole('button', { name: '冻结升级' }))
    await userEvent.type(screen.getByLabelText('证据编号'), 'SERVICE-101')
    await userEvent.type(screen.getByLabelText('原因'), '需要核查实际板卡')
    await userEvent.click(screen.getByRole('button', { name: '确认提交' }))
    await waitFor(() => expect(mutate).toHaveBeenCalledWith('SN-A', 'freeze', expect.objectContaining({ expected_revision: 7, evidence_ref: 'SERVICE-101', reason: '需要核查实际板卡' })))
  })
  it('allows audited unfreezing only after identity is verified', async () => {
    vi.spyOn(hardwareApi, 'getRegistry').mockResolvedValue({ ...registry, identity_state: 'verified', frozen: true } as any)
    vi.spyOn(hardwareApi, 'getHistory').mockResolvedValue({ items: [], total: 0 })
    vi.spyOn(hardwareApi, 'listBoardTypes').mockResolvedValue([])
    const mutate = vi.spyOn(hardwareApi, 'mutateRegistry').mockResolvedValue(registry as any)
    renderAsAdmin(<HardwareRegistryDrawer sn="SN-A" onClose={() => {}} />)
    await screen.findByText('DSP-A')
    await userEvent.click(screen.getByRole('button', { name: '解除冻结' }))
    await userEvent.type(screen.getByLabelText('证据编号'), 'SERVICE-DONE')
    await userEvent.type(screen.getByLabelText('原因'), '实际板卡已核实')
    await userEvent.click(screen.getByRole('button', { name: '确认提交' }))
    await waitFor(() => expect(mutate).toHaveBeenCalledWith('SN-A', 'freeze', expect.objectContaining({ frozen: false, expected_revision: 7 })))
  })
})
