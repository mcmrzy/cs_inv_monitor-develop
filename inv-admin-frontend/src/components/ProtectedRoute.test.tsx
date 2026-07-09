import { describe, it, expect, beforeEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import { renderWithProviders } from '@/test/test-utils'
import { mockAdminUser } from '@/test/mocks/data'
import ProtectedRoute from './ProtectedRoute'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'

describe('ProtectedRoute', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  it('should show loading spinner initially', () => {
    renderWithProviders(
      <ProtectedRoute>
        <div>Protected Content</div>
      </ProtectedRoute>,
    )

    // Should show spinner (antd Spin component)
    const spinner = document.querySelector('.ant-spin')
    expect(spinner).toBeInTheDocument()
  })

  it('should redirect to /login when not authenticated', async () => {
    renderWithProviders(
      <ProtectedRoute>
        <div>Protected Content</div>
      </ProtectedRoute>,
    )

    // After timeout in ProtectedRoute (2s), it should redirect
    await waitFor(
      () => {
        expect(screen.queryByText('Protected Content')).not.toBeInTheDocument()
      },
      { timeout: 3000 },
    )
  })

  it('should render children when authenticated', async () => {
    // Pre-login before render
    useAuthStore.getState().login('test-token', 'refresh', mockAdminUser, [])

    renderWithProviders(
      <ProtectedRoute>
        <div>Protected Content</div>
      </ProtectedRoute>,
    )

    await waitFor(() => {
      expect(screen.getByText('Protected Content')).toBeInTheDocument()
    })
  })

  it('should render children when token is set after mount', async () => {
    renderWithProviders(
      <ProtectedRoute>
        <div>Protected Content</div>
      </ProtectedRoute>,
    )

    // Initially should be loading
    expect(document.querySelector('.ant-spin')).toBeInTheDocument()

    // Set token after a short delay
    setTimeout(() => {
      useAuthStore.getState().login('test-token', 'refresh', mockAdminUser, [])
    }, 100)

    await waitFor(() => {
      expect(screen.getByText('Protected Content')).toBeInTheDocument()
    })
  })
})
