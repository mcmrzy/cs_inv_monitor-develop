import { describe, it, expect, vi } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '@/test/test-utils'
import BulkDeviceOperationModal from './BulkDeviceOperationModal'

describe('BulkDeviceOperationModal', () => {
  it('executes devices serially with success/failure counts and supports retrying failed items', async () => {
    const user = userEvent.setup()
    const executed: string[] = []
    // SN-2 仅首次尝试失败（如设备仍被电站占用），重试后成功
    const failedOnce = new Set<string>()
    const execute = vi.fn(async (sn: string) => {
      executed.push(sn)
      if (sn === 'SN-2' && !failedOnce.has(sn)) {
        failedOnce.add(sn)
        throw new Error('device busy')
      }
    })
    const onSettled = vi.fn()
    const onCancel = vi.fn()

    renderWithProviders(
      <BulkDeviceOperationModal
        open
        title="批量解绑"
        sns={['SN-1', 'SN-2', 'SN-3']}
        execute={execute}
        onCancel={onCancel}
        onSettled={onSettled}
      />,
    )

    // 全部执行完毕：串行顺序 SN-1 → SN-2 → SN-3
    await waitFor(() => {
      expect(onSettled).toHaveBeenCalledTimes(1)
    })
    expect(executed).toEqual(['SN-1', 'SN-2', 'SN-3'])

    // 结束后展示成功 x / 失败 y 计数与失败 SN 列表
    expect(screen.getByText('2')).toBeInTheDocument()
    expect(screen.getByText('1')).toBeInTheDocument()
    expect(screen.getByText('SN-2')).toBeInTheDocument()

    // 失败项出现「重试失败项」按钮，且只重试失败的那台
    await user.click(screen.getByRole('button', { name: /重试失败项/ }))
    await waitFor(() => {
      expect(onSettled).toHaveBeenCalledTimes(2)
    })
    // 第二轮只执行失败项，且本轮全部成功
    expect(execute).toHaveBeenLastCalledWith('SN-2')
    expect(executed.filter((sn) => sn === 'SN-2')).toHaveLength(2)
    expect(onSettled).toHaveBeenLastCalledWith({ success: ['SN-2'], failures: [] })
    // 全部成功后失败计数归零
    expect(screen.getByText('0')).toBeInTheDocument()
  })
})
