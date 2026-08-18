// 回归测试：['stations', 'all'] 缓存形状污染
//
// 线上崩溃场景（"d.find is not a function"，生产压缩后变量名）：
// 批量设置页（batch-settings）与 DeviceSelector 共用 queryKey ['stations', 'all']，
// 但前者 queryFn 返回整个响应体 {code, message, data:{items:[...]}}（非数组）。
// 用户先访问批量设置页 → 缓存写入非数组形状 → 切到远程设置页时
// DeviceSelector 的 stations.find(s => s.id === selectedStationId) 抛 TypeError，
// 页面级 ErrorBoundary 显示 "Something went wrong"，刷新（缓存清空）后恢复。
//
// 修复要求：DeviceSelector 消费侧对缓存形状做防御，非数组一律降级为空列表。
import { describe, it, expect, beforeEach } from 'vitest'
import DeviceSelector from './DeviceSelector'
import { renderWithProviders, createTestQueryClient } from '@/test/test-utils'

describe('DeviceSelector 缓存形状防御', () => {
  beforeEach(() => {
    // 让 selectedStationId 非 null，触发电站 Select value 分支的 stations.find()
    localStorage.setItem('remote-settings-station-id', '1')
    localStorage.removeItem('remote-settings-device-sn')
  })

  it('stations 缓存为批量设置页写入的非数组形状（响应体）时不崩溃', () => {
    const queryClient = createTestQueryClient()
    // 形状与 batch-settings 的 queryFn（r.data）完全一致
    queryClient.setQueryData(['stations', 'all'], {
      code: 0,
      message: 'success',
      data: { items: [{ id: 1, name: '测试电站' }], total: 1 },
    } as any)

    expect(() =>
      renderWithProviders(
        <DeviceSelector selectedSn={null} onDeviceChange={() => undefined} onRead={() => undefined} reading={false} />,
        { queryClient },
      ),
    ).not.toThrow()
  })

  it('stations 缓存为对象（无 items）时同样不崩溃', () => {
    const queryClient = createTestQueryClient()
    queryClient.setQueryData(['stations', 'all'], { weird: true } as any)

    expect(() =>
      renderWithProviders(
        <DeviceSelector selectedSn={null} onDeviceChange={() => undefined} onRead={() => undefined} reading={false} />,
        { queryClient },
      ),
    ).not.toThrow()
  })

  it('stations 缓存为正常数组时正常渲染选择器', () => {
    const queryClient = createTestQueryClient()
    queryClient.setQueryData(['stations', 'all'], [{ id: 1, name: '测试电站' }] as any)

    const { container } = renderWithProviders(
      <DeviceSelector selectedSn={null} onDeviceChange={() => undefined} onRead={() => undefined} reading={false} />,
      { queryClient },
    )
    // 两个选择器（电站 + 设备）均正常渲染
    expect(container.querySelectorAll('.ant-select').length).toBeGreaterThanOrEqual(2)
  })
})
