/**
 * 测试基础设施验证套件
 *
 * 验证以下核心能力：
 * 1. vitest 正常运行（describe/it/expect）
 * 2. MSW 正确拦截 API 请求
 * 3. renderWithProviders 正确渲染 React 组件
 * 4. jest-dom 扩展断言可用
 */

import React from 'react'
import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { renderWithProviders, screen, waitFor } from './test-utils'
import { server } from './mocks/server'
import { mockAdminUser, mockDevices, mockUsers, mockFirmwares } from './mocks/data'
import api from '@/services/api'

// ─── 1. Vitest 基础能力 ───────────────────────────────────────────────────────

describe('Vitest 基础能力', () => {
  it('支持基本断言', () => {
    expect(1 + 1).toBe(2)
    expect(true).toBeTruthy()
    expect(null).toBeNull()
  })

  it('支持异步断言', async () => {
    const result = await Promise.resolve('hello')
    expect(result).toBe('hello')
  })
})

// ─── 2. jest-dom 扩展断言 ─────────────────────────────────────────────────────

describe('jest-dom 扩展断言', () => {
  it('toBeInTheDocument() 可用', () => {
    const div = document.createElement('div')
    div.textContent = 'test'
    document.body.appendChild(div)
    expect(div).toBeInTheDocument()
    document.body.removeChild(div)
  })

  it('toBeVisible() / toBeDisabled() 可用', () => {
    const btn = document.createElement('button')
    btn.textContent = 'Click'
    document.body.appendChild(btn)
    expect(btn).toBeVisible()
    expect(btn).not.toBeDisabled()
    document.body.removeChild(btn)
  })
})

// ─── 3. MSW 拦截验证 ──────────────────────────────────────────────────────────

describe('MSW Mock Server', () => {
  it('拦截登录请求并返回 mock 数据', async () => {
    const res = await api.post('/auth/login', {
      account: 'admin@example.com',
      password: 'Admin123',
    })
    expect(res.data.code).toBe(0)
    expect(res.data.data).toHaveProperty('token')
    expect(res.data.data.user).toEqual(mockAdminUser)
  })

  it('拦截设备列表请求', async () => {
    const res = await api.get('/devices')
    expect(res.data.code).toBe(0)
    expect(res.data.data.items).toEqual(mockDevices)
    expect(res.data.data.total).toBe(mockDevices.length)
  })

  it('拦截用户列表请求', async () => {
    const res = await api.get('/users')
    expect(res.data.code).toBe(0)
    expect(res.data.data.items).toEqual(mockUsers)
  })

  it('拦截固件列表请求', async () => {
    const res = await api.get('/firmwares')
    expect(res.data.code).toBe(0)
    expect(res.data.data.items).toEqual(mockFirmwares)
  })

  it('支持 server.use() 覆盖默认 handler', async () => {
    const customDevices = [{ sn: 'CUSTOM-001', model: 'X-100' }]
    server.use(
      http.get('/api/v1/devices', () =>
        HttpResponse.json({
          code: 0,
          message: 'success',
          data: { items: customDevices, total: 1, page: 1, pageSize: 20 },
        }),
      ),
    )

    const res = await api.get('/devices')
    expect(res.data.data.items).toEqual(customDevices)
    expect(res.data.data.total).toBe(1)
  })

  it('server.resetHandlers() 后恢复默认 handler', async () => {
    // 上一个 test 的 server.use() 应已被 afterEach 中的 resetHandlers 清除
    const res = await api.get('/devices')
    expect(res.data.data.items).toEqual(mockDevices)
  })
})

// ─── 4. renderWithProviders 验证 ──────────────────────────────────────────────

describe('renderWithProviders', () => {
  function TestComponent({ name }: { name: string }) {
    return <div data-testid="greeting">你好，{name}！</div>
  }

  it('正确渲染简单组件', () => {
    renderWithProviders(<TestComponent name="测试用户" />)
    expect(screen.getByTestId('greeting')).toBeInTheDocument()
    expect(screen.getByText('你好，测试用户！')).toBeVisible()
  })

  it('支持自定义路由初始路径', () => {
    renderWithProviders(<TestComponent name="路由测试" />, {
      routerProps: { initialEntries: ['/devices'] },
    })
    expect(screen.getByText('你好，路由测试！')).toBeInTheDocument()
  })

  it('异步组件配合 waitFor 正常工作', async () => {
    function AsyncComponent() {
      const [data, setData] = React.useState<string | null>(null)
      React.useEffect(() => {
        api.get('/devices').then((res) => {
          setData(`设备数：${res.data.data.total}`)
        })
      }, [])
      return <div>{data ?? '加载中...'}</div>
    }

    renderWithProviders(<AsyncComponent />)
    expect(screen.getByText('加载中...')).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByText(`设备数：${mockDevices.length}`)).toBeInTheDocument()
    })
  })
})
