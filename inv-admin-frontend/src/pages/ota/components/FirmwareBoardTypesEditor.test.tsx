import { afterEach, describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderAsAdmin } from '@/test/test-utils'
import { hardwareApi } from '@/services/hardwareApi'
import FirmwareBoardTypesEditor from './FirmwareBoardTypesEditor'

describe('FirmwareBoardTypesEditor', () => {
  afterEach(() => vi.restoreAllMocks())
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
