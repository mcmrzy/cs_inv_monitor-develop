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

  // 一次 5xx / 网络抖动不能被当成“无权限”，否则用户会被永久钉在 403 页面。
  it('shows a retryable error instead of the unauthorized page when the lookup fails', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockRejectedValue(
      Object.assign(new Error('boom'), { response: { status: 500 } }),
    )

    renderRoute()

    await waitFor(() => {
      expect(screen.getByText('暂时无法确认您的组织权限')).toBeInTheDocument()
    })
    expect(screen.queryByText('Unauthorized Page')).not.toBeInTheDocument()
    expect(screen.queryByText('Organization Management')).not.toBeInTheDocument()
    // antd 会在两个中文字之间插空格，断言用正则匹配
    expect(screen.getByRole('button', { name: /重\s*试/ })).toBeInTheDocument()
  })

  it('still redirects to the unauthorized page on a 403 verdict', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockRejectedValue(
      Object.assign(new Error('forbidden'), { response: { status: 403 } }),
    )

    renderRoute()

    await waitFor(() => {
      expect(screen.getByText('Unauthorized Page')).toBeInTheDocument()
    })
  })
})
