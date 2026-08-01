import { useState, useMemo, useEffect, type ReactNode } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Button, Input, Space, Tag, Spin, Modal, Form, Select, Row, Col, App, Empty, Card, Tooltip,
} from 'antd'
import {
  PlusOutlined, EditOutlined, DeleteOutlined, SwapOutlined, ReloadOutlined,
  UserAddOutlined, TeamOutlined, DesktopOutlined, ApartmentOutlined,
  ShopOutlined, DeploymentUnitOutlined, ToolOutlined, HomeOutlined, BankOutlined,
  StopOutlined, CheckCircleOutlined, ExpandOutlined, CompressOutlined,
} from '@ant-design/icons'
import { channelApi, type OrgHierarchyNode } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'
import InviteDialog from './InviteDialog'
import InvitationList from './InvitationList'
import useAuthStore from '@/stores/authStore'

interface Props {
  selectedOrgId: number | null
  onSelectOrg: (id: number | null) => void
}

// Channel hierarchy: manufacturer -> agent -> distributor -> installer -> customer
const ORG_HIERARCHY: Record<string, string[]> = {
  manufacturer: ['agent'],
  agent: ['distributor'],
  distributor: ['installer'],
  installer: ['customer'],
}

const ALL_ORG_TYPES = ['agent', 'distributor', 'installer', 'customer']

// 类型 → 主色 / 渐变 / 图标（彩色卡片头部）
const TYPE_META: Record<string, { color: string; gradient: string; icon: ReactNode }> = {
  manufacturer: { color: '#1677ff', gradient: 'linear-gradient(135deg, #1677ff, #69b1ff)', icon: <BankOutlined /> },
  agent: { color: '#722ed1', gradient: 'linear-gradient(135deg, #722ed1, #b37feb)', icon: <ShopOutlined /> },
  distributor: { color: '#08979c', gradient: 'linear-gradient(135deg, #08979c, #5cdbd3)', icon: <DeploymentUnitOutlined /> },
  installer: { color: '#389e0d', gradient: 'linear-gradient(135deg, #389e0d, #95de64)', icon: <ToolOutlined /> },
  customer: { color: '#d46b08', gradient: 'linear-gradient(135deg, #fa8c16, #ffc069)', icon: <HomeOutlined /> },
}

// 纯 CSS 组织树连线（成熟 org chart 模式：层水平线 + 节点垂直短线）
const TREE_CSS = `
.org-tree-scope { text-align: center; padding: 8px 0 16px; }
.org-tree-scope .org-root { position: relative; display: inline-block; text-align: center; }
.org-tree-scope .org-children {
  position: relative; display: flex; justify-content: center; flex-wrap: wrap;
  padding-top: 30px;
}
.org-tree-scope .org-children::before {
  content: ''; position: absolute; top: 0; left: 50%; height: 30px;
  border-left: 2px solid #c8d2e0;
}
.org-tree-scope .org-child {
  position: relative; display: inline-block; text-align: center;
  padding: 30px 8px 0;
}
.org-tree-scope .org-child::before {
  content: ''; position: absolute; top: 0; left: 0; right: 0; height: 30px;
  border-top: 2px solid #c8d2e0;
}
.org-tree-scope .org-child::after {
  content: ''; position: absolute; top: 0; left: 50%; height: 30px;
  border-left: 2px solid #c8d2e0;
}
.org-tree-scope .org-child:first-child::before { left: 50%; }
.org-tree-scope .org-child:last-child::before { right: 50%; }
.org-tree-scope .org-child:only-child::before { display: none; }
`

