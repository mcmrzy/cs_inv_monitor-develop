import { useEffect, useMemo, useState, type CSSProperties, type ReactNode } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import {
  Modal, Input, InputNumber, Row, Col, App, TreeSelect, Tag, Space, Button, Switch, Tooltip, Radio, Select,
} from 'antd'
import {
  MailOutlined, ApartmentOutlined, BankOutlined, ShopOutlined,
  DeploymentUnitOutlined, ToolOutlined, HomeOutlined, CrownOutlined, QuestionCircleOutlined,
} from '@ant-design/icons'
import { channelApi, type OrgHierarchyNode, type InvitationAssignment } from '@/services/channelApi'
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

// ── 身份模型：成员身份 = 组织类型（manufacturer 组织等同 org_admin）──
// 组织内不再有可自由选择的"角色"；org_admin 仅作为可叠加的管理角色，
// 通过"设为组织管理员"开关追加。
const ORG_TYPE_IDENTITY: Record<string, string> = {
  manufacturer: 'org_admin',
  agent: 'agent',
  distributor: 'distributor',
  installer: 'installer',
  customer: 'customer',
}

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

interface MyOrg {
  id: number
  name: string
  type: string
  roles: string[]
}

const InviteDialog: React.FC<Props> = ({ open, initialOrgId, onClose, onSent }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { user } = useAuthStore()
  const isSystemAdmin = !!user?.isSystemAdmin

  const [emailInput, setEmailInput] = useState('')
  const [selectedOrganizationIds, setSelectedOrganizationIds] = useState<number[]>([])
  const [adminByOrg, setAdminByOrg] = useState<Record<number, boolean>>({})
  const [expiresHours, setExpiresHours] = useState<number>(72)
  // 邀请模式：existing = 邀请到已有组织；customer = 邀请终端用户（直接挂安装商组织）
  const [inviteMode, setInviteMode] = useState<'existing' | 'customer'>('existing')
  const [customerParentOrgId, setCustomerParentOrgId] = useState<number | null>(null)

  // 我的组织（真实角色码）：roles 含 org_admin 的组织 = 我可管理的组织
  const { data: myOrgs } = useQuery({
    queryKey: queryKeys.channels.myOrganizations(user?.id),
    queryFn: () => channelApi.getMyOrganizations().then((r) => {
      const d = r.data?.data
      return Array.isArray(d) ? d : []
    }),
    enabled: !isSystemAdmin && open,
  })

  const managedOrgIds = useMemo(() => {
    if (isSystemAdmin) return null // 系统管理员可管理全部组织
    if (!Array.isArray(myOrgs)) return new Set<number>()
    return new Set(
      (myOrgs as MyOrg[])
        .filter((o) => Array.isArray(o.roles) && o.roles.includes('org_admin'))
        .map((o) => o.id),
    )
  }, [isSystemAdmin, myOrgs])

  // 组织树：系统管理员全量；普通管理员剪枝为"自己 org_admin 的组织 + 全部下级"
  const { data: orgHierarchy, isLoading: loadingOrgs } = useQuery({
    queryKey: queryKeys.channels.orgHierarchy(),
    queryFn: () => channelApi.getOrgHierarchy().then((r) => {
      const d = r.data?.data
      return Array.isArray(d) ? d : []
    }),
    enabled: open,
  })

  const pruneToManaged = (nodes: OrgHierarchyNode[], managed: Set<number> | null): OrgHierarchyNode[] => {
    if (!managed) return nodes
    const result: OrgHierarchyNode[] = []
    for (const node of nodes) {
      if (managed.has(node.id)) {
        result.push(node) // 管理组织的整棵子树均可邀请
      } else {
        const children = pruneToManaged(node.children ?? [], managed)
        if (children.length > 0) result.push({ ...node, children })
      }
    }
    return result
  }

  const pickerTree = useMemo(
    () => pruneToManaged((orgHierarchy ?? []) as OrgHierarchyNode[], managedOrgIds),
    [orgHierarchy, managedOrgIds],
  )

  const flattenTree = (nodes: OrgHierarchyNode[]): { label: string; value: number; isLeaf: boolean }[] =>
    nodes.flatMap((node) => {
      if (node.id == null || !node.name || node.name.trim() === '') return []
      return [
        { label: node.name.trim(), value: node.id, isLeaf: node.children_count === 0 },
        ...flattenTree(node.children || []),
      ]
    })

  const orgOptions = flattenTree(pickerTree)

  // 客户模式可选归属安装商：管理范围内的 installer 组织（系统管理员为全量）
  const installerOptions = useMemo(() => {
    const list: { label: string; value: number }[] = []
    const walk = (nodes: OrgHierarchyNode[]) => {
      for (const n of nodes) {
        if (n.type === 'installer' && n.status === 'active') list.push({ label: n.name, value: n.id })
        if (n.children?.length) walk(n.children)
      }
    }
    walk(pickerTree)
    return list
  }, [pickerTree])

  // 组织 id → type 映射（仅用于展示类型色 / 图标 / 推导身份，只读）
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
      for (const o of myOrgs as MyOrg[]) {
        if (o.id != null) {
          const type = o.type
          if (type) map.set(o.id, type)
        }
      }
    }
    return map
  }, [orgHierarchy, myOrgs])

  const orgTypeOf = (orgId: number): string | undefined => orgTypeById.get(orgId)

  // 身份由组织类型自动推导
  const identityOf = (orgId: number): string | undefined => ORG_TYPE_IDENTITY[orgTypeOf(orgId) ?? '']

  // 该组织是否为管理范围（系统管理员全量；普通管理员剪枝后全部在管理范围内）
  const canManageOrg = (orgId: number): boolean => isSystemAdmin || (managedOrgIds?.has(orgId) ?? false)

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

  // 打开时预填初始组织（仅当该组织在管理范围内；myOrgs 加载完成后 managedOrgIds 稳定，本 effect 会再次执行并补填）
  useEffect(() => {
    if (!open) return
    setEmailInput('')
    setExpiresHours(72)
    setAdminByOrg({})
    setInviteMode('existing')
    setCustomerParentOrgId(null)
    if (initialOrgId && (isSystemAdmin || managedOrgIds?.has(initialOrgId))) {
      setSelectedOrganizationIds([initialOrgId])
    } else {
      setSelectedOrganizationIds([])
    }
  }, [open, initialOrgId, isSystemAdmin, managedOrgIds])

  // 客户模式预填：初始组织为 installer 时作为默认归属安装商（等树加载完成）
  useEffect(() => {
    if (!open || !initialOrgId || customerParentOrgId) return
    if (orgTypeOf(initialOrgId) === 'installer') setCustomerParentOrgId(initialOrgId)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initialOrgId, orgHierarchy])

  const sendMutation = useMutation({
    mutationFn: (data: {
      emails: string[]
      assignments?: InvitationAssignment[]
      customer_org?: { parent_org_id: number | null }
      expires_hours: number
    }) => channelApi.sendInvitation(data),
    onSuccess: (res) => {
      const data = res.data?.data
      // 后端异常时 results 可能缺失或非数组，降级为空数组避免 .filter/.map 崩溃
      const results = Array.isArray(data?.results) ? data.results : []
      const created = results.filter((r: any) => r.status === 'created')
      const failed = results.filter((r: any) => r.status !== 'created')

      // 结果提示统一使用同一 key：同 key 的新提示会替换旧提示，
      // 保证同一时刻只有一条 toast，避免“成功/失败”同时叠加弹出。
      const resultKey = 'invite-send-result'
      if (created.length > 0 && failed.length === 0) {
        message.success({ content: t('channel.invite.sendSuccess', { count: created.length }), key: resultKey })
      } else if (created.length > 0) {
        const detail = failed.map((r: any) => `${r.email}（${r.error || t('admin.operationFailed')}）`).join('、')
        message.warning({
          content: `${t('channel.invite.sendPartialSuccess', { count: created.length, failed: failed.length })}：${detail}`,
          key: resultKey,
          duration: 6,
        })
      } else {
        const detail = failed.map((r: any) => `${r.email}（${r.error || t('admin.operationFailed')}）`).join('、')
        message.error({ content: `${t('channel.invite.sendFailed')}：${detail}`, key: resultKey, duration: 6 })
      }

      // 复制首个邀请链接（原始 token 仅在创建时返回一次）。
      // 复制成功/失败均不再弹独立提示，避免与结果提示叠加
      //（HTTP 非安全上下文下 clipboard API 不可用，复制失败不代表发送失败）。
      const first = created.find((r: any) => r.invite_link)
      if (first?.invite_link) {
        const link = `${window.location.origin}${first.invite_link}`
        navigator.clipboard.writeText(link).catch(() => {})
      }

      setSelectedOrganizationIds([])
      setAdminByOrg({})
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

  const handleSelectOrgs = (values: number[]) => {
    setSelectedOrganizationIds(values)
    setAdminByOrg((prev) => {
      const next: Record<number, boolean> = {}
      for (const id of values) if (prev[id]) next[id] = true
      return next
    })
  }

  const validateAndSend = (): boolean => {
    // 防重复提交：请求进行中时拒绝再次发送
    if (sendMutation.isPending) return false
    if (!isSystemAdmin && (managedOrgIds?.size ?? 0) === 0) {
      message.warning(t('channel.invite.noManagePermission'))
      return false
    }
    const emails = parseEmails(emailInput)
    if (emails.length === 0) {
      message.error(t('channel.invite.emailRequired'))
      return false
    }

    // ── 客户模式：终端用户直接挂到指定安装商组织下（不创建新组织）──
    if (inviteMode === 'customer') {
      if (!customerParentOrgId) {
        message.error(t('channel.invite.parentRequired'))
        return false
      }
      const payload: {
        emails: string[]
        expires_hours: number
        customer_org: { parent_org_id: number | null }
      } = {
        emails,
        expires_hours: expiresHours,
        customer_org: { parent_org_id: customerParentOrgId },
      }
      sendMutation.mutate(payload)
      return true
    }

    if (selectedOrganizationIds.length === 0) {
      message.error(t('channel.invite.orgRequired'))
      return false
    }
    // 展开为：身份（=组织类型）+ 可选的 org_admin 叠加
    const assignments: InvitationAssignment[] = selectedOrganizationIds.flatMap((orgId) => {
      const identity = identityOf(orgId)
      if (!identity) return []
      const list: InvitationAssignment[] = [{ organization_id: orgId, role_code: identity }]
      if (adminByOrg[orgId] && identity !== 'org_admin') {
        list.push({ organization_id: orgId, role_code: 'org_admin' })
      }
      return list
    })
    if (assignments.length === 0) {
      message.error(t('channel.invite.identityMissing'))
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
        {/* ── 邀请模式：已有组织 / 自动创建客户组织 ── */}
        <div>
          <label style={LABEL_STYLE}>{t('channel.invite.mode')}</label>
          <Radio.Group
            value={inviteMode}
            onChange={(e) => setInviteMode(e.target.value)}
            options={[
              { label: t('channel.invite.modeExisting'), value: 'existing' },
              { label: t('channel.invite.modeCustomer'), value: 'customer' },
            ]}
            optionType="button"
            buttonStyle="solid"
          />
        </div>

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

        {/* ── 分组二：组织与成员身份 / 归属安装商信息 ── */}
        {inviteMode === 'customer' ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 3, height: 14, borderRadius: 2, background: '#d46b08' }} />
              <span style={{ fontSize: 13, fontWeight: 600, color: '#1f2d3d' }}>
                {t('channel.invite.customerOrgSection')}
              </span>
              <span style={{ fontSize: 12, color: '#8c9cb0' }}>{t('channel.invite.customerOrgSectionHint')}</span>
            </div>
            <Row gutter={16}>
              <Col span={24}>
                <div>
                  <label style={LABEL_STYLE}>
                    <HomeOutlined style={{ marginRight: 6, color: '#d46b08' }} />
                    {t('channel.invite.parentInstaller')}
                  </label>
                  <Select
                    showSearch
                    optionFilterProp="label"
                    placeholder={t('channel.invite.parentPlaceholder')}
                    options={installerOptions}
                    value={customerParentOrgId}
                    onChange={(v) => setCustomerParentOrgId(v ?? null)}
                    style={{ width: '100%' }}
                    status={!customerParentOrgId ? 'warning' : undefined}
                  />
                  <div style={HINT_STYLE}>{t('channel.invite.parentHint')}</div>
                </div>
              </Col>
            </Row>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 3, height: 14, borderRadius: 2, background: '#1677ff' }} />
            <span style={{ fontSize: 13, fontWeight: 600, color: '#1f2d3d' }}>
              {t('channel.invite.roleAssignments')}
            </span>
            <span style={{ fontSize: 12, color: '#8c9cb0' }}>{t('channel.invite.identityAuto')}</span>
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
              onChange={handleSelectOrgs}
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
                const identity = identityOf(orgId)
                const manageable = canManageOrg(orgId)
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
                      {/* 身份 = 组织类型，自动推导，不可手动选择 */}
                      <Tag
                        style={{
                          marginInlineEnd: 0,
                          borderColor: '#d9e6f5',
                          background: '#f0f6ff',
                          color: '#1677ff',
                          borderRadius: 6,
                          lineHeight: '18px',
                          paddingInline: 6,
                        }}
                      >
                        {t('channel.invite.identity')}：{identity ? roleLabel(identity, t) : '—'}
                      </Tag>
                    </div>

                    {identity && identity !== 'org_admin' && (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
                        <CrownOutlined style={{ color: '#d48806' }} />
                        <span style={{ fontSize: 13, color: '#1f2d3d' }}>
                          {t('channel.invite.setOrgAdmin')}
                        </span>
                        <Tooltip title={t('channel.invite.orgAdminHint')}>
                          <QuestionCircleOutlined style={{ color: '#8c9cb0', fontSize: 12 }} />
                        </Tooltip>
                        <Switch
                          size="small"
                          checked={!!adminByOrg[orgId]}
                          onChange={(checked) =>
                            setAdminByOrg((prev) => ({ ...prev, [orgId]: checked }))
                          }
                          disabled={!manageable}
                        />
                      </div>
                    )}

                    <Button size="small" danger onClick={() => {
                      setSelectedOrganizationIds((prev) => prev.filter((id) => id !== orgId))
                      setAdminByOrg((prev) => {
                        const next = { ...prev }
                        delete next[orgId]
                        return next
                      })
                    }} style={{ flexShrink: 0 }}>
                      {t('common.delete')}
                    </Button>
                  </div>
                )
              })}
            </Space>
          )}
        </div>
        )}
      </div>
    </Modal>
  )
}

export default InviteDialog
