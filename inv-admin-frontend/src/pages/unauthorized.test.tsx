import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { renderWithProviders, screen, waitFor } from '@/test/test-utils'
import { mockAdminUser, mockEndUser, mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import UnauthorizedPage from './unauthorized'

const responseFor = (data: unknown) => ({ data: { code: 0, data } }) as never

describe('UnauthorizedPage', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  // 没有任何权限路由时，“返回首页”会被守卫原样弹回本页，形成死循环，所以只能给退出登录。
  it('offers sign-out instead of a looping home button for a permission-less account', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(responseFor([]))

    renderWithProviders(<UnauthorizedPage />, {
      initialUser: mockEndUser,
      initialToken: 'customer-token',
      initialPermissions: [],
    })

    await waitFor(() => {
      expect(screen.getByRole('button', { name: '退出登录' })).toBeInTheDocument()
    })
    expect(screen.queryByRole('button', { name: '返回首页' })).not.toBeInTheDocument()
  })

  it('keeps a home button for accounts that do have an accessible route', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor([{ roles: ['installer'] }]),
    )

    renderWithProviders(<UnauthorizedPage />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
      initialPermissions: ['devices:view'],
    })

    await waitFor(() => {
      expect(screen.getByRole('button', { name: '返回首页' })).toBeInTheDocument()
    })
    expect(screen.getByRole('button', { name: '退出登录' })).toBeInTheDocument()
  })

  it('keeps a home button for system administrators', async () => {
    const getMyOrganizations = vi.spyOn(channelApi, 'getMyOrganizations')

    renderWithProviders(<UnauthorizedPage />, {
      initialUser: { ...mockAdminUser, isSystemAdmin: true },
      initialToken: 'admin-token',
      initialPermissions: [],
    })

    await waitFor(() => {
      expect(screen.getByRole('button', { name: '返回首页' })).toBeInTheDocument()
    })
    expect(getMyOrganizations).not.toHaveBeenCalled()
  })
})