const OrgCardTree: React.FC<Props> = ({ selectedOrgId, onSelectOrg }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()
  // 组织创建/删除等管理操作仅系统管理员可用（后端 Create 明确拒绝非管理员）
  const { user } = useAuthStore()
  const isSystemAdmin = !!user?.isSystemAdmin
  const [searchText, setSearchText] = useState('')
  const [expandedIds, setExpandedIds] = useState<Set<number>>(new Set())
  const [createOpen, setCreateOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [moveOpen, setMoveOpen] = useState(false)
  const [inviteOpen, setInviteOpen] = useState(false)
  const [inviteOrgId, setInviteOrgId] = useState<number | null>(null)
  const [editingOrg, setEditingOrg] = useState<OrgHierarchyNode | null>(null)
  const [movingOrg, setMovingOrg] = useState<OrgHierarchyNode | null>(null)
  const [createForm] = Form.useForm()
  const [editForm] = Form.useForm()
  const [moveForm] = Form.useForm()
  // Watch the parent field inside the create modal so type options react to it
  const watchedParentId = Form.useWatch('parent_id', createForm)

  // 树形数据源（后端已按可见范围剪枝）
  const { data: hierarchy, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.orgHierarchy(),
    queryFn: () => channelApi.getOrgHierarchy().then((r) => r.data?.data ?? []),
  })

  const roots = (hierarchy ?? []) as OrgHierarchyNode[]

  // 平铺可见组织，用于父级下拉
  const flatOrgs = useMemo(() => {
    const list: OrgHierarchyNode[] = []
    const walk = (nodes: OrgHierarchyNode[]) => {
      for (const n of nodes) {
        list.push(n)
        if (n.children?.length) walk(n.children)
      }
    }
    walk(roots)
    return list
  }, [roots])

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: queryKeys.channels.orgHierarchy() })
    queryClient.invalidateQueries({ queryKey: queryKeys.channels.organizations() })
  }

  // 默认展开第一层（根节点）
  useEffect(() => {
    if (roots.length > 0 && expandedIds.size === 0) {
      setExpandedIds(new Set(roots.map((r) => r.id)))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roots])

  // ── 搜索：保留匹配节点及其祖先链 ──
  const filteredRoots = useMemo(() => {
    if (!searchText.trim()) return roots
    const keyword = searchText.toLowerCase()
    const filterTree = (nodes: OrgHierarchyNode[]): OrgHierarchyNode[] => {
      const result: OrgHierarchyNode[] = []
      for (const node of nodes) {
        const children = node.children ? filterTree(node.children) : []
        const selfMatch =
          node.name.toLowerCase().includes(keyword) || node.type.toLowerCase().includes(keyword)
        if (selfMatch || children.length > 0) {
          result.push({ ...node, children: children.length > 0 ? children : node.children })
        }
      }
      return result
    }
    return filterTree(roots)
  }, [roots, searchText])

  // 搜索时自动展开全部匹配路径
  useEffect(() => {
    if (!searchText.trim()) return
    const all = new Set<number>()
    const collect = (nodes: OrgHierarchyNode[]) => {
      for (const n of nodes) {
        all.add(n.id)
        if (n.children?.length) collect(n.children)
      }
    }
    collect(filteredRoots)
    setExpandedIds(all)
  }, [searchText, filteredRoots])

  // ── Mutations ──
  const createMutation = useMutation({
    mutationFn: (values: any) => channelApi.createOrganization(values),
    onSuccess: () => { message.success(t('channel.org.createSuccess')); setCreateOpen(false); createForm.resetFields(); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, values }: { id: number; values: any }) => channelApi.updateOrganization(id, values),
    onSuccess: () => { message.success(t('channel.org.updateSuccess')); setEditOpen(false); setEditingOrg(null); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => channelApi.deleteOrganization(id),
    onSuccess: () => { message.success(t('channel.org.deleteSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const moveMutation = useMutation({
    mutationFn: ({ id, parentId }: { id: number; parentId: number | null }) => channelApi.moveOrganization(id, parentId),
    onSuccess: () => { message.success(t('channel.org.moveSuccess')); setMoveOpen(false); setMovingOrg(null); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const toggleMutation = useMutation({
    mutationFn: (id: number) => channelApi.toggleOrganization(id),
    onSuccess: () => { message.success(t('channel.org.toggleSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  // 基于有效父组织类型计算可创建的下级类型
  const getAllowedTypes = (): string[] => {
    const effectiveParentId = (watchedParentId ?? selectedOrgId) as number | null
    if (!effectiveParentId) return ALL_ORG_TYPES
    const parentOrg = flatOrgs.find((o) => o.id === effectiveParentId)
    if (!parentOrg) return ALL_ORG_TYPES
    return ORG_HIERARCHY[parentOrg.type] ?? []
  }

  // Reset the type field when it is no longer valid for the chosen parent
  useEffect(() => {
    if (!createOpen) return
    const current = createForm.getFieldValue('type') as string | undefined
    if (current && !getAllowedTypes().includes(current)) {
      createForm.setFieldValue('type', undefined)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [watchedParentId, createOpen])

  const toggleExpand = (id: number) => {
    setExpandedIds((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  const openCreate = (parentId: number | null = null) => {
    createForm.resetFields()
    if (parentId) createForm.setFieldsValue({ parent_id: parentId })
    setCreateOpen(true)
  }

  const openEdit = async (org: OrgHierarchyNode) => {
    setEditingOrg(org)
    editForm.setFieldsValue({ name: org.name, type: org.type })
    // hierarchy 节点不含 description，从详情接口补齐
    try {
      const res = await channelApi.getOrganization(org.id)
      const detail = res.data?.data as { description?: string } | undefined
      if (detail?.description) editForm.setFieldsValue({ description: detail.description })
    } catch {}
    setEditOpen(true)
  }

  const openMove = (org: OrgHierarchyNode) => {
    setMovingOrg(org)
    moveForm.setFieldsValue({ parent_id: org.parent_id })
    setMoveOpen(true)
  }

  const openInvite = (orgId: number) => {
    setInviteOrgId(orgId)
    setInviteOpen(true)
  }

  // ── 递归卡片渲染（彩色卡片 + CSS 连线） ──
  const renderCard = (node: OrgHierarchyNode, depth: number, withConnector: boolean) => {
    const expanded = expandedIds.has(node.id)
    const selected = selectedOrgId === node.id
    const children = node.children ?? []
    const meta = TYPE_META[node.type] ?? TYPE_META.customer
    const creatableChildTypes = ORG_HIERARCHY[node.type] ?? []

    return (
      <div className={withConnector ? 'org-child' : 'org-root'} key={node.id}>
        {/* 卡片本体 */}
        <div
          className="org-card"
          style={{
            width: 252,
            background: '#FFFFFF',
            borderRadius: 14,
            border: `1px solid ${selected ? meta.color : '#E3EAF3'}`,
            boxShadow: selected
              ? `0 0 0 2px ${meta.color}33, 0 10px 24px -8px ${meta.color}55`
              : '0 4px 14px -6px rgba(20,40,80,0.16)',
            textAlign: 'left',
            overflow: 'hidden',
            cursor: 'pointer',
            display: 'inline-block',
            verticalAlign: 'top',
            transition: 'box-shadow 0.2s, transform 0.2s',
          }}
          onClick={() => {
            onSelectOrg(node.id)
            if (children.length > 0) toggleExpand(node.id)
          }}
        >
          {/* 彩色渐变头部 */}
          <div style={{ background: meta.gradient, padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ color: '#FFFFFF', fontSize: 20, lineHeight: 1 }}>{meta.icon}</span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div
                title={node.name}
                style={{
                  color: '#FFFFFF', fontWeight: 600, fontSize: 15,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                }}
              >
                {node.name}
              </div>
              <div style={{ marginTop: 5, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                <span
                  style={{
                    background: 'rgba(255,255,255,0.22)', color: '#FFFFFF',
                    fontSize: 11, lineHeight: '18px', padding: '0 8px', borderRadius: 9,
                    border: '1px solid rgba(255,255,255,0.35)',
                  }}
                >
                  {t(`channel.org.type.${node.type}`)}
                </span>
                <span
                  style={{
                    background: node.status === 'active' ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.18)',
                    color: '#FFFFFF', fontSize: 11, lineHeight: '18px', padding: '0 8px', borderRadius: 9,
                    border: '1px solid rgba(255,255,255,0.35)',
                  }}
                >
                  {t(`channel.org.status.${node.status}`)}
                </span>
              </div>
            </div>
            {children.length > 0 && (
              <span style={{ color: 'rgba(255,255,255,0.9)', fontSize: 13, flexShrink: 0 }}>
                {expanded ? <CompressOutlined /> : <ExpandOutlined />}
              </span>
            )}
          </div>

          {/* 统计信息 */}
          <div style={{ display: 'flex', gap: 10, padding: '10px 14px 6px', flexWrap: 'wrap' }}>
            <Tooltip title={t('channel.org.memberCount')}>
              <span style={statChipStyle}><TeamOutlined /> {node.member_count}</span>
            </Tooltip>
            <Tooltip title={t('channel.org.deviceCount')}>
              <span style={statChipStyle}><DesktopOutlined /> {node.device_count}</span>
            </Tooltip>
            <Tooltip title={t('channel.org.childrenCount')}>
              <span style={statChipStyle}><ApartmentOutlined /> {node.children_count}</span>
            </Tooltip>
          </div>

          {/* 操作按钮 */}
          <div
            style={{ display: 'flex', gap: 2, padding: '2px 8px 10px', flexWrap: 'wrap' }}
            onClick={(e) => e.stopPropagation()}
          >
            <Tooltip title={t('channel.org.edit')}>
              <Button size="small" type="text" icon={<EditOutlined />} onClick={() => openEdit(node)} />
            </Tooltip>
            <Tooltip title={t('channel.org.move')}>
              <Button size="small" type="text" icon={<SwapOutlined />} onClick={() => openMove(node)} />
            </Tooltip>
            <Popconfirm
              title={t('channel.org.confirmToggle')}
              onConfirm={() => toggleMutation.mutate(node.id)}
            >
              <Tooltip title={node.status === 'active' ? t('channel.org.status.disabled') : t('channel.org.status.active')}>
                <Button
                  size="small"
                  type="text"
                  icon={node.status === 'active' ? <StopOutlined /> : <CheckCircleOutlined />}
                  style={node.status === 'active' ? { color: '#faad14' } : { color: '#52c41a' }}
                />
              </Tooltip>
            </Popconfirm>
            <Popconfirm
              title={t('channel.org.confirmDelete')}
              onConfirm={() => deleteMutation.mutate(node.id)}
            >
              <Button size="small" type="text" danger icon={<DeleteOutlined />} />
            </Popconfirm>
            {isSystemAdmin && creatableChildTypes.length > 0 && (
              <Tooltip title={t('channel.org.createChild')}>
                <Button
                  size="small"
                  type="text"
                  icon={<PlusOutlined />}
                  style={{ color: meta.color }}
                  onClick={() => openCreate(node.id)}
                />
              </Tooltip>
            )}
            <Tooltip title={t('channel.org.invite')}>
              <Button
                size="small"
                type="primary"
                ghost
                icon={<UserAddOutlined />}
                style={{ borderColor: meta.color, color: meta.color }}
                onClick={() => openInvite(node.id)}
              />
            </Tooltip>
          </div>
        </div>

        {/* 下级卡片层（CSS 连线） */}
        {expanded && children.length > 0 && (
          <div className="org-children">
            {children.map((child) => renderCard(child, depth + 1, true))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="org-tree-scope">
      <style>{TREE_CSS}</style>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16, textAlign: 'left' }}>
        <Col>
          <Space>
            {isSystemAdmin && (
              <Button type="primary" icon={<PlusOutlined />} onClick={() => openCreate(selectedOrgId)}>
                {t('channel.org.create')}
              </Button>
            )}
            <Input.Search
              placeholder={t('channel.org.search')}
              style={{ width: 240 }}
              allowClear
              onSearch={setSearchText}
              onChange={(e) => !e.target.value && setSearchText('')}
            />
          </Space>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Col>
      </Row>

      <Spin spinning={isLoading}>
        {filteredRoots.length === 0 ? (
          <Empty description={t('common.noData')} style={{ padding: 40 }} />
        ) : (
          <div>
            {filteredRoots.map((root) => renderCard(root, 0, false))}
            {!searchText.trim() && filteredRoots.length > 0 && (
              <div style={{ textAlign: 'center', color: '#999', fontSize: 12, marginTop: 12 }}>
                {t('channel.org.cardClickHint')}
              </div>
            )}
          </div>
        )}
      </Spin>

      {/* 邀请记录面板（当前可见范围） */}
      <Card
        size="small"
        variant="outlined"
        title={t('channel.invite.records')}
        extra={<span style={{ color: '#999', fontSize: 12 }}>{t('channel.invite.recordsHint')}</span>}
        style={{ borderRadius: 12, marginTop: 24, textAlign: 'left' }}
      >
        <InvitationList />
      </Card>

      {/* 邀请弹窗 */}
      <InviteDialog
        open={inviteOpen}
        initialOrgId={inviteOrgId}
        onClose={() => setInviteOpen(false)}
        onSent={invalidate}
      />

      {/* Create Modal */}
      <Modal
        title={t('channel.org.create')}
        open={createOpen}
        onOk={async () => { try { createMutation.mutate(await createForm.validateFields()) } catch {} }}
        onCancel={() => { setCreateOpen(false); createForm.resetFields() }}
        confirmLoading={createMutation.isPending}
        destroyOnHidden
        width={520}
      >
        <Form form={createForm} layout="vertical" preserve={false}>
          <Form.Item name="name" label={t('channel.org.name')} rules={[{ required: true }]}>
            <Input placeholder={t('channel.org.namePlaceholder')} />
          </Form.Item>
          <Form.Item name="type" label={t('channel.org.type')} rules={[{ required: true }]}>
            <Select
              options={getAllowedTypes().map((type) => ({ label: t(`channel.org.type.${type}`), value: type }))}
              placeholder={t('channel.org.typePlaceholder')}
            />
          </Form.Item>
          <Form.Item name="parent_id" label={t('channel.org.parent')}>
            <Select
              allowClear
              placeholder={t('channel.org.parentNone')}
              options={flatOrgs.map((o) => ({ label: `${o.name} (${t(`channel.org.type.${o.type}`)})`, value: o.id }))}
              onChange={() => createForm.setFieldValue('type', undefined)}
            />
          </Form.Item>
          <Form.Item name="code" label={t('channel.org.code')}>
            <Input placeholder={t('channel.org.codePlaceholder')} />
          </Form.Item>
          <Form.Item name="admin_email" label={t('channel.org.adminEmail')}>
            <Input placeholder={t('channel.org.adminEmailPlaceholder')} type="email" />
          </Form.Item>
        </Form>
      </Modal>

      {/* Edit Modal */}
      <Modal
        title={t('channel.org.edit')}
        open={editOpen}
        onOk={async () => {
          try {
            const values = await editForm.validateFields()
            updateMutation.mutate({ id: editingOrg!.id, values })
          } catch {}
        }}
        onCancel={() => { setEditOpen(false); setEditingOrg(null) }}
        confirmLoading={updateMutation.isPending}
        destroyOnHidden
      >
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="name" label={t('channel.org.name')} rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="type" label={t('channel.org.type')} rules={[{ required: true }]}>
            <Select options={ALL_ORG_TYPES.map((type) => ({ label: t(`channel.org.type.${type}`), value: type }))} disabled />
          </Form.Item>
          <Form.Item name="description" label={t('channel.org.description')}>
            <Input.TextArea rows={3} />
          </Form.Item>
        </Form>
      </Modal>

      {/* Move Modal */}
      <Modal
        title={t('channel.org.move')}
        open={moveOpen}
        onOk={async () => {
          try {
            const values = await moveForm.validateFields()
            moveMutation.mutate({ id: movingOrg!.id, parentId: values.parent_id ?? null })
          } catch {}
        }}
        onCancel={() => { setMoveOpen(false); setMovingOrg(null) }}
        confirmLoading={moveMutation.isPending}
        destroyOnHidden
      >
        <div style={{ marginBottom: 16 }}>
          <strong>{movingOrg?.name}</strong>
        </div>
        <Form form={moveForm} layout="vertical" preserve={false}>
          <Form.Item name="parent_id" label={t('channel.org.parent')}>
            <Select
              allowClear
              placeholder={t('channel.org.parentNone')}
              options={flatOrgs
                .filter((o) => o.id !== movingOrg?.id)
                .map((o) => ({ label: o.name, value: o.id }))}
            />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

// 统计信息小徽章样式
const statChipStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: 4,
  background: '#F5F7FB',
  borderRadius: 8,
  padding: '3px 8px',
  fontSize: 12,
  color: '#4A5A75',
}

export default OrgCardTree
