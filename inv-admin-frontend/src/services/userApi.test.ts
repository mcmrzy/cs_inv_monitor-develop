import { describe, it, expect } from 'vitest'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { userApi } from './userApi'
import { mockUsers, paginatedResponse } from '@/test/mocks/data'

describe('userApi', () => {
  describe('list', () => {
    it('should fetch user list', async () => {
      const res = await userApi.list({ page: 1, page_size: 20 })
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(mockUsers.length)
      expect(data.total).toBe(mockUsers.length)
    })

    it('should filter users by role', async () => {
      server.use(
        http.get('/api/v1/users', ({ request }) => {
          const url = new URL(request.url)
          const role = url.searchParams.get('role')
          const filtered = mockUsers.filter((u) => String(u.role) === role)
          return HttpResponse.json({
            code: 0,
            data: paginatedResponse(filtered, filtered.length),
          })
        }),
      )

      const res = await userApi.getInstallers()
      const data = res.data?.data ?? res.data
      expect(data.items).toHaveLength(1)
      expect(data.items[0].role).toBe(4)
    })
  })

  describe('get', () => {
    it('should fetch user by id', async () => {
      const res = await userApi.get(1)
      const data = res.data?.data ?? res.data
      expect(data.id).toBe('1')
      expect(data.nickname).toBe('超级管理员')
    })

    it('should return 404 for non-existent user', async () => {
      try {
        await userApi.get(999)
        expect.fail('should have thrown')
      } catch (err: any) {
        expect(err.response?.status).toBe(404)
      }
    })
  })

  describe('create', () => {
    it('should create a new user', async () => {
      server.use(
        http.post('/api/v1/users', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { id: '4', ...body },
          })
        }),
      )

      const res = await userApi.create({
        phone: '13800000004',
        email: 'new@csergy.com',
        nickname: '新用户',
        password: 'Pass123',
        role: 5,
      })
      expect(res.data.code).toBe(0)
      expect(res.data.data.nickname).toBe('新用户')
    })
  })

  describe('update', () => {
    it('should update user info', async () => {
      server.use(
        http.patch('/api/v1/users/:id', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { ...body, updated: true },
          })
        }),
      )

      const res = await userApi.update('2', { nickname: '更新昵称' })
      expect(res.data.code).toBe(0)
    })
  })

  describe('delete', () => {
    it('should delete user', async () => {
      const res = await userApi.delete('3')
      expect(res.data.code).toBe(0)
    })
  })

  describe('resetPassword', () => {
    it('should reset user password', async () => {
      server.use(
        http.put('/api/v1/users/:id/password', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { hasNewPassword: !!body.newPassword },
          })
        }),
      )

      const res = await userApi.resetPassword(1, { password: 'NewPass123' })
      expect(res.data.code).toBe(0)
    })
  })

  describe('toggleStatus', () => {
    it('should toggle user status', async () => {
      server.use(
        http.put('/api/v1/users/:id/toggle', async ({ request }) => {
          const body = (await request.json()) as any
          return HttpResponse.json({
            code: 0,
            data: { newStatus: body.status },
          })
        }),
      )

      const res = await userApi.toggleStatus('2', 0)
      expect(res.data.code).toBe(0)
    })
  })
})
