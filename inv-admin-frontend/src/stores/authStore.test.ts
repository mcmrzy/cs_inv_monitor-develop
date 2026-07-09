import { describe, it, expect, beforeEach } from 'vitest'
import useAuthStore from './authStore'
import { Role } from '@/types'
import type { User } from '@/types'

const mockUser: User = {
  id: '1',
  phone: '13800000001',
  email: 'admin@csergy.com',
  nickname: 'Admin',
  avatar: '',
  role: Role.SUPER_ADMIN,
  status: 1,
  timezone: 'Asia/Shanghai',
  lastLoginAt: '2026-07-01T08:00:00Z',
  createdAt: '2025-01-01T00:00:00Z',
}

describe('authStore', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  describe('Initial State', () => {
    it('should have default unauthenticated state', () => {
      const state = useAuthStore.getState()
      expect(state.token).toBeNull()
      expect(state.refreshToken).toBeNull()
      expect(state.user).toBeNull()
      expect(state.permissions).toEqual([])
      expect(state.isAuthenticated).toBe(false)
    })
  })

  describe('login', () => {
    it('should set auth state on login', () => {
      const { login } = useAuthStore.getState()
      login('test-token', 'test-refresh', mockUser, ['devices:view', 'alerts:view'])

      const state = useAuthStore.getState()
      expect(state.token).toBe('test-token')
      expect(state.refreshToken).toBe('test-refresh')
      expect(state.user).toEqual(mockUser)
      expect(state.permissions).toEqual(['devices:view', 'alerts:view'])
      expect(state.isAuthenticated).toBe(true)
    })

    it('should default permissions to empty array', () => {
      const { login } = useAuthStore.getState()
      login('token', 'refresh', mockUser)

      expect(useAuthStore.getState().permissions).toEqual([])
    })
  })

  describe('logout', () => {
    it('should clear all auth state on logout', () => {
      const { login, logout } = useAuthStore.getState()
      login('token', 'refresh', mockUser, ['devices:view'])
      logout()

      const state = useAuthStore.getState()
      expect(state.token).toBeNull()
      expect(state.refreshToken).toBeNull()
      expect(state.user).toBeNull()
      expect(state.permissions).toEqual([])
      expect(state.isAuthenticated).toBe(false)
    })
  })

  describe('setUser', () => {
    it('should update user without affecting tokens', () => {
      const { login, setUser } = useAuthStore.getState()
      login('token', 'refresh', mockUser)

      const updatedUser = { ...mockUser, nickname: 'Updated' }
      setUser(updatedUser)

      expect(useAuthStore.getState().user?.nickname).toBe('Updated')
      expect(useAuthStore.getState().token).toBe('token')
    })
  })

  describe('refreshAuth', () => {
    it('should update tokens without affecting user', () => {
      const { login, refreshAuth } = useAuthStore.getState()
      login('old-token', 'old-refresh', mockUser)

      refreshAuth('new-token', 'new-refresh')

      const state = useAuthStore.getState()
      expect(state.token).toBe('new-token')
      expect(state.refreshToken).toBe('new-refresh')
      expect(state.user).toEqual(mockUser)
    })
  })

  describe('hasPermission', () => {
    it('should return true for super admin regardless of permissions', () => {
      const { login } = useAuthStore.getState()
      login('token', 'refresh', mockUser, [])

      expect(useAuthStore.getState().hasPermission('any:permission')).toBe(true)
    })

    it('should check permission in list for non-admin', () => {
      const normalUser = { ...mockUser, role: Role.AGENT }
      const { login } = useAuthStore.getState()
      login('token', 'refresh', normalUser, ['devices:view', 'alerts:view'])

      expect(useAuthStore.getState().hasPermission('devices:view')).toBe(true)
      expect(useAuthStore.getState().hasPermission('admin:view')).toBe(false)
    })

    it('should return false when permissions is not an array', () => {
      const normalUser = { ...mockUser, role: Role.END_USER }
      const { login } = useAuthStore.getState()
      login('token', 'refresh', normalUser)
      // Manually corrupt permissions
      useAuthStore.setState({ permissions: undefined as any })

      expect(useAuthStore.getState().hasPermission('devices:view')).toBe(false)
    })
  })

  describe('hasAnyPermission', () => {
    it('should return true for super admin', () => {
      const { login } = useAuthStore.getState()
      login('token', 'refresh', mockUser, [])

      expect(useAuthStore.getState().hasAnyPermission('a', 'b')).toBe(true)
    })

    it('should return true when any permission matches', () => {
      const normalUser = { ...mockUser, role: Role.AGENT }
      const { login } = useAuthStore.getState()
      login('token', 'refresh', normalUser, ['devices:view'])

      expect(useAuthStore.getState().hasAnyPermission('devices:view', 'admin:view')).toBe(true)
    })

    it('should return false when no permissions match', () => {
      const normalUser = { ...mockUser, role: Role.AGENT }
      const { login } = useAuthStore.getState()
      login('token', 'refresh', normalUser, ['devices:view'])

      expect(useAuthStore.getState().hasAnyPermission('admin:view', 'users:edit')).toBe(false)
    })
  })
})
