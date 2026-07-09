/**
 * MSW setupServer 实例
 *
 * 用于 Node.js 环境（vitest/jsdom）下的 API 拦截。
 * 在 `setup.ts` 中通过生命周期钩子统一管理启停。
 *
 * @example
 * ```ts
 * import { server } from '@/test/mocks/server'
 * import { http, HttpResponse } from 'msw'
 *
 * // 在单个测试中覆盖默认 handler
 * server.use(
 *   http.get('/api/v1/devices', () => HttpResponse.json({ code: 0, data: { items: [] } }))
 * )
 * ```
 */

import { setupServer } from 'msw/node'
import { handlers } from './handlers'

export const server = setupServer(...handlers)
