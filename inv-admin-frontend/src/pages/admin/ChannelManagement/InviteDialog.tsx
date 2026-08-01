import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import {
  Modal, Input, Select, InputNumber, Row, Col, App, TreeSelect, Tag, Space, Button,
} from 'antd'
import {
  MailOutlined, ApartmentOutlined, BankOutlined, ShopOutlined,
  DeploymentUnitOutlined, ToolOutlined, HomeOutlined,
} from '@ant-design/icons'
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

// ── 组织类型 → 类型色 + 图标（与组织树卡片同配色，仅展示用）──
const ORG_TYPE_META: Record<string, { color: string; icon: ReactNode }> = {
  manufacturer: { color: '#1677ff', icon: <BankOutlined /> },
  agent: { color: '#722ed1', icon: <ShopOutlined /> },
  distributor: { color: '#08979c', icon: <DeploymentUnitOutlined /> },
  installer: { color: '#389e0d', icon: <ToolOutlined /> },
  customer: { color: '#d46b08', icon: <HomeOutlined /> },
}

const DEFAULT_ORG_COLOR = '#5c6b7a'

// ── 表单标签 / 说明文字统一样式 ──
const LABEL_STYLE: CSSProperties = {
  display: 'block',
  marginBottom: 6,
  fontSize: 14,
  fontWeight: 500,
  color: '#1f2d3d',
}

const HINT_STYLE: CSSProperties = {
  marginTop: 6,
  fontSize: 12,
  color: '#8c9cb0',
  lineHeight: '18px',
}

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

  // 组织 id → type 映射（仅用于展示类型色 / 图标，只读，不参与任何提交逻辑）
  const orgTypeById = useMemo(() => {
    const map = new Map<number, string>()
    const walk = (nodes: OrgHierarchyNode[]) => {
      for (const n of nodes) {
        if (n.id != null && n.type) map.set(n.id, n.type)
        if (n.children?.length) walk(n.children)
      }
    }
    walk((orgHierarchy ?? []) as OrgHierarchyNode[])
    if (Array.isArray(myOrgs)) {
      for (const o of myOrgs as any[]) {
        if (o.id != null) {
          const type = o.type ?? o.org_type
          if (type) map.set(o.id, type)
        }
      }
    }
    return map
  }, [orgHierarchy, myOrgs])

  const orgTypeOf = (orgId: number): string | undefined => orgTypeById.get(orgId)

  // TreeSelect 已选组织 → 带类型色圆点的 Tag
  const renderSelectedOrgTag = (props: any) => {
    const { label, closable, onClose } = props
    const color = ORG_TYPE_META[orgTypeOf(Number(props.value)) ?? '']?.color ?? DEFAULT_ORG_COLOR
    return (
      <Tag
        closable={closable}
        onClose={onClose}
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: 6,
          marginInlineEnd: 4,
          paddingInline: 8,
          borderRadius: 6,
          background: `${color}14`,
          borderColor: `${color}40`,
          color: '#1f2d3d',
        }}
      >
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: '50%',
            background: color,
            display: 'inline-block',
            flexShrink: 0,
          }}
        />
        {label}
      </Tag>
    )
  }

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
      <div style={{ minHeight: '55vh', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* ── 分组一：收件人信息（邀请邮箱 + 有效时长）── */}
        <Row gutter={16}>
          <Col span={16}>
            <div>
              <label style={LABEL_STYLE}>
                <MailOutlined style={{ marginRight: 6, color: '#1677ff' }} />
                {t('channel.invite.email')}
              </label>
              <Input.TextArea
                rows={3}
                placeholder={t('channel.invite.emailPlaceholder')}
                value={emailInput}
                onChange={(e) => setEmailInput(e.target.value)}
              />
              <div style={HINT_STYLE}>
                <MailOutlined style={{ marginRight: 4 }} />
                {t('channel.invite.emailPlaceholder')}
              </div>
            </div>
          </Col>
          <Col span={8}>
            <div>
              <label style={LABEL_STYLE}>{t('channel.invite.expiryHours')}</label>
              <InputNumber
                min={1}
                max={720}
                value={expiresHours}
                onChange={(v) => setExpiresHours(v ?? 72)}
                style={{ width: '100%' }}
                addonAfter={t('admin.hours')}
              />
              <div style={HINT_STYLE}>{`1 - 720 ${t('admin.hours')}`}</div>
            </div>
          </Col>
        </Row>

        {/* ── 分组分隔线 ── */}
        <div style={{ height: 1, background: '#eef2f7', margin: '2px 0' }} />

        {/* ── 分组二：组织与角色分配 ── */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 3, height: 14, borderRadius: 2, background: '#1677ff' }} />
            <span style={{ fontSize: 13, fontWeight: 600, color: '#1f2d3d' }}>
              {t('channel.invite.roleAssignments')}
            </span>
          </div>

          <div>
            <label style={LABEL_STYLE}>{t('channel.invite.organization')}</label>
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
              tagRender={renderSelectedOrgTag}
            />
          </div>

          {selectedOrganizationIds.length > 0 && (
            <Space direction="vertical" size={10} style={{ width: '100%' }}>
              {selectedOrganizationIds.map((orgId) => {
                const org = orgOptions.find((n) => n.value === orgId)
                const orgType = orgTypeOf(orgId)
                const meta = orgType ? ORG_TYPE_META[orgType] : undefined
                const color = meta?.color ?? DEFAULT_ORG_COLOR
                return (
                  <div
                    key={orgId}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 12,
                      background: '#F7F9FC',
                      border: '1px solid #eef2f7',
                      borderRadius: 10,
                      padding: '10px 12px',
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, minWidth: 0 }}>
                      <span
                        style={{
                          display: 'inline-flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          width: 22,
                          height: 22,
                          borderRadius: 6,
                          flexShrink: 0,
                          fontSize: 12,
                          background: `${color}14`,
                          color,
                        }}
                      >
                        {meta?.icon ?? <ApartmentOutlined />}
                      </span>
                      <span
                        style={{
                          fontWeight: 500,
                          color: '#1f2d3d',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {org?.label}
                      </span>
                      {orgType && meta && (
                        <Tag
                          style={{
                            marginInlineEnd: 0,
                            borderColor: `${color}40`,
                            background: `${color}14`,
                            color,
                            borderRadius: 6,
                            lineHeight: '18px',
                            paddingInline: 6,
                          }}
                        >
                          {t(`channel.org.type.${orgType}`)}
                        </Tag>
                      )}
                    </div>
                    <Select
                      size="small"
                      options={roleOptions.map((code) => ({ label: roleLabel(code, t), value: code }))}
                      style={{ width: 160, flexShrink: 0 }}
                      value={roleAssignments.find((r) => r.organization_id === orgId)?.role_code}
                      onChange={(val) => handleRoleChange(orgId, val)}
                      placeholder={t('channel.invite.selectRole')}
                    />
                    <Button size="small" danger onClick={() => handleRemoveAssignment(orgId)} style={{ flexShrink: 0 }}>
                      {t('common.delete')}
                    </Button>
                  </div>
                )
              })}
            </Space>
          )}
        </div>
      </div>
    </Modal>
  )
}

export default InviteDialog
