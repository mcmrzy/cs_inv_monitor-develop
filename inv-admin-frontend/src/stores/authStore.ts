import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { User } from '@/types'

interface AuthState {
  token: string | null
  refreshToken: string | null
  user: User | null
  permissions: string[]
  isAuthenticated: boolean
  login: (token: string, refreshToken: string, user: User, permissions?: string[]) => void
  logout: () => void
  setUser: (user: User) => void
  refreshAuth: (token: string, refreshToken: string) => void
  hasPermission: (permission: string) => boolean
  hasAnyPermission: (...permissions: string[]) => boolean
}

type PersistedState = Pick<AuthState, 'token' | 'refreshToken' | 'user' | 'permissions' | 'isAuthenticated'>

const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      refreshToken: null,
      user: null,
      permissions: [],
      isAuthenticated: false,

      login: (token, refreshToken, user, permissions = []) =>
        set({ token, refreshToken, user, permissions, isAuthenticated: true }),

      logout: () =>
        set({ token: null, refreshToken: null, user: null, permissions: [], isAuthenticated: false }),

      setUser: (user) => set({ user }),

      refreshAuth: (token, refreshToken) => set({ token, refreshToken }),

      hasPermission: (perm: string): boolean => {
        const state = get()
        if ((state.user?.role ?? 99) <= 1) return true  // super_admin + admin
        if (!Array.isArray(state.permissions)) return false
        return state.permissions.includes(perm)
      },

      hasAnyPermission: (...perms: string[]): boolean => {
        const state = get()
        if ((state.user?.role ?? 99) <= 1) return true  // super_admin + admin
        if (!Array.isArray(state.permissions)) return false
        return perms.some(p => state.permissions.includes(p))
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state): PersistedState => ({
        token: state.token,
        refreshToken: state.refreshToken,
        user: state.user,
        permissions: state.permissions,
        isAuthenticated: state.isAuthenticated,
      }),
    },
  ),
)

export default useAuthStore
