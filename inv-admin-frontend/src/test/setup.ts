/**
 * Vitest 全局 Setup 文件
 *
 * - 注入 `@testing-library/jest-dom` 的 DOM 断言扩展
 * - 启动/重置/关闭 MSW mock server
 * - 提供 jsdom 缺失的浏览器 API mock（matchMedia、IntersectionObserver 等）
 * - 每个测试结束后清理 zustand store 及 localStorage 状态
 */

import '@testing-library/jest-dom'
import { beforeAll, beforeEach, afterEach, afterAll, vi } from 'vitest'
import { server } from './mocks/server'

// ─── MSW 生命周期 ────────────────────────────────────────────────────────────

beforeAll(() => {
  server.listen({ onUnhandledRequest: 'warn' })
})

function createSafeLocation(href = 'http://localhost:5173/') {
  const url = new URL(href)
  return {
    href: url.href,
    protocol: url.protocol,
    host: url.host,
    hostname: url.hostname,
    port: url.port,
    pathname: url.pathname,
    search: url.search,
    hash: url.hash,
    origin: url.origin,
    assign: vi.fn(),
    replace: vi.fn(),
    reload: vi.fn(),
    toString: () => url.href,
  }
}

beforeEach(() => {
  // 为每个测试提供可安全作为 URL base 的 location 对象，避免 MSW 解析相对 URL 时报 Invalid URL
  Object.defineProperty(window, 'location', {
    writable: true,
    value: createSafeLocation(),
  })
})

afterEach(() => {
  // 重置所有运行时覆盖的 handler（通过 server.use(...) 添加的）
  server.resetHandlers()
})

afterAll(() => {
  server.close()
})

// ─── 浏览器 API Mock ─────────────────────────────────────────────────────────

/** jsdom 不支持 matchMedia，Ant Design 组件依赖此 API */
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})

/** jsdom 不支持 IntersectionObserver（部分 Ant Design 组件懒加载依赖） */
class MockIntersectionObserver {
  observe = vi.fn()
  unobserve = vi.fn()
  disconnect = vi.fn()
}
Object.defineProperty(window, 'IntersectionObserver', {
  writable: true,
  value: MockIntersectionObserver,
})

/** 安全包装 getComputedStyle，避免 jsdom 对未挂载元素抛出异常 */
const origGetComputedStyle = window.getComputedStyle
window.getComputedStyle = (elt: Element, pseudoElt?: string | null) => {
  try {
    return origGetComputedStyle(elt, pseudoElt)
  } catch {
    return {} as CSSStyleDeclaration
  }
}

/** 抑制 antd 在测试环境下的无害警告 */
const originalWarn = console.warn
console.warn = (...args: unknown[]) => {
  const msg = typeof args[0] === 'string' ? args[0] : ''
  if (msg.includes('antd') || msg.includes('[antd') || msg.includes('Warning:')) return
  originalWarn(...args)
}

// ─── 状态清理 ────────────────────────────────────────────────────────────────

afterEach(() => {
  // 清空 localStorage，避免 zustand persist 在不同测试间泄漏状态
  localStorage.clear()
  // 清空 sessionStorage
  sessionStorage.clear()
})
