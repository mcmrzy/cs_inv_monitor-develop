import api from './api'

// ────────────────────── Types ──────────────────────

export interface Organization {
  id: number
  name: string
  parent_id: number | null
  type: string // manufacturer/agent/distributor/installer/customer
  status: string // active/disabled
  member_count: number
  code?: string
  description?: string
  created_at: string
  updated_at: string
  children?: Organization[]
}

export interface OrgMember {
  id: number
  user_id: number
  organization_id: number
  role: string
  status: string // active/inactive
  email: string
  phone?: string
  nickname?: string
  joined_at: string
}

export interface Invitation {
  id: number
  organization_id?: number | null
  organization?: string | null
  email: string
  role_id?: number
  role_name: string
  role_codes: string[]
  status: string // pending/accepted/rejected/expired/revoked
  token_hint: string
  expires_at: string
  created_at: string
  inviter_name: string
  created_by?: number
}

// Role assignment input for batch invitations (channel role model)
export interface InvitationAssignment {
  organization_id: number
  role_code: string // org_admin/agent/distributor/installer/customer
}

// Result per recipient email returned by the batch create endpoint
export interface InvitationCreateResult {
  email: string
  invitation_id?: number
  status: 'created' | 'duplicate' | 'failed'
  error?: string
  invite_link?: string
}

export interface TransferRequest {
  id: number
  resource_type: string // user/device
  resource_id: number
  from_org_id: number
  to_org_id: number
  from_org_name: string
  to_org_name: string
  requester_id: number
  requester_email: string
  reason: string
  status: string // pending/approved/rejected
  created_at: string
}

export interface OrgHierarchyNode {
  id: number
  parent_id: number | null
  name: string
  type: string
  code: string
  status: string
  member_count: number
  device_count: number
  children_count: number
  children?: OrgHierarchyNode[]
}

export interface OrgQuotaItem {
  resource_type: string // device/member/sub_org
  quota_limit: number
  used_count: number
  reserved_count: number
  inherited_from_organization_id?: number
}

// ────────────────────── API ──────────────────────

export const channelApi = {
  // ── Organizations ──
  getOrganizations: () =>
    api.get('/organizations', { expectedDataShape: 'array' }),

  getOrganization: (id: number) =>
    api.get(`/organizations/${id}`, { expectedDataShape: 'object' }),

  createOrganization: (data: { name: string; parent_id?: number | null; type: string; code?: string; admin_email?: string }) =>
    api.post('/organizations', data),

  updateOrganization: (id: number, data: { name?: string; type?: string; description?: string; status?: string }) =>
    api.put(`/organizations/${id}`, data),

  deleteOrganization: (id: number) =>
    api.delete(`/organizations/${id}`),

  moveOrganization: (id: number, parentId: number | null) =>
    api.post(`/organizations/${id}/move`, { parent_id: parentId }),

  toggleOrganization: (id: number) =>
    api.patch(`/organizations/${id}/status`),

  // ── Members ──
  getOrganizationMembers: (orgId: number, params?: any) =>
    api.get(`/organizations/${orgId}/members`, { params, expectedDataShape: 'page' }),

  addMember: (data: { organization_id: number; email: string; role: string }) =>
    api.post('/members/add', data),

  removeMember: (membershipId: number) =>
    api.delete(`/members/memberships/${membershipId}/remove`),

  updateMemberRole: (membershipId: number, role: string) =>
    api.put(`/members/memberships/${membershipId}/role`, { role }),

  reactivateMember: (membershipId: number) =>
    api.patch(`/members/memberships/${membershipId}/reactivate`),

  // ── Invitations ──
  getInvitations: (params?: any) =>
    api.get('/invitations/list', { params, expectedDataShape: 'page' }),

  // Batch create: emails[] x assignments[] with per-email result details.
  // Legacy single format {email, role_id, organization_id} is also accepted.
  // Customer-org mode: provide customer_org to auto-create a customer org
  // (assignments are ignored by the backend and forced to 'customer').
  sendInvitation: (data: {
    emails: string[]
    assignments?: InvitationAssignment[]
    customer_org?: {
      name?: string
      parent_org_id?: number | null // installer org; null/undefined = root manufacturer
    }
    expires_hours: number
  }) =>
    api.post('/invitations/create', data),

  revokeInvitation: (id: number) =>
    api.delete(`/invitations/${id}/revoke`),

  // The DB stores only the token digest; the full link is returned once at
  // creation time (see InvitationCreateResult.invite_link). This endpoint
  // returns guidance instead of the unrecoverable raw token.
  getInvitationLink: (id: number) =>
    api.get(`/invitations/${id}/copy-link`),

  // ── Transfers ──
  getTransferRequests: (params?: any) =>
    api.get('/members/transfers/list', { params, expectedDataShape: 'page' }),

  approveTransfer: (id: number) =>
    api.post('/members/transfer/accept', { transfer_id: id }),

  rejectTransfer: (id: number, reason?: string) =>
    api.post('/members/transfer/reject', { transfer_id: id, reason }),

  batchApproveTransfers: (ids: number[]) =>
    api.post('/members/transfers/batch-accept', { transfer_ids: ids }),

  batchRejectTransfers: (ids: number[], reason?: string) =>
    api.post('/members/transfers/batch-reject', { transfer_ids: ids, reason }),

  // ── Hierarchy / Quota / Join ──
  getOrgHierarchy: () =>
    api.get('/organizations/hierarchy', { expectedDataShape: 'array' }),

  getOrgQuota: (id: number) =>
    api.get(`/organizations/${id}/quota`, { expectedDataShape: 'array' }),

  setOrgQuota: (id: number, data: { quotas: { resource_type: string; quota_limit: number }[] }) =>
    api.put(`/organizations/${id}/quota`, data),

  joinOrganization: (id: number) =>
    api.post(`/organizations/${id}/join`),

  approveJoin: (id: number, data: { user_id: number; action: 'approve' | 'reject' }) =>
    api.post(`/organizations/${id}/approve-join`, data),

  getMyOrganizations: () =>
    api.get('/my/organizations', { expectedDataShape: 'array' }),
}
