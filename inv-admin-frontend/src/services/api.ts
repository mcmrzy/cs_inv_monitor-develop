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
      const refreshToken = useAuthStore.getState().refreshToken
      if (refreshToken) {
        try {
          const res = await axios.post('/api/v1/auth/refresh', { refresh_token: refreshToken })
          const data = res.data?.data ?? res.data
          const token = data?.token ?? data?.access_token
          if (token) {
            useAuthStore.getState().refreshAuth(token, data.refresh_token ?? '')
            originalRequest.headers.Authorization = `Bearer ${token}`
            return api(originalRequest)
          }
        } catch {
          // refresh failed, fall through to logout
        }
      }
      useAuthStore.getState().logout()
      window.location.href = '/login'
    }
    return Promise.reject(error)
  },
)

export const authApi = {
  login: (data: { account: string; password: string }) =>
    api.post<ApiResponse<{ token: string; refresh_token: string; user: unknown }>>('/auth/login', data),

  refreshToken: (refreshToken: string) =>
    api.post<ApiResponse<{ token: string; refresh_token: string }>>('/auth/refresh', { refresh_token: refreshToken }),

  logout: () =>
    api.post<ApiResponse<null>>('/auth/logout'),
}

export default api
