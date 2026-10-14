import { afterEach, describe, expect, it, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderAsAdmin } from '@/test/test-utils'
import { hardwareApi } from '@/services/hardwareApi'
import CompatibilityWindowsModal from './CompatibilityWindowsModal'
describe('CompatibilityWindowsModal', () => {
  afterEach(() => vi.restoreAllMocks())
  it('requires explicit digest, trusted revision and evidence before legacy migration', async () => {
    vi.spyOn(hardwareApi, 'listCompatibilityWindows').mockResolvedValue([])
    const create = vi.spyOn(hardwareApi, 'createCompatibilityWindow').mockResolvedValue({} as any)
    renderAsAdmin(<CompatibilityWindowsModal open onClose={() => {}} />)
    expect(await screen.findByText(/不提供离线升级或设备写入前防护/)).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '创建迁移窗口' }))
    await waitFor(() => expect(screen.getAllByText('必填').length).toBeGreaterThan(0))
    expect(create).not.toHaveBeenCalled()
  })
})
