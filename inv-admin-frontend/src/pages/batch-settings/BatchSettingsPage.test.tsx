import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { renderAsAdmin } from '@/test/test-utils'
import BatchSettingsPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)
// antd Button 对两字中文文案会自动插入空格（如「全 选」），断言使用正则容忍空格

describe('BatchSettingsPage', () => {
  it('renders title, summary cards and device list from devices API', async () => {
    renderAsAdmin(<BatchSettingsPage />)

    expect(screen.getByText('批量设置')).toBeInTheDocument()
    // 三步流程入口按钮
    expect(screen.getByRole('button', { name: '下一步: 配置参数' })).toBeInTheDocument()
    // MSW /devices 返回 3 台设备，设备列表卡片出现 SN
    expect(await screen.findByText('INV20250001')).toBeInTheDocument()
    expect(screen.getByText('INV20250002')).toBeInTheDocument()
    expect(screen.getByText('INV20250003')).toBeInTheDocument()
    // 电站筛选卡片
    expect(screen.getByText('电站筛选')).toBeInTheDocument()
  })

  it('shows selection summary tags and disabled next step initially', async () => {
    renderAsAdmin(<BatchSettingsPage />)

    // 摘要标签：已选设备 0 台 / 参数变更 0 项；下一步按钮初始禁用
    await screen.findByText('INV20250001')
    expect(screen.getByText('已选设备: 0 台')).toBeInTheDocument()
    expect(screen.getByText('参数变更: 0 项')).toBeInTheDocument()
    expect(screen.getByText(/已选 0 \/ 3/)).toBeInTheDocument()
    const nextBtn = screen.getByRole('button', { name: '下一步: 配置参数' })
    expect(nextBtn).toBeDisabled()
  })

  it('selects all devices and enables the next step button', async () => {
    renderAsAdmin(<BatchSettingsPage />)

    await screen.findByText('INV20250001')
    fireEvent.click(screen.getByRole('button', { name: /全\s*选/ }))

    // 全选后摘要与计数更新，下一步可用
    await waitFor(() => {
      expect(screen.getByText('已选设备: 3 台')).toBeInTheDocument()
    })
    expect(screen.getByText(/已选 3 \/ 3/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '下一步: 配置参数' })).toBeEnabled()
  })

  it('advances to parameter config step with category cards', async () => {
    renderAsAdmin(<BatchSettingsPage />)

    await screen.findByText('INV20250001')
    fireEvent.click(screen.getByRole('button', { name: /全\s*选/ }))
    fireEvent.click(await waitFor(() => {
      const btn = screen.getByRole('button', { name: '下一步: 配置参数' })
      expect(btn).toBeEnabled()
      return btn
    }))

    // 步骤 1：参数配置卡片（充电/放电/电网/应用 4 类参数，16 个开关）
    await waitFor(() => {
      expect(screen.getByText('参数配置')).toBeInTheDocument()
    })
    expect(screen.getByText('选择需要修改的参数并设置值')).toBeInTheDocument()
    const switches = document.querySelectorAll('button[role="switch"]')
    expect(switches.length).toBeGreaterThanOrEqual(16)
  })

  it('renders batch history section with empty placeholder', async () => {
    renderAsAdmin(<BatchSettingsPage />)

    // 历史记录卡片初始为空
    expect(await screen.findByText('最近批量操作')).toBeInTheDocument()
    expect(screen.getByText('暂无批量操作记录')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /刷\s*新/ })).toBeInTheDocument()
  })
})
