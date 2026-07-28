import axios, { AxiosError } from 'axios'
import type { ApiResponse } from '@/types'
import useAuthStore from '@/stores/authStore'

export type ExpectedDataShape = 'object' | 'array' | 'page'

declare module 'axios' {
  interface AxiosRequestConfig {
    expectedDataShape?: ExpectedDataShape
  }
}

function isObjectData(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function matchesExpectedShape(value: unknown, expected: ExpectedDataShape): boolean {
  if (expected === 'array') return Array.isArray(value)
  if (expected === 'object') return isObjectData(value)
  return isObjectData(value)
    && Array.isArray(value.items)
    && typeof value.total === 'number'
}

/** 解析 JWT token 获取过期时间（秒级时间戳） */
function parseJwtExp(token: string): number | null {
  try {
    const payload = token.split('.')[1]
    if (!payload) return null
    const decoded = JSON.parse(atob(payload))
    return decoded.exp ?? null
  } catch {
    return null
  }
}

// Token 刷新状态管理
let isRefreshing = false
let refreshSubscribers: Array<(token: string) => void> = []
let proactiveRefreshTimer: ReturnType<typeof setTimeout> | null = null

function subscribeTokenRefresh(cb: (token: string) => void) {
  refreshSubscribers.push(cb)
}

function onTokenRefreshed(newToken: string) {
  refreshSubscribers.forEach(cb => cb(newToken))
  refreshSubscribers = []
}

/** 设置主动定时刷新：在 token 过期前 2 分钟自动刷新 */
scheduleProactiveRefresh()

function scheduleProactiveRefresh() {
  if (proactiveRefreshTimer) {
    clearTimeout(proactiveRefreshTimer)
    proactiveRefreshTimer = null
  }
  const token = useAuthStore.getState().token
  if (!token) return
  const exp = parseJwtExp(token)
  if (!exp) return
  const now = Math.floor(Date.now() / 1000)
  const refreshIn = (exp - now - 120) * 1000 // 提前 2 分钟刷新
  if (refreshIn <= 0) {
    // token 已过期或即将过期，立即刷新
    doRefreshToken()
    return
  }
  proactiveRefreshTimer = setTimeout(() => doRefreshToken(), refreshIn)
}

async function doRefreshToken(): Promise<string | null> {
  const refreshToken = useAuthStore.getState().refreshToken
  if (!refreshToken) return null
  try {
    const res = await axios.post('/api/v1/auth/refresh', { refresh_token: refreshToken })
    const data = res.data?.data ?? res.data
    const newToken = data?.token ?? data?.access_token
    if (newToken) {
      useAuthStore.getState().refreshAuth(newToken, data.refresh_token ?? '')
      scheduleProactiveRefresh() // 重新调度下次刷新
      return newToken
    }
  } catch {
    // 刷新失败
  }
  return null
}

const api = axios.create({
  baseURL: '/api/v1',
  timeout: 15000,
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
})

/**
 * 将 params 中的 camelCase 分页参数转换为 snake_case。
 * 作为额外保障：即使某些调用方仍使用 pageSize，也能在请求发出前统一为 page_size。
 */
function normalizeParams(params: Record<string, unknown>): Record<string, unknown> {
  if (params && typeof params === 'object' && 'pageSize' in params && !('page_size' in params)) {
    const { pageSize, ...rest } = params
    return { ...rest, page_size: pageSize }
  }
  return params
}

api.interceptors.request.use(
  (config) => {
    const token = useAuthStore.getState().token
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    if (config.params && typeof config.params === 'object') {
      config.params = normalizeParams(config.params)
    }
    return config
  },
  (error) => Promise.reject(error),
)

api.interceptors.response.use(
  (response) => {
    const body = response.data
    if (body && typeof body === 'object' && 'code' in body) {
      const code = Number((body as ApiResponse<unknown>).code)
      if (Number.isFinite(code) && code !== 0) {
        throw new AxiosError(
          (body as ApiResponse<unknown>).message || `API error ${code}`,
          'ERR_BUSINESS_RESPONSE',
          response.config,
          response.request,
          response,
        )
      }

      const method = response.config.method?.toLowerCase()
      if (method === 'get' && !Object.prototype.hasOwnProperty.call(body, 'data')) {
        throw new AxiosError(
          'Response format error: missing data',
          'ERR_RESPONSE_FORMAT',
          response.config,
          response.request,
          response,
        )
      }

      const expectedShape = response.config.expectedDataShape
      if (expectedShape && !matchesExpectedShape((body as ApiResponse<unknown>).data, expectedShape)) {
        throw new AxiosError(
          `Response format error: expected ${expectedShape} data`,
          'ERR_RESPONSE_FORMAT',
          response.config,
          response.request,
          response,
        )
      }
    }
    return response
  },
  async (error) => {
    const originalRequest = error.config
    if (error.response?.status === 401 && !originalRequest._retry && window.location.pathname !== '/login') {
      originalRequest._retry = true

      // 如果正在刷新中，将请求加入队列等待
      if (isRefreshing) {
        return new Promise((resolve) => {
          subscribeTokenRefresh((newToken: string) => {
            originalRequest.headers.Authorization = `Bearer ${newToken}`
            resolve(api(originalRequest))
          })
        })
      }

      isRefreshing = true
      const newToken = await doRefreshToken()
      isRefreshing = false

      if (newToken) {
        // 通知所有等待的请求
        onTokenRefreshed(newToken)
        originalRequest.headers.Authorization = `Bearer ${newToken}`
        return api(originalRequest)
      }

      // 刷新失败，跳转登录页
      useAuthStore.getState().logout()
      window.location.href = '/login'
    }
    return Promise.reject(error)
  },
)

// 监听 authStore 变化，token 变更时重新调度主动刷新
useAuthStore.subscribe((state, prevState) => {
  if (state.token !== prevState.token) {
    scheduleProactiveRefresh()
  }
})

export const authApi = {
  login: (data: { account: string; password: string }) =>
    api.post<ApiResponse<{ token: string; refresh_token: string; user: unknown }>>('/auth/login', data),

  refreshToken: (refreshToken: string) =>
    api.post<ApiResponse<{ token: string; refresh_token: string }>>('/auth/refresh', { refresh_token: refreshToken }),

  logout: () =>
    api.post<ApiResponse<null>>('/auth/logout'),
}

export default api
