/**
 * MSW v2 API Mock Handlers
 *
 * 使用 MSW v2 的 `http` 语法定义 API 拦截器。
 * 所有 handlers 均返回符合 `ApiResponse<T>` 格式的响应。
 *
 * 在测试中可通过 `server.use(...)` 覆盖特定 handler。
 */

import { http, HttpResponse } from 'msw'
import {
  mockLoginResponse,
  mockDevices,
  mockUsers,
  mockFirmwares,
  mockAlerts,
  mockWorkOrders,
  mockUpgradeTasks,
  mockAlertStats,
  mockDashboardStats,
  paginatedResponse,
} from './data'

const API_BASE = '/api/v1'

export const handlers = [
  /** 登录 */
  http.post(`${API_BASE}/auth/login`, async ({ request }) => {
    const body = (await request.json()) as { account: string; password: string }
    if (body.account === 'admin@example.com' && body.password === 'Admin123') {
      return HttpResponse.json(mockLoginResponse)
    }
    return HttpResponse.json(
      { code: 1001, message: '账号或密码错误' },
      { status: 401 },
    )
  }),

  /** 刷新 Token */
  http.post(`${API_BASE}/auth/refresh`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        token: 'mock-refreshed-jwt-token',
        refresh_token: 'mock-refreshed-refresh-token',
      },
    })
  }),

  /** 退出登录 */
  http.post(`${API_BASE}/auth/logout`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 设备列表 */
  http.get(`${API_BASE}/devices`, ({ request }) => {
    const url = new URL(request.url)
    const page = Number(url.searchParams.get('page') || '1')
    const pageSize = Number(url.searchParams.get('page_size') || url.searchParams.get('pageSize') || '20')
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: paginatedResponse(mockDevices, mockDevices.length),
    })
  }),

  /** 设备详情 */
  http.get(`${API_BASE}/devices/by-sn/:sn`, ({ params }) => {
    const device = mockDevices.find((d) => d.sn === params.sn)
    if (device) {
      return HttpResponse.json({ code: 0, message: 'success', data: device })
    }
    return HttpResponse.json({ code: 404, message: '设备不存在' }, { status: 404 })
  }),

  /** 创建设备 */
  http.post(`${API_BASE}/devices`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 更新设备 */
  http.put(`${API_BASE}/devices/by-sn/:sn`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 删除设备 */
  http.delete(`${API_BASE}/devices/by-sn/:sn`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 设备实时数据 */
  http.get(`${API_BASE}/devices/by-sn/:sn/realtime`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        ac: { voltage: 220, current: 10, power: 2200, frequency: 50 },
        pv: { voltage: 350, current: 8, power: 2800 },
        battery: { soc: 80, voltage: 48, current: 5, temp: 25 },
        system: { state: 'running', fault_code: 0, temp_inv: 42 },
        online: { online: true, rssi: -60, ip: '192.168.1.100' },
      },
    })
  }),

  /** 设备遥测历史 */
  http.get(`${API_BASE}/devices/by-sn/:sn/telemetry`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: { items: [], total: 0 },
    })
  }),

  /** 用户列表 */
  http.get(`${API_BASE}/users`, ({ request }) => {
    const url = new URL(request.url)
    const role = url.searchParams.get('role')
    const filtered = role
      ? mockUsers.filter((u) => String(u.role) === role)
      : mockUsers
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: paginatedResponse(filtered, filtered.length),
    })
  }),

  /** 用户详情 */
  http.get(`${API_BASE}/users/:id`, ({ params }) => {
    const user = mockUsers.find((u) => u.id === params.id)
    if (user) {
      return HttpResponse.json({ code: 0, message: 'success', data: user })
    }
    return HttpResponse.json({ code: 404, message: '用户不存在' }, { status: 404 })
  }),

  /** 创建用户 */
  http.post(`${API_BASE}/users`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 更新用户 */
  http.patch(`${API_BASE}/users/:id`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 删除用户 */
  http.delete(`${API_BASE}/users/:id`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 重置密码 */
  http.put(`${API_BASE}/users/:id/password`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 切换用户状态 */
  http.put(`${API_BASE}/users/:id/toggle`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 告警列表 */
  http.get(`${API_BASE}/alarms`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: paginatedResponse(mockAlerts, mockAlerts.length),
    })
  }),

  /** 告警统计 */
  http.get(`${API_BASE}/alarms/stats`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: mockAlertStats,
    })
  }),

  /** 确认告警 */
  http.post(`${API_BASE}/alarms/:id/acknowledge`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 忽略告警 */
  http.post(`${API_BASE}/alarms/:id/ignore`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 删除告警 */
  http.delete(`${API_BASE}/alarms/:id`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 清空告警 */
  http.delete(`${API_BASE}/alarms/clear-all`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 通知列表 */
  http.get(`${API_BASE}/notifications`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: { items: [], total: 0 },
    })
  }),

  /** 通知统计 */
  http.get(`${API_BASE}/notifications/stats`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: { total: 3, unread: 1 },
    })
  }),

  /** 固件列表 */
  http.get(`${API_BASE}/firmwares`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: mockFirmwares,
    })
  }),

  /** 上传固件 */
  http.post(`${API_BASE}/firmwares`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 删除固件 */
  http.delete(`${API_BASE}/firmwares/:id`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** OTA 任务列表 */
  http.get(`${API_BASE}/ota/tasks`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: paginatedResponse(mockUpgradeTasks, mockUpgradeTasks.length),
    })
  }),

  /** OTA 任务统计 */
  http.get(`${API_BASE}/ota/task-stats`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: { total: 5, running: 1, completed: 3, failed: 1 },
    })
  }),

  /** 创建 OTA 任务 */
  http.post(`${API_BASE}/ota/tasks`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 取消 OTA 任务 */
  http.post(`${API_BASE}/ota/tasks/:id/cancel`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** OTA 升级面板 */
  http.get(`${API_BASE}/ota/upgrades/dashboard`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } })
  }),

  /** OTA 升级包列表 */
  http.get(`${API_BASE}/ota/packages`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 创建 OTA 升级包 */
  http.post(`${API_BASE}/ota/packages`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 仪表盘统计 */
  http.get(`${API_BASE}/dashboard/statistics`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: mockDashboardStats })
  }),

  /** 仪表盘趋势 */
  http.get(`${API_BASE}/dashboard/trend`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 设备分布 */
  http.get(`${API_BASE}/dashboard/device-distribution`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: { online: 95, offline: 20, fault: 5 },
    })
  }),

  /** 电站列表 */
  http.get(`${API_BASE}/stations`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: {
        items: [
          { id: 1, name: '测试电站A', device_count: 10 },
          { id: 2, name: '测试电站B', device_count: 5 },
        ],
        total: 2,
      },
    })
  }),

  /** 型号列表 */
  http.get(`${API_BASE}/admin/models`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: [
        { id: 1, model_code: 'SG-5K-D', model_name: 'SG-5K-D', manufacturer: 'CSERGY', category: 'inverter' },
        { id: 2, model_code: 'SG-10K-D', model_name: 'SG-10K-D', manufacturer: 'CSERGY', category: 'inverter' },
      ],
    })
  }),

  http.get(`${API_BASE}/models`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: [
        { id: 1, model_code: 'SG-5K-D', model_name: 'SG-5K-D', manufacturer: 'CSERGY', category: 'inverter' },
        { id: 2, model_code: 'SG-10K-D', model_name: 'SG-10K-D', manufacturer: 'CSERGY', category: 'inverter' },
      ],
    })
  }),

  /** 工单列表 */
  http.get(`${API_BASE}/work-orders`, () => {
    return HttpResponse.json({
      code: 0,
      message: 'success',
      data: paginatedResponse(mockWorkOrders, mockWorkOrders.length),
    })
  }),

  /** 仪表盘能量流 */
  http.get(`${API_BASE}/dashboard/energy-flow`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 仪表盘电量统计 */
  http.get(`${API_BASE}/dashboard/energy-stats`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { dates: [], pv: [], batteryCharge: [], batteryDischarge: [] } })
  }),

  /** 仪表盘电站排行 */
  http.get(`${API_BASE}/dashboard/station-ranking`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 仪表盘大屏 */
  http.get(`${API_BASE}/dashboard/big-screen`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: {} })
  }),

  /** 管理-系统健康 */
  http.get(`${API_BASE}/admin/system-health`, () => {
    return HttpResponse.json({
      code: 0, message: 'success',
      data: { uptime: 86400, memoryUsage: 45.2, cpuUsage: 12.5, database: true, redis: true, mqtt: true, version: '1.0.0', lastCheckAt: '2026-01-01T12:00:00Z' },
    })
  }),

  /** 管理-审计日志 */
  http.get(`${API_BASE}/admin/logs`, () => {
    return HttpResponse.json({
      code: 0, message: 'success',
      data: paginatedResponse([
        { id: 1, userId: 1, username: 'admin', action: 'login', resource: 'auth', resourceId: '', details: '管理员登录', ipAddress: '127.0.0.1', createdAt: '2026-01-01T08:00:00Z' },
      ], 1),
    })
  }),

  /** 管理-审计日志导出 */
  http.get(`${API_BASE}/admin/logs/export`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-租户列表 */
  http.get(`${API_BASE}/admin/tenants`, () => {
    return HttpResponse.json({
      code: 0, message: 'success',
      data: paginatedResponse([
        { id: 2, phone: '13800000002', nickname: '测试管理员', email: 'admin2@example.com', status: 1, subUserCount: 2, deviceCount: 5, deviceLimit: 100, userLimit: 50, createdAt: '2025-01-01T00:00:00Z', lastLoginAt: '2026-01-01T00:00:00Z' },
      ], 1),
    })
  }),

  /** 管理-租户创建 */
  http.post(`${API_BASE}/admin/tenants`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-租户更新 */
  http.patch(`${API_BASE}/admin/tenants/:id`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-租户切换状态 */
  http.post(`${API_BASE}/admin/tenants/:id/toggle`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-系统配置 */
  http.get(`${API_BASE}/admin/system-config`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: {} })
  }),

  http.patch(`${API_BASE}/admin/system-config`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-指标 */
  http.get(`${API_BASE}/admin/metrics`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: {} })
  }),

  /** 管理-权限列表 */
  http.get(`${API_BASE}/admin/permissions`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  http.get(`${API_BASE}/admin/permissions/:role`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  http.put(`${API_BASE}/admin/permissions/:role`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  http.post(`${API_BASE}/admin/permissions/:role/toggle`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 管理-路由组 */
  http.get(`${API_BASE}/admin/route-groups`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 工单统计 */
  http.get(`${API_BASE}/work-order-stats`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { total: 10, open: 3, inProgress: 4, resolved: 2, closed: 1 } })
  }),

  /** 工单模板 */
  http.get(`${API_BASE}/work-order-templates`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 工单详情 */
  http.get(`${API_BASE}/work-orders/:id`, ({ params }) => {
    const wo = mockWorkOrders.find((w) => w.id === params.id)
    if (wo) {
      return HttpResponse.json({ code: 0, message: 'success', data: { ...wo, assigneeName: 'admin', creatorName: 'admin', deviceSn: 'INV20250001', timeline: [], attachments: [] } })
    }
    return HttpResponse.json({ code: 404, message: '工单不存在' }, { status: 404 })
  }),

  /** 工单状态更新 */
  http.patch(`${API_BASE}/work-orders/:id/status`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 设备命令模板 */
  http.get(`${API_BASE}/devices/by-sn/:sn/commands`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 设备命令历史 */
  http.get(`${API_BASE}/devices/by-sn/:sn/commands/history`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } })
  }),

  /** 设备命令执行 */
  http.post(`${API_BASE}/devices/by-sn/:sn/control`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { req_id: 'cmd-001' } })
  }),

  /** 型号字段 */
  http.get(`${API_BASE}/admin/models/:id/fields`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  http.get(`${API_BASE}/models/:id/fields`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: [] })
  }),

  /** 型号公开列表 */
  http.get(`${API_BASE}/models/public`, () => {
    return HttpResponse.json({
      code: 0, message: 'success',
      data: [
        { id: 1, model_code: 'SG-5K-D', model_name: 'SG-5K-D', manufacturer: 'CSERGY', category: 'inverter' },
      ],
    })
  }),

  /** 电站详情 */
  http.get(`${API_BASE}/stations/:id`, ({ params }) => {
    return HttpResponse.json({
      code: 0, message: 'success',
      data: { id: Number(params.id), name: '测试电站A', device_count: 10, status: 1, online_count: 8, fault_count: 1 },
    })
  }),

  /** 电站统计 */
  http.get(`${API_BASE}/stations/:id/statistics`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { today: 50.5, month: 1200, year: 15000, total: 80000 } })
  }),

  /** 电站设备 */
  http.get(`${API_BASE}/stations/:id/devices`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { items: mockDevices, total: mockDevices.length } })
  }),

  /** 电站告警 */
  http.get(`${API_BASE}/stations/:id/alarms`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { items: [], total: 0 } })
  }),

  /** 电站摘要 */
  http.get(`${API_BASE}/stations/summary`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { totalStations: 2, totalDevices: 15, onlineDevices: 12, todayGeneration: 100.5 } })
  }),

  /** 创建电站 */
  http.post(`${API_BASE}/stations`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 更新电站 */
  http.put(`${API_BASE}/stations/:id`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  http.patch(`${API_BASE}/stations/:id`, async () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 删除电站 */
  http.delete(`${API_BASE}/stations/:id`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: null })
  }),

  /** 时区配置 */
  http.get(`${API_BASE}/auth/timezone`, () => {
    return HttpResponse.json({ code: 0, message: 'success', data: { timezone: 'Asia/Shanghai' } })
  }),
]
