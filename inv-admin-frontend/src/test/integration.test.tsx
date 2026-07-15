import { describe, it, expect, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { server } from '@/test/mocks/server'
import { renderWithProviders } from '@/test/test-utils'
import { mockAdminUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { vi } from 'vitest'
import LoginPage from '@/pages/login'
import ProtectedRoute from '@/components/ProtectedRoute'
import MainLayout from '@/layouts/MainLayout'
import DashboardPage from '@/pages/dashboard'
import { Routes, Route, Navigate } from 'react-router-dom'

// Mock components that have complex dependencies
vi.mock('@/components/SliderCaptcha/SliderCaptchaModal', () => ({
  default: () => null,
}))

// Mock echarts to avoid canvas issues in jsdom
vi.mock('@/lib/echarts', () => ({
  default: () => <div data-testid="echarts-mock">chart</div>,
}))

// Mock react-leaflet
vi.mock('react-leaflet', () => ({
  MapContainer: ({ children }: any) => <div data-testid="map-mock">{children}</div>,
  TileLayer: () => null,
  Marker: () => null,
  Popup: () => null,
  useMap: () => ({}),
}))

vi.mock('leaflet', () => ({
  Icon: class { constructor() {} },
  divIcon: () => ({}),
  marker: () => ({}),
}))

describe('Integration Tests', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  describe('Login Flow', () => {
    it('should complete full login flow: enter credentials -> submit -> auth state updated', async () => {
      const user = userEvent.setup()
      renderWithProviders(<LoginPage />, { routerProps: { initialEntries: ['/login'] } })

      // Login page should show welcome text
      await waitFor(() => {
        expect(screen.getByText('欢迎回来')).toBeInTheDocument()
      })

      // Fill in credentials
      const accountInput = screen.getByPlaceholderText('手机号 / 邮箱')
      const passwordInput = screen.getByPlaceholderText('密码')

      await user.type(accountInput, 'admin@example.com')
      await user.type(passwordInput, 'Admin123')

      // Submit
      await user.click(screen.getByText('登 录'))

      // After login, auth state should be updated
      await waitFor(() => {
        const state = useAuthStore.getState()
        expect(state.isAuthenticated).toBe(true)
        expect(state.token).toBe('mock-jwt-token')
        expect(state.user?.id).toBe('1')
      })
    })

    it('should show error message on failed login', async () => {
      const user = userEvent.setup()
      renderWithProviders(<LoginPage />, { routerProps: { initialEntries: ['/login'] } })

      await waitFor(() => {
        expect(screen.getByText('欢迎回来')).toBeInTheDocument()
      })

      const accountInput = screen.getByPlaceholderText('手机号 / 邮箱')
      const passwordInput = screen.getByPlaceholderText('密码')

      await user.type(accountInput, 'bad@email.com')
      await user.type(passwordInput, 'badpassword')
      await user.click(screen.getByText('登 录'))

      await waitFor(() => {
        const alerts = document.querySelectorAll('.ant-alert-error')
        expect(alerts.length).toBeGreaterThan(0)
      })
    })
  })

  describe('Unauthenticated Route Protection', () => {
    it('should show login page when accessing protected route without auth', async () => {
      // Render ProtectedRoute wrapping a dummy component, starting at /
      renderWithProviders(
        <Routes>
          <Route path="/" element={
            <ProtectedRoute>
              <div>Protected Content</div>
            </ProtectedRoute>
          } />
          <Route path="/login" element={<LoginPage />} />
        </Routes>,
        { routerProps: { initialEntries: ['/'] } },
      )

      // ProtectedRoute should redirect to /login, showing the login page
      await waitFor(
        () => {
          expect(screen.getByText('欢迎回来')).toBeInTheDocument()
        },
        { timeout: 5000 },
      )
    })
  })

  describe('Authenticated Navigation', () => {
    it('should show dashboard when authenticated user navigates to /', async () => {
      useAuthStore.getState().login(
        'mock-token',
        'mock-refresh',
        mockAdminUser,
        ['dashboard:view', 'devices:view', 'firmware:view', 'alerts:view', 'users:view', 'admin:view'],
      )

      // Render ProtectedRoute + MainLayout at /dashboard
      renderWithProviders(
        <Routes>
          <Route element={
            <ProtectedRoute>
              <MainLayout />
            </ProtectedRoute>
          }>
            <Route path="/dashboard" element={<DashboardPage />} />
          </Route>
        </Routes>,
        { routerProps: { initialEntries: ['/dashboard'] } },
      )

      // Should render MainLayout with sider
      await waitFor(() => {
        const sider = document.querySelector('.ant-layout-sider')
        expect(sider).toBeInTheDocument()
      }, { timeout: 5000 })
    })
  })
})
