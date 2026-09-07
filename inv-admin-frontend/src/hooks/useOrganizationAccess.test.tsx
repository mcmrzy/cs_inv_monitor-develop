import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest'
import { renderWithProviders, screen, waitFor } from '@/test/test-utils'
import { mockEndUser, mockManagerUser } from '@/test/mocks/data'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import useOrganizationAccess from './useOrganizationAccess'

function AccessProbe() {
  const { status, isEndUser } = useOrganizationAccess()

  return <output data-testid="organization-access">{status}:{String(isEndUser)}</output>
}

const responseFor = (data: unknown) => ({ data: { code: 0, data } }) as never

describe('useOrganizationAccess', () => {
  beforeEach(() => {
    useAuthStore.getState().logout()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('bypasses organization lookup for system administrators', async () => {
    const getMyOrganizations = vi.spyOn(channelApi, 'getMyOrganizations')

    renderWithProviders(<AccessProbe />, {
      initialUser: { ...mockManagerUser, isSystemAdmin: true },
      initialToken: 'admin-token',
    })

    expect(screen.getByTestId('organization-access')).toHaveTextContent('allowed:false')
    expect(getMyOrganizations).not.toHaveBeenCalled()
  })

  it('keeps access in loading state until the membership query resolves', async () => {
    let resolveRequest: (value: unknown) => void = () => undefined
    vi.spyOn(channelApi, 'getMyOrganizations').mockReturnValue(
      new Promise((resolve) => {
        resolveRequest = resolve
      }) as never,
    )

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    expect(screen.getByTestId('organization-access')).toHaveTextContent('loading:false')

    resolveRequest(responseFor([{ roles: ['installer'] }]))
    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('allowed:false')
    })
  })

  it('allows a member when any membership has a non-customer role', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor([
        { roles: ['customer'] },
        { roles: ['customer', 'installer'] },
      ]),
    )

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('allowed:false')
    })
  })

  it('normalizes a single membership object and its legacy role field', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor({ role: 'org_admin' }),
    )

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('allowed:false')
    })
  })

  it('denies a pure customer membership and marks it as an end user', async () => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(
      responseFor([{ roles: ['customer'] }]),
    )

    renderWithProviders(<AccessProbe />, {
      initialUser: mockEndUser,
      initialToken: 'customer-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('denied:true')
    })
  })

  it.each([
    ['an empty organization list', []],
    ['a membership without role information', [{}]],
    ['a failed membership query', null],
  ])('denies access for %s', async (_reason, data) => {
    const request = vi.spyOn(channelApi, 'getMyOrganizations')
    if (data === null) {
      request.mockRejectedValue(new Error('network failure'))
    } else {
      request.mockResolvedValue(responseFor(data))
    }

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('denied:false')
    })
  })
})
