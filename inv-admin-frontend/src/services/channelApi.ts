import api from './api'

// ────────────────────── Types ──────────────────────

export interface Organization {
  id: number
  name: string
  parent_id: number | null
  type: string // manufacturer/distributor/dealer/installer/end_user
  status: string // active/disabled
  member_count: number
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
  organization_id: number
  email: string
  role_name: string
  status: string // pending/used/expired/revoked
  token_hint: string
  expires_at: string
  created_at: string
  created_by?: number
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

// ────────────────────── API ──────────────────────

export const channelApi = {
  // ── Organizations ──
  getOrganizations: () =>
    api.get('/organizations', { expectedDataShape: 'array' }),

  getOrganization: (id: number) =>
    api.get(`/organizations/${id}`, { expectedDataShape: 'object' }),

  createOrganization: (data: { name: string; parent_id?: number | null; type: string; description?: string }) =>
    api.post('/organizations', data),

  updateOrganization: (id: number, data: { name?: string; type?: string; description?: string; status?: string }) =>
    api.put(`/organizations/${id}`, data),

  deleteOrganization: (id: number) =>
    api.delete(`/organizations/${id}`),

  moveOrganization: (id: number, parentId: number | null) =>
    api.post(`/organizations/${id}/move`, { parent_id: parentId }),

  toggleOrganization: (id: number) =>
    api.post(`/organizations/${id}/toggle`),

  // ── Members ──
  getOrganizationMembers: (orgId: number, params?: any) =>
    api.get(`/organizations/${orgId}/members`, { params, expectedDataShape: 'page' }),

  addMember: (data: { organization_id: number; email: string; role: string }) =>
    api.post('/members/add', data),

  removeMember: (membershipId: number) =>
    api.delete(`/memberships/${membershipId}/remove`),

  updateMemberRole: (membershipId: number, role: string) =>
    api.put(`/memberships/${membershipId}/role`, { role }),

  reactivateMember: (membershipId: number) =>
    api.post(`/memberships/${membershipId}/reactivate`),

  // ── Invitations ──
  getInvitations: (params?: any) =>
    api.get('/invitations/list', { params, expectedDataShape: 'page' }),

  sendInvitation: (data: { organization_id: number; email: string; role_name: string; expires_in_hours?: number }) =>
    api.post('/invitations/create', data),

  revokeInvitation: (id: number) =>
    api.delete(`/invitations/${id}/revoke`),

  resendInvitation: (id: number) =>
    api.post(`/invitations/${id}/resend`),

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
}
