import { afterEach, describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderAsAdmin } from '@/test/test-utils'
import { hardwareApi } from '@/services/hardwareApi'
import FirmwareBoardTypesEditor from './FirmwareBoardTypesEditor'

describe('FirmwareBoardTypesEditor', () => {
  afterEach(() => vi.restoreAllMocks())
  it('shows load failures with retry instead of claiming the catalog is empty', async () => {
    const catalog = vi.spyOn(hardwareApi, 'listBoardTypes').mockRejectedValueOnce(new Error('接口不存在')).mockResolvedValue([{ model: 'L10', target_chip: 'dsp', board_code: 'DSP-A', description: '' }])
    vi.spyOn(hardwareApi, 'getFirmwareBoardTypes').mockResolvedValue([])
    renderAsAdmin(<FirmwareBoardTypesEditor firmware={{ id: '12', model: 'L10', target_chip: 'dsp' } as any} onClose={() => {}} />)
    await screen.findByText('接口不存在')
    expect(screen.queryByText('请先登记该型号和目标的板卡类型')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '重新加载' }))
    await screen.findByText('DSP-A')
    expect(catalog).toHaveBeenCalledTimes(2)
  })
  it('lets an administrator register a missing board here with the model and target prefilled', async () => {
    vi.spyOn(hardwareApi, 'listBoardTypes').mockResolvedValue([])
    vi.spyOn(hardwareApi, 'getFirmwareBoardTypes').mockResolvedValue([])
    const create = vi.spyOn(hardwareApi, 'createBoardType').mockResolvedValue({ model: 'L10', target_chip: 'dsp', board_code: 'DSP-A', description: '' })
    renderAsAdmin(<FirmwareBoardTypesEditor firmware={{ id: '12', model: 'L10', target_chip: 'dsp' } as any} onClose={() => {}} />)
    await screen.findByText('请先登记该型号和目标的板卡类型')
    await userEvent.click(screen.getByRole('button', { name: '新增板卡类型' }))
    expect(screen.getByLabelText('核实型号')).toHaveValue('L10')
    await userEvent.type(screen.getByLabelText('板卡类型'), 'DSP-A')
    await userEvent.click(screen.getByRole('button', { name: '确认提交' }))
    await waitFor(() => expect(create).toHaveBeenCalledWith(expect.objectContaining({ model: 'L10', target_chip: 'dsp', board_code: 'DSP-A' })))
  })
  it('loads the exact model and target catalog and saves explicitly selected codes', async () => {
    const catalog = vi.spyOn(hardwareApi, 'listBoardTypes').mockResolvedValue([{ model: 'L10', target_chip: 'dsp', board_code: 'DSP-A', description: 'A board' }])
    vi.spyOn(hardwareApi, 'getFirmwareBoardTypes').mockResolvedValue(['DSP-A'])
    const save = vi.spyOn(hardwareApi, 'setFirmwareBoardTypes').mockResolvedValue(['DSP-A'])
    renderAsAdmin(<FirmwareBoardTypesEditor firmware={{ id: '12', model: 'L10', target_chip: 'dsp', hardware_versions: ['V1'] } as any} onClose={() => {}} />)
    await screen.findByText('DSP-A — A board')
    expect(catalog).toHaveBeenCalledWith('L10', 'dsp')
    expect(screen.getByText(/旧硬件范围仅供历史展示/)).toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('证据编号'), 'COMPAT-1')
    await userEvent.type(screen.getByLabelText('原因'), '已验证板卡适配')
    await userEvent.click(screen.getByRole('button', { name: '保存板卡范围' }))
    await waitFor(() => expect(save).toHaveBeenCalledWith('12', ['DSP-A'], 'COMPAT-1', '已验证板卡适配'))
  })
})
