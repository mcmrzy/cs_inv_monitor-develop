import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { Route, Routes } from 'react-router-dom'
import { renderWithProviders, screen, waitFor } from '@/test/test-utils'
import { mockEndUser, mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import OrganizationRoute from './OrganizationRoute'

const responseFor = (data: unknown) => ({ data: { code: 0, data } }) as never

function renderRoute(user = mockManagerUser, token = 'member-token') {
  return renderWithProviders(
    <Routes>
      <Route
        path="/organizations"
        element={
          <OrganizationRoute>
            <div>Organization Management</div>
          </OrganizationRoute>
        }
      />
      <Route path="/unauthorized" element={<div>Unauthorized Page</div>} />
    </Routes>,
    {
      routerProps: { initialEntries: ['/organizations'] },
      initialUser: user,
      initialToken: token,
    },
  )
}

describe('OrganizationRoute', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('shows a centered spinner while membership access is loading', () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockReturnValue(new Promise(() => undefined) as never)

    renderWithProviders(
      <OrganizationRoute>
        <div>Organization Management</div>
      </OrganizationRoute>,
      {
        initialUser: mockManagerUser,
        initialToken: 'member-token',
      },
    )

    expect(document.querySelector('.ant-spin')).toBeInTheDocument()
    expect(screen.queryByText('Organization Management')).not.toBeInTheDocument()
  })

  it('renders children for an organization member', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor([{ roles: ['installer'] }]),
    )

    renderRoute()

    await waitFor(() => {
      expect(screen.getByText('Organization Management')).toBeInTheDocument()
    })
  })

  it('redirects a pure customer to the unauthorized page', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor([{ roles: ['customer'] }]),
    )

    renderRoute(mockEndUser, 'customer-token')

    await waitFor(() => {
      expect(screen.getByText('Unauthorized Page')).toBeInTheDocument()
    })
    expect(screen.queryByText('Organization Management')).not.toBeInTheDocument()
  })
})
