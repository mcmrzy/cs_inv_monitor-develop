import { describe, it, expect } from 'vitest'
import { fireEvent, screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderAsAdmin } from '@/test/test-utils'
import WorkOrdersPage from './index'

// 注意：不要 mock @/utils/timezone —— 页面依赖其模块级 dayjs.extend(utc)

/** 从统计卡片中找到标题对应的Statistic元素并断言其数值文本 */
function expectStatistic(title: string, value: string) {
  const stat = Array.from(document.querySelectorAll('.ant-statistic')).find((el) =>
    el.textContent?.includes(title),
  )
  expect(stat, `statistic ${title} should render`).toBeTruthy()
  expect(stat?.textContent).toContain(value)
}

describe('WorkOrdersPage', () => {
  it('renders title and SLA statistics from work-order-stats API', async () => {
    renderAsAdmin(<WorkOrdersPage />)

    expect(screen.getByText('工单管理')).toBeInTheDocument()
    // /work-order-stats: open=3, inProgress=4, resolved=2, closed=1
    await waitFor(() => {
      expectStatistic('待处理', '3')
      expectStatistic('处理中', '4')
      expectStatistic('已解决', '2')
      expectStatistic('已关闭', '1')
    })
  })

  it('renders work order table with mocked rows and tags', async () => {
    renderAsAdmin(<WorkOrdersPage />)

    // mockWorkOrders: 设备离线故障排查 / high / open
    expect(await screen.findByText('设备离线故障排查')).toBeInTheDocument()
    expect(document.querySelector('.ant-table')).toBeInTheDocument()
    // 优先级与状态标签
    expect(screen.getByText('高')).toBeInTheDocument()
    expect(screen.getAllByText('待处理').length).toBeGreaterThanOrEqual(1)
    // 操作列：详情按钮 + 视图切换按钮
    expect(screen.getAllByText('详情').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('表格')).toBeInTheDocument()
    expect(screen.getByText('看板')).toBeInTheDocument()
  })

  it('switches to kanban view and renders status columns', async () => {
    renderAsAdmin(<WorkOrdersPage />)

    await screen.findByText('设备离线故障排查')
    fireEvent.click(screen.getByText('看板'))

    // 看板模式下表格消失，按 4 种状态分列且 open 列包含该工单卡片
    await waitFor(() => {
      expect(document.querySelector('.ant-table')).not.toBeInTheDocument()
    })
    expect(screen.getAllByText('待处理').length).toBeGreaterThanOrEqual(1)
    expect(screen.getAllByText('已解决').length).toBeGreaterThanOrEqual(1)
    expect(screen.getAllByText('已关闭').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('设备离线故障排查')).toBeInTheDocument()
  })

  it('opens template modal with template cards and then create form', async () => {
    server.use(
      http.get('/api/v1/work-order-templates', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: [
            { templateId: 'repair', title: '维修工单', description: '现场维修', priority: 2, estimatedHours: 4 },
          ],
        }),
      ),
    )

    renderAsAdmin(<WorkOrdersPage />)

    fireEvent.click(await screen.findByText('创建工单'))
    // 模板选择弹窗（等模板数据异步加载完成）
    expect(await screen.findByText('维修工单')).toBeInTheDocument()
    expect(screen.getByText('选择工单模板')).toBeInTheDocument()
    // 选择模板 → 打开创建表单（标题为 创建工单（模板预填））
    fireEvent.click(screen.getByText('维修工单'))
    expect(await screen.findByText('预计 4h')).toBeInTheDocument()
    expect(screen.getByText('创建工单（模板预填）')).toBeInTheDocument()
  })

  it('shows empty state when work order list is empty', async () => {
    server.use(
      http.get('/api/v1/work-orders', () =>
        HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } }),
      ),
    )

    renderAsAdmin(<WorkOrdersPage />)

    await waitFor(() => {
      expect(document.querySelector('.ant-empty')).toBeInTheDocument()
    })
    expect(screen.getByText('暂无工单')).toBeInTheDocument()
  })
})
