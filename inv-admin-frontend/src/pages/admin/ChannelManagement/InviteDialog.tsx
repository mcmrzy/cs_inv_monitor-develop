import { useEffect, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import {
  Modal, Input, Select, InputNumber, Row, Col, App, TreeSelect, Tag, Space, Button,
} from 'antd'
import { channelApi, type OrgHierarchyNode } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { roleLabel } from '@/utils/roleLabel'

interface Props {
  open: boolean
  initialOrgId: number | null
  onClose: () => void
  onSent: () => void
}

// ── 可邀请角色：与后端 inviterAllowedRolesByOrgType 保持一致 ──
const ALLOWED_ROLES_BY_ORG_TYPE: Record<string, string[]> = {
  manufacturer: ['agent', 'distributor', 'installer', 'customer'],
  agent: ['installer', 'customer'],
  distributor: ['installer', 'customer'],
  installer: ['customer'],
  customer: [],
}

const ALL_ROLES = ['org_admin', 'agent', 'distributor', 'installer', 'customer']

// 多组织取并集；系统管理员豁免全量；org_admin 管理角色始终可分配
export function resolveAllowedRoles(orgTypes: string[], isSystemAdmin: boolean): string[] {
  if (isSystemAdmin) return [...ALL_ROLES]
  const set = new Set<string>(['org_admin'])
  for (const orgType of orgTypes) {
    for (const role of ALLOWED_ROLES_BY_ORG_TYPE[orgType] ?? []) set.add(role)
  }
  return [...set]
}

const InviteDialog: React.FC<Props> = ({ open, initialOrgId, onClose, onSent }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { user } = useAuthStore()
  const isSystemAdmin = !!user?.isSystemAdmin

  const [emailInput, setEmailInput] = useState('')
  const [selectedOrganizationIds, setSelectedOrganizationIds] = useState<number[]>([])
  const [roleAssignments, setRoleAssignments] = useState<{ organization_id: number; role_code: string }[]>([])
  const [expiresHours, setExpiresHours] = useState<number>(72)

  // 普通管理员：所属组织类型决定可邀请角色；系统管理员豁免全量
  const { data: myOrgs } = useQuery({
    queryKey: queryKeys.channels.myOrganizations(user?.id),
    queryFn: () => channelApi.getMyOrganizations().then((r) => r.data?.data ?? []),
    enabled: !isSystemAdmin && open,
  })

  const myOrgTypes: string[] = Array.isArray(myOrgs)
    ? [...new Set((myOrgs as any[]).map((o: any) => o.type ?? o.org_type).filter(Boolean))]
    : []

  const roleOptions = resolveAllowedRoles(myOrgTypes, isSystemAdmin)

  // 系统管理员：全量组织树；普通管理员：仅自己的组织（后端仅允许邀请自己所属组织）
  const { data: orgHierarchy, isLoading: loadingOrgs } = useQuery({
    queryKey: queryKeys.channels.orgHierarchy(),
    queryFn: () => channelApi.getOrgHierarchy().then((r) => r.data?.data ?? []),
    enabled: open,
  })

  const flattenTree = (nodes: OrgHierarchyNode[]): { label: string; value: number; isLeaf: boolean }[] =>
    nodes.flatMap((node) => {
      if (node.id == null || !node.name || node.name.trim() === '') return []
      return [
        { label: node.name.trim(), value: node.id, isLeaf: node.children_count === 0 },
        ...flattenTree(node.children || []),
      ]
    })

  const orgOptions = isSystemAdmin
    ? flattenTree((orgHierarchy ?? []) as OrgHierarchyNode[])
    : Array.isArray(myOrgs)
      ? (myOrgs as any[]).map((o: any) => ({ label: o.name, value: o.id, isLeaf: true }))
      : []

  // 打开时预填初始组织
  useEffect(() => {
    if (!open) return
    setEmailInput('')
    setExpiresHours(72)
    if (initialOrgId) {
      setSelectedOrganizationIds([initialOrgId])
      setRoleAssignments([{ organization_id: initialOrgId, role_code: 'customer' }])
    } else {
      setSelectedOrganizationIds([])
      setRoleAssignments([])
    }
  }, [open, initialOrgId])

  const sendMutation = useMutation({
    mutationFn: (data: {
      emails: string[]
      assignments: { organization_id: number; role_code: string }[]
      expires_hours: number
    }) => channelApi.sendInvitation(data),
    onSuccess: (res) => {
      const data = res.data?.data
      const results = data?.results ?? []
      const created = results.filter((r: any) => r.status === 'created')
      const failed = results.filter((r: any) => r.status !== 'created')

      if (created.length > 0) {
        message.success(
          failed.length > 0
            ? t('channel.invite.sendPartialSuccess', { count: created.length, failed: failed.length })
            : t('channel.invite.sendSuccess', { count: created.length }),
        )
      }
      failed.forEach((r: any) => message.warning(`${r.email}: ${r.error || t('admin.operationFailed')}`))

      // 复制首个邀请链接（原始 token 仅在创建时返回一次）
      const first = created.find((r: any) => r.invite_link)
      if (first?.invite_link) {
        const link = `${window.location.origin}${first.invite_link}`
        navigator.clipboard.writeText(link)
          .then(() => message.success(t('channel.invite.linkCopied')))
          .catch(() => message.warning(t('channel.invite.linkOnlyVisible')))
      } else if (created.length > 0) {
        message.warning(t('channel.invite.linkOnlyVisible'))
      }

      setSelectedOrganizationIds([])
      setRoleAssignments([])
      setEmailInput('')
      onSent()
      onClose()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const parseEmails = (text: string): string[] =>
    text
      .split(/\r?\n|,/)
      .map((e) => e.trim().toLowerCase())
      .filter((e) => e.length > 0 && /^[^\s@]+@[^\s@]+$/.test(e))

  const handleRoleChange = (orgId: number, roleCode: string) => {
    setRoleAssignments((prev) => {
      const existing = prev.findIndex((r) => r.organization_id === orgId)
      if (existing >= 0) {
        const updated = [...prev]
        updated[existing] = { organization_id: orgId, role_code: roleCode }
        return updated
      }
      return [...prev, { organization_id: orgId, role_code: roleCode }]
    })
  }

  const handleRemoveAssignment = (orgId: number) => {
    setRoleAssignments((prev) => prev.filter((r) => r.organization_id !== orgId))
    setSelectedOrganizationIds((prev) => prev.filter((id) => id !== orgId))
  }

  const validateAndSend = (): boolean => {
    if (roleOptions.length <= 1) {
      // 仅剩 org_admin（customer 组织）→ 无法发起渠道邀请
      message.warning(t('channel.invite.noPermission'))
      return false
    }
    const emails = parseEmails(emailInput)
    if (emails.length === 0) {
      message.error(t('channel.invite.emailRequired'))
      return false
    }
    if (selectedOrganizationIds.length === 0) {
      message.error(t('channel.invite.orgRequired'))
      return false
    }
    const hasRoleMissing = selectedOrganizationIds.some(
      (orgId) => !roleAssignments.find((r) => r.organization_id === orgId)?.role_code,
    )
    if (hasRoleMissing) {
      message.error(t('channel.invite.roleRequired'))
      return false
    }
    const assignments = selectedOrganizationIds
      .map((orgId) => ({
        organization_id: orgId,
        role_code: roleAssignments.find((r) => r.organization_id === orgId)?.role_code ?? '',
      }))
      .filter((a) => a.role_code !== '')
    if (assignments.length === 0) {
      message.error(t('channel.invite.roleRequired'))
      return false
    }
    sendMutation.mutate({ emails, assignments, expires_hours: expiresHours })
    return true
  }

  return (
    <Modal
      title={t('channel.invite.send')}
      open={open}
      onOk={validateAndSend}
      onCancel={onClose}
      confirmLoading={sendMutation.isPending}
      width={900}
      destroyOnHidden
    >
      <div style={{ minHeight: '55vh', display: 'flex', flexDirection: 'column', gap: '16px' }}>
        <Row gutter={16}>
          <Col span={16}>
            <div>
              <label style={{ display: 'block', marginBottom: 6, fontWeight: 500 }}>
                {t('channel.invite.email')}
              </label>
              <Input.TextArea
                rows={3}
                placeholder={t('channel.invite.emailPlaceholder')}
                value={emailInput}
                onChange={(e) => setEmailInput(e.target.value)}
              />
            </div>
          </Col>
          <Col span={8}>
            <div>
              <label style={{ display: 'block', marginBottom: 6, fontWeight: 500 }}>
                {t('channel.invite.expiryHours')}
              </label>
              <InputNumber
                min={1}
                max={720}
                value={expiresHours}
                onChange={(v) => setExpiresHours(v ?? 72)}
                style={{ width: '100%' }}
              />
            </div>
          </Col>
        </Row>

        <div>
          <label style={{ display: 'block', marginBottom: 6, fontWeight: 500 }}>
            {t('channel.invite.organization')}
          </label>
          <TreeSelect
            treeData={orgOptions}
            placeholder={t('channel.org.select')}
            multiple
            allowClear
            showSearch
            value={selectedOrganizationIds}
            onChange={(values: number[]) => {
              setSelectedOrganizationIds(values)
              setRoleAssignments((prev) => prev.filter((r) => values.includes(r.organization_id)))
            }}
            disabled={loadingOrgs}
            treeDefaultExpandAll={isSystemAdmin}
            style={{ width: '100%' }}
          />
        </div>

        {selectedOrganizationIds.length > 0 && (
          <div>
            <label style={{ display: 'block', marginBottom: 6, fontWeight: 500 }}>
              {t('channel.invite.roleAssignments')}
            </label>
            <Space direction="vertical" style={{ width: '100%' }}>
              {selectedOrganizationIds.map((orgId) => {
                const org = orgOptions.find((n) => n.value === orgId)
                return (
                  <Row key={orgId} align="middle" gutter={[8, 8]}>
                    <Col flex="auto">
                      <Tag color="blue">{org?.label}</Tag>
                    </Col>
                    <Col>
                      <Select
                        size="small"
                        options={roleOptions.map((code) => ({ label: roleLabel(code, t), value: code }))}
                        style={{ width: 160 }}
                        value={roleAssignments.find((r) => r.organization_id === orgId)?.role_code}
                        onChange={(val) => handleRoleChange(orgId, val)}
                        placeholder={t('channel.invite.selectRole')}
                      />
                    </Col>
                    <Col>
                      <Button size="small" danger onClick={() => handleRemoveAssignment(orgId)}>
                        {t('admin.remove')}
                      </Button>
                    </Col>
                  </Row>
                )
              })}
            </Space>
          </div>
        )}
      </div>
    </Modal>
  )
}

export default InviteDialog
