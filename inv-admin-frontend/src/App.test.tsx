import { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useLocation } from 'react-router-dom'
import { renderWithProviders, screen, waitFor } from '@/test/test-utils'
import { mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import { AppRoutes } from './App'

vi.mock('@/utils/lazyWithRetry', () => ({
  default: () => function MockLazyPage() {
    return <div data-testid="mock-route-page">route page</div>
  },
}))

function LocationProbe() {
  const location = useLocation()
  return <output data-testid="location">{location.pathname}</output>
}

function renderRoutes(initialEntry: string, permissions: string[] = []) {
  return renderWithProviders(
    <>
      <AppRoutes />
      <LocationProbe />
    </>,
    {
      routerProps: { initialEntries: [initialEntry] },
      initialUser: mockManagerUser,
      initialToken: 'route-token',
      initialPermissions: permissions,
    },
  )
}

describe('AppRoutes permission integration', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue({
      data: { code: 0, data: [{ roles: ['installer'] }] },
    } as never)
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it.each([
    ['/users', ['users:view']],
    ['/big-screen', ['dashboard:view']],
    ['/devices/INV-001/detail', ['devices:view']],
  ])('keeps an authorized user on %s', async (path, permissions) => {
    renderRoutes(path, permissions)
    await waitFor(() => expect(screen.getByTestId('location')).toHaveTextContent(path))
    expect(screen.getByTestId('mock-route-page')).toBeInTheDocument()
  })

  it('redirects a direct users URL without permission to unauthorized', async () => {
    renderRoutes('/users')
    await waitFor(() => expect(screen.getByTestId('location')).toHaveTextContent('/unauthorized'))
  })

  it('uses the first permitted route when the root URL is opened', async () => {
    renderRoutes('/', ['users:view'])
    await waitFor(() => expect(screen.getByTestId('location')).toHaveTextContent('/users'))
  })

  it('redirects the legacy admin URL through organization access', async () => {
    renderRoutes('/admin')
    await waitFor(() => expect(screen.getByTestId('location')).toHaveTextContent('/organizations'))
    expect(screen.getByTestId('mock-route-page')).toBeInTheDocument()
  })

  it('sends an unauthenticated protected URL to login', async () => {
    vi.useFakeTimers()
    try {
      renderWithProviders(
        <>
          <AppRoutes />
          <LocationProbe />
        </>,
        {
          routerProps: { initialEntries: ['/users'] },
          initialUser: null,
          initialToken: null,
        },
      )
      await act(async () => {
        vi.advanceTimersByTime(2_000)
      })
      expect(screen.getByTestId('location')).toHaveTextContent('/login')
    } finally {
      vi.useRealTimers()
    }
  })
})
