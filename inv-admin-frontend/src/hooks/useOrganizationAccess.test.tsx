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
  ])('denies access for %s', async (_reason, data) => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockResolvedValue(responseFor(data))

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('denied:false')
    })
  })

  it.each([
    ['a 401 response', 401],
    ['a 403 response', 403],
  ])('keeps a %s from the lookup as a real authorization verdict', async (_reason, status) => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockRejectedValue(
      Object.assign(new Error('rejected'), { response: { status } }),
    )

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('denied:false')
    })
  })

  it.each([
    ['a 500 response', Object.assign(new Error('boom'), { response: { status: 500 } })],
    ['a transport failure', new Error('network failure')],
  ])('reports %s as a lookup error instead of denying access', async (_reason, failure) => {
    vi.spyOn(channelApi, 'getMyOrganizations').mockRejectedValue(failure)

    renderWithProviders(<AccessProbe />, {
      initialUser: mockManagerUser,
      initialToken: 'member-token',
    })

    await waitFor(() => {
      expect(screen.getByTestId('organization-access')).toHaveTextContent('error:false')
    })
  })
})
