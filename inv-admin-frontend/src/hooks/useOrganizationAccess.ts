import { useQuery } from '@tanstack/react-query'
import useAuthStore from '@/stores/authStore'
import { channelApi } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'

export type OrganizationAccessStatus = 'loading' | 'allowed' | 'denied' | 'error'

export interface OrganizationAccess {
  status: OrganizationAccessStatus
  /** True only when all known membership roles are customer. */
  isEndUser: boolean
  /** Re-run the membership lookup; only meaningful for the `error` status. */
  refetch: () => void
}

export interface OrganizationMembership {
  roles?: unknown
  role?: unknown
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

/** Normalize the legacy single-object response and the current array response. */
export function normalizeOrganizationMemberships(data: unknown): OrganizationMembership[] {
  if (Array.isArray(data)) return data.filter(isRecord)
  if (isRecord(data)) return [data]
  return []
}

function extractResponseData(response: unknown): unknown {
  if (!isRecord(response)) return response
  const body = response.data
  if (isRecord(body) && Object.prototype.hasOwnProperty.call(body, 'data')) return body.data
  return body
}

function membershipRoles(membership: OrganizationMembership): string[] {
  if (Array.isArray(membership.roles)) {
    const roles = membership.roles.filter((role): role is string => typeof role === 'string' && role.trim().length > 0)
    if (roles.length > 0) return roles
  }

  return typeof membership.role === 'string' && membership.role.trim().length > 0
    ? [membership.role]
    : []
}

/**
 * Classify a successful membership response without relying on organization type.
 * A customer-only identity cannot manage organizations; every other known role can.
 */
export function classifyOrganizationMemberships(data: unknown): Pick<OrganizationAccess, 'status' | 'isEndUser'> {
  const memberships = normalizeOrganizationMemberships(data)
  if (memberships.length === 0) return { status: 'denied', isEndUser: false }

  const roles = memberships.flatMap(membershipRoles)
  if (roles.length === 0) return { status: 'denied', isEndUser: false }

  const isEndUser = roles.every((role) => role.trim().toLowerCase() === 'customer')
  return { status: isEndUser ? 'denied' : 'allowed', isEndUser }
}

/**
 * A 401/403 from this endpoint is the server saying the caller has no organization
 * context, which is a real verdict. Anything else (5xx, network, CORS) is a transport
 * failure and must not be reported to the user as "you have no permission".
 */
function isAuthorizationVerdict(error: unknown): boolean {
  const status = (error as { response?: { status?: unknown } } | null)?.response?.status
  return status === 401 || status === 403
}

export default function useOrganizationAccess(): OrganizationAccess {
  const user = useAuthStore((state) => state.user)
  const query = useQuery({
    queryKey: queryKeys.channels.myOrganizations(user?.id),
    queryFn: async () => {
      const response = await channelApi.getMyOrganizations()
      return extractResponseData(response)
    },
    enabled: Boolean(user) && !user?.isSystemAdmin,
    retry: false,
    staleTime: 60_000,
  })

  const refetch = () => {
    if (query.isError) void query.refetch()
  }

  if (!user) return { status: 'denied', isEndUser: false, refetch }
  if (user.isSystemAdmin) return { status: 'allowed', isEndUser: false, refetch }
  if (query.isPending) return { status: 'loading', isEndUser: false, refetch }
  if (query.isError) {
    return { status: isAuthorizationVerdict(query.error) ? 'denied' : 'error', isEndUser: false, refetch }
  }

  return { ...classifyOrganizationMemberships(query.data), refetch }
}
