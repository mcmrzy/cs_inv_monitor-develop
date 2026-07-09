import { describe, it, expect, beforeEach, vi } from 'vitest'
import axios from 'axios'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import useAuthStore from '@/stores/authStore'
import api, { authApi } from './api'

describe('Axios Instance Configuration', () => {
  it('should have correct baseURL', () => {
    expect(api.defaults.baseURL).toBe('/api/v1')
  })

  it('should have correct timeout', () => {
    expect(api.defaults.timeout).toBe(15000)
  })

  it('should have withCredentials enabled', () => {
    expect(api.defaults.withCredentials).toBe(true)
  })

  it('should have JSON content type', () => {
    expect(api.defaults.headers['Content-Type']).toBe('application/json')
  })
})

describe('Request Interceptor - Token Injection', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('should add Authorization header when token exists', async () => {
    useAuthStore.getState().login('test-token', 'refresh', {
      id: '1', phone: '', email: '', nickname: '', avatar: '',
      role: 0, status: 1, timezone: '', lastLoginAt: '', createdAt: '',
    })

    server.use(
      http.get('/api/v1/test', ({ request }) => {
        const auth = request.headers.get('Authorization')
        return HttpResponse.json({ code: 0, data: { auth } })
      }),
    )

    const res = await api.get('/test')
    expect(res.data.data.auth).toBe('Bearer test-token')
  })

  it('should not add Authorization header when no token', async () => {
    server.use(
      http.get('/api/v1/test', ({ request }) => {
        const auth = request.headers.get('Authorization')
        return HttpResponse.json({ code: 0, data: { auth: auth || null } })
      }),
    )

    const res = await api.get('/test')
    expect(res.data.data.auth).toBeNull()
  })
})

describe('Response Interceptor - 401 Token Refresh', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('should attempt token refresh on 401 response', async () => {
    useAuthStore.getState().login('expired-token', 'valid-refresh', {
      id: '1', phone: '', email: '', nickname: '', avatar: '',
      role: 0, status: 1, timezone: '', lastLoginAt: '', createdAt: '',
    })

    let requestCount = 0
    server.use(
      http.get('/api/v1/test', ({ request }) => {
        requestCount++
        const auth = request.headers.get('Authorization')
        if (auth === 'Bearer expired-token') {
          return HttpResponse.json({ code: 401, message: 'unauthorized' }, { status: 401 })
        }
        return HttpResponse.json({ code: 0, data: 'success' })
      }),
    )

    // Set pathname to non-login to trigger refresh logic
    Object.defineProperty(window, 'location', {
      writable: true,
      value: { ...window.location, pathname: '/dashboard', href: 'http://localhost:5173/dashboard' },
    })

    const res = await api.get('/test')
    expect(res.data.data).toBe('success')
    expect(requestCount).toBe(2) // original + retry
  })

  it('should redirect to login when refresh fails', async () => {
    useAuthStore.getState().login('expired-token', 'bad-refresh', {
      id: '1', phone: '', email: '', nickname: '', avatar: '',
      role: 0, status: 1, timezone: '', lastLoginAt: '', createdAt: '',
    })

    server.use(
      http.get('/api/v1/test', () => {
        return HttpResponse.json({ code: 401, message: 'unauthorized' }, { status: 401 })
      }),
      http.post('/api/v1/auth/refresh', () => {
        return HttpResponse.json({ code: 401, message: 'refresh failed' }, { status: 401 })
      }),
    )

    Object.defineProperty(window, 'location', {
      writable: true,
      value: { ...window.location, pathname: '/dashboard', href: 'http://localhost:5173/dashboard' },
    })

    try {
      await api.get('/test')
    } catch {
      // expected
    }

    expect(useAuthStore.getState().isAuthenticated).toBe(false)
  })
})

describe('authApi', () => {
  it('login should post credentials and return tokens', async () => {
    const res = await authApi.login({ account: 'admin@example.com', password: 'Admin123' })
    expect(res.data.data?.token).toBe('mock-jwt-token')
    expect(res.data.data?.refresh_token).toBe('mock-refresh-token')
  })

  it('login should fail with wrong credentials', async () => {
    try {
      await authApi.login({ account: 'bad@example.com', password: 'wrong' })
      expect.fail('should have thrown')
    } catch (err: any) {
      expect(err.response?.status).toBe(401)
    }
  })

  it('refreshToken should return new tokens', async () => {
    const res = await authApi.refreshToken('valid-refresh')
    expect(res.data).toBeDefined()
  })

  it('logout should call the logout endpoint', async () => {
    const res = await authApi.logout()
    expect(res.data.code).toBe(0)
  })
})
