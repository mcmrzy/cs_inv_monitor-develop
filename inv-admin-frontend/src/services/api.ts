import axios from 'axios'
import type { ApiResponse } from '@/types'
import useAuthStore from '@/stores/authStore'

const api = axios.create({
  baseURL: '/api/v1',
  timeout: 15000,
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
})

api.interceptors.request.use(
  (config) => {
    const token = useAuthStore.getState().token
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }
    return config
  },
  (error) => Promise.reject(error),
)

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config
    if (error.response?.status === 401 && !originalRequest._retry && window.location.pathname !== '/login') {
      originalRequest._retry = true
      const refreshToken = useAuthStore.getState().refreshToken
      if (refreshToken) {
        try {
          const res = await axios.post('/api/v1/auth/refresh', { refresh_token: refreshToken })
          const data = res.data?.data ?? res.data
          if (data?.access_token) {
            useAuthStore.getState().refreshAuth(data.access_token, data.refresh_token)
            originalRequest.headers.Authorization = `Bearer ${data.access_token}`
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
