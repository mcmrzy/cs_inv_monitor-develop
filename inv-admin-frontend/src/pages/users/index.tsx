import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Modal, Form, Input, Select, Tag, Space,
  Row, Col, Popconfirm, Typography, App, Empty, Tabs, Drawer,
} from 'antd'
import {
  PlusOutlined, ReloadOutlined, EditOutlined, DeleteOutlined,
  LockOutlined, StopOutlined, CheckCircleOutlined, TeamOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { userApi } from '@/services/userApi'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import { Role } from '@/types'
import { ROLE_MAP, ROLE_COLORS } from '@/utils/constants'
import { queryKeys } from '@/utils/queryKeys'
import type { User } from '@/types'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { Title } = Typography

interface UserRecord {
  id: string
  phone: string
  nickname: string
  role: number
  status: number
  parent_id?: string | null
  created_at: string
}

const ROLE_TO_NUMERIC: Record<Role, number> = {
  [Role.SUPER_ADMIN]: 0,
  [Role.ADMIN]: 1,
  [Role.OPERATOR]: 2,
  [Role.DEALER]: 3,
  [Role.INSTALLER]: 4,
  [Role.END_USER]: 5,
}
const ROLE_ORDER: Record<string, number> = {
  [Role.SUPER_ADMIN]: 0,
  [Role.ADMIN]: 1,
  [Role.OPERATOR]: 2,
  [Role.DEALER]: 3,
  [Role.INSTALLER]: 4,
  [Role.END_USER]: 5,
}


function canManageUser(currentRole: Role | undefined, targetRole: Role): boolean {
  if (currentRole === undefined) return false
  if (currentRole === Role.SUPER_ADMIN) return true
  return (ROLE_ORDER[currentRole] ?? 99) < (ROLE_ORDER[targetRole] ?? 99)
}

function getAssignableRoles(currentRole: Role | undefined): Role[] {
  if (currentRole === undefined) return []
  switch (currentRole) {
    case Role.SUPER_ADMIN: return [Role.SUPER_ADMIN, Role.ADMIN, Role.OPERATOR, Role.DEALER, Role.INSTALLER, Role.END_USER]
    case Role.ADMIN: return [Role.OPERATOR, Role.DEALER, Role.INSTALLER, Role.END_USER]
    case Role.OPERATOR: return [Role.DEALER, Role.INSTALLER, Role.END_USER]
    case Role.DEALER: return [Role.INSTALLER, Role.END_USER]
    case Role.INSTALLER: return [Role.END_USER]
    default: return []
  }
}

const UsersPage: React.FC = () => {
  const { user: currentUser } = useAuthStore()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [keyword, setKeyword] = useState<string>()
  const [roleFilter, setRoleFilter] = useState<number>()
  const [statusFilter, setStatusFilter] = useState<number>()
  const [modalOpen, setModalOpen] = useState(false)
  const [editingUser, setEditingUser] = useState<User | null>(null)
  const [resetPwdOpen, setResetPwdOpen] = useState(false)
  const [resetUserId, setResetUserId] = useState<string>('')
  const [childrenDrawerOpen, setChildrenDrawerOpen] = useState(false)
  const [selectedUserId, setSelectedUserId] = useState<string>('')
  const [selectedUserName, setSelectedUserName] = useState<string>('')
  const [form] = Form.useForm()
  const [pwdForm] = Form.useForm()

  const STATUS_MAP: Record<number, { label: string; color: string }> = {
    1: { label: t('user.normal'), color: '#52c41a' },
    0: { label: t('user.disabled'), color: '#ff4d4f' },
    2: { label: t('user.locked'), color: '#fa8c16' },
  }

  const queryParams = { page, page_size: pageSize, keyword: keyword || undefined, role: roleFilter, status: statusFilter }

  const { data: listRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.users.list(queryParams),
    queryFn: () => userApi.list(queryParams).then((r) => {
      const d = (r.data?.data ?? r.data) as { items?: User[]; total?: number }
      return { items: d?.items ?? [], total: d?.total ?? 0 }
    }),
  })

  const { data: childrenRes } = useQuery({
    queryKey: ['users', 'children', selectedUserId],
    queryFn: () => userApi.getChildren(selectedUserId).then((r) => {
      const d = (r.data?.data ?? r.data) as { items?: User[]; total?: number }
      return { items: d?.items ?? [], total: d?.total ?? 0 }
    }),
    enabled: childrenDrawerOpen && !!selectedUserId,
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.users.all })

  const createMutation = useMutation({
    mutationFn: (data: any) => userApi.create(data),
    onSuccess: () => { message.success(t('user.createSuccess')); setModalOpen(false); form.resetFields(); invalidate() },
    onError: () => { message.error(t('user.createFailed')) },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: string; data: any }) => userApi.update(id, data),
    onSuccess: () => { message.success(t('user.updateSuccess')); setModalOpen(false); form.resetFields(); invalidate() },
    onError: () => { message.error(t('user.updateFailed')) },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => userApi.delete(id),
    onSuccess: () => { message.success(t('user.deleteSuccess')); invalidate() },
    onError: () => { message.error(t('user.deleteFailed')) },
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, status }: { id: string; status: number }) => userApi.toggleStatus(id, status),
    onSuccess: (_, vars) => { message.success(t('user.statusChanged')); invalidate() },
    onError: () => { message.error(t('user.statusChangeFailed')) },
  })

  const resetPwdMutation = useMutation({
    mutationFn: ({ id, password }: { id: string; password: string }) => userApi.resetPassword(Number(id), { password }),
    onSuccess: () => { message.success(t('user.resetPwdSuccess')); setResetPwdOpen(false); pwdForm.resetFields() },
    onError: () => { message.error(t('user.resetPwdFailed')) },
  })

  const assignableRoles = getAssignableRoles(currentUser?.role)

  // 获取可选的上级用户列表（角色等级高于当前创建的用户）
  const { data: parentUsers } = useQuery({
    queryKey: ['users', 'parents', currentUser?.id],
    queryFn: () => userApi.list({ page_size: 100, status: 1 }).then((r) => {
      const d = (r.data?.data ?? r.data) as { items?: User[]; total?: number }
      const items = d?.items ?? []
      // 过滤出角色等级高于当前用户的用户（排除自己）
      return items.filter((u: User) => u.id !== currentUser?.id && (ROLE_ORDER[u.role] ?? 99) < (ROLE_ORDER[currentUser?.role ?? ''] ?? 99))
    }),
    enabled: modalOpen,
  })

  const openAdd = () => { setEditingUser(null); form.resetFields(); setModalOpen(true) }
  const openEdit = (record: User) => {
    setEditingUser(record)
    form.setFieldsValue({ phone: record.phone, email: record.email, nickname: record.nickname, role: record.role })
    setModalOpen(true)
  }

  const handleSave = async () => {
    try {
      const values = await form.validateFields()
      if (editingUser) {
        updateMutation.mutate({ id: editingUser.id, data: { phone: values.phone, email: values.email, nickname: values.nickname, role: values.role } })
      } else {
        if (!values.password) { message.warning(t('user.pleaseInputPassword')); return }
        createMutation.mutate(values)
      }
    } catch { /* validation failed */ }
  }

  const handleResetPwd = async () => {
    try {
      const values = await pwdForm.validateFields()
      resetPwdMutation.mutate({ id: resetUserId, password: values.password })
    } catch { /* validation failed */ }
  }

  const columns: ColumnsType<User> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 80, ellipsis: true },
    { title: t('user.phone'), dataIndex: 'phone', key: 'phone', width: 130 },
    { title: t('user.email'), dataIndex: 'email', key: 'email', width: 180, ellipsis: true },
    { title: t('user.nickname'), dataIndex: 'nickname', key: 'nickname', width: 120 },
    {
      title: t('user.role'), dataIndex: 'role', key: 'role', width: 110,
      render: (role: any) => {
        const key = typeof role === 'number' ? String(role) : role
        return <Tag color={ROLE_COLORS[key] || '#d9d9d9'}>{ROLE_MAP[key] || key}</Tag>
      },
    },
    {
      title: t('user.status'), dataIndex: 'status', key: 'status', width: 90,
      render: (status: number) => {
        const cfg = STATUS_MAP[status] || { label: String(status), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    { title: t('user.lastLogin'), dataIndex: 'last_login_at', key: 'last_login_at', width: 170, render: (val: string) => val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') : '-' },
    { title: t('user.registerTime'), dataIndex: 'created_at', key: 'created_at', width: 170, render: (val: string) => formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') },
    {
      title: t('common.operation'), key: 'action', width: 280,
      render: (_: any, record: User) => {
        const canManage = canManageUser(currentUser?.role, record.role)
        const isSuperAdmin = currentUser?.role === Role.SUPER_ADMIN
        const canViewChildren = record.role !== Role.END_USER && canManage
        return (
          <Space>
            {canViewChildren && <Button type="link" size="small" onClick={() => { setSelectedUserId(record.id); setSelectedUserName(record.nickname || record.phone); setChildrenDrawerOpen(true) }}>{t('user.children')}</Button>}
            {canManage && <Button type="link" size="small" icon={<EditOutlined />} onClick={() => openEdit(record)}>{t('user.edit')}</Button>}
            {canManage && (
              <Popconfirm title={record.status === 1 ? t('user.confirmDisable') : t('user.confirmEnable')} onConfirm={() => toggleMutation.mutate({ id: record.id, status: record.status === 1 ? 0 : 1 })}>
                <Button type="link" size="small" icon={record.status === 1 ? <StopOutlined /> : <CheckCircleOutlined />}>{record.status === 1 ? t('user.disable') : t('user.enable')}</Button>
              </Popconfirm>
            )}
            {canManage && <Button type="link" size="small" icon={<LockOutlined />} onClick={() => { setResetUserId(record.id); pwdForm.resetFields(); setResetPwdOpen(true) }}>{t('user.resetPassword')}</Button>}
            {isSuperAdmin && (
              <Popconfirm title={t('user.confirmDelete')} onConfirm={() => deleteMutation.mutate(record.id)}>
                <Button type="link" size="small" danger icon={<DeleteOutlined />} />
              </Popconfirm>
            )}
          </Space>
        )
      },
    },
  ]

  const data = listRes?.items ?? []
  const total = listRes?.total ?? 0

  const roleTabs = [
    { key: 'all', label: t('user.allUsers') },
    { key: '0', label: t('user.superAdmin') },
    { key: '1', label: t('user.admin') },
    { key: '2', label: t('user.operator') },
    { key: '3', label: t('user.dealer') },
    { key: '4', label: t('user.installer') },
    { key: '5', label: t('user.endUser') },
  ]

  const handleTabChange = (key: string) => {
    if (key === 'all') {
      setRoleFilter(undefined)
    } else {
      setRoleFilter(Number(key))
    }
    setPage(1)
  }

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <TeamOutlined style={{ marginRight: 8 }} />{t('user.title')}
      </Title>
      <Tabs activeKey={roleFilter !== undefined ? String(roleFilter) : 'all'} onChange={handleTabChange} items={roleTabs} style={{ marginBottom: 16 }} />
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Input.Search allowClear placeholder={t('user.searchPlaceholder')} style={{ width: 240 }}
              value={keyword} onChange={(e) => setKeyword(e.target.value)} onSearch={() => { setPage(1); refetch() }} />
          </Col>
          <Col>
            <Select allowClear placeholder={t('user.filterRole')} style={{ width: 140 }}
              value={roleFilter} onChange={(val) => { setRoleFilter(val); setPage(1) }}
              options={[
                { label: t('user.superAdmin'), value: Role.SUPER_ADMIN },
                { label: t('user.admin'), value: Role.ADMIN },
                { label: t('user.operator'), value: Role.OPERATOR },
                { label: t('user.dealer'), value: Role.DEALER },
                { label: t('user.installer'), value: Role.INSTALLER },
                { label: t('user.endUser'), value: Role.END_USER },
              ]} />
          </Col>
          <Col>
            <Select allowClear placeholder={t('user.filterStatus')} style={{ width: 120 }}
              value={statusFilter} onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={Object.entries(STATUS_MAP).map(([k, v]) => ({ label: v.label, value: Number(k) }))} />
          </Col>
          <Col><Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button></Col>
          {assignableRoles.length > 0 && (
            <Col><Button type="primary" icon={<PlusOutlined />} onClick={openAdd}>{t('user.addUser')}</Button></Col>
          )}
        </Row>
      </Card>

      <Table<User> rowKey="id" columns={columns} dataSource={data} loading={isLoading} size="middle"
          locale={{ emptyText: <Empty description={t('common.noData')} /> }}
        pagination={{ current: page, pageSize, total, showSizeChanger: true, showTotal: (totalCount) => t('common.total', { total: totalCount }), onChange: (p, ps) => { setPage(p); setPageSize(ps) } }} />

      <Modal title={editingUser ? t('user.editUser') : t('user.addUserTitle')} open={modalOpen}
        onCancel={() => { setModalOpen(false); form.resetFields() }} onOk={handleSave}
        confirmLoading={createMutation.isPending || updateMutation.isPending} destroyOnClose>
        <Form form={form} layout="vertical">
          <Form.Item name="phone" label={t('user.phone')} rules={[{ required: true, message: t('common.pleaseInput') + t('user.phone') }]}><Input placeholder={t('common.pleaseInput') + t('user.phone')} /></Form.Item>
          <Form.Item name="email" label={t('user.email')} rules={[{ required: true, message: t('common.pleaseInput') + t('user.email') }, { type: 'email', message: t('user.emailFormatError') }]}><Input placeholder={t('common.pleaseInput') + t('user.email')} /></Form.Item>
          <Form.Item name="nickname" label={t('user.nickname')} rules={[{ required: true, message: t('common.pleaseInput') + t('user.nickname') }]}><Input placeholder={t('common.pleaseInput') + t('user.nickname')} /></Form.Item>
          <Form.Item name="role" label={t('user.role')} rules={[{ required: true, message: t('common.pleaseSelect') + t('user.role') }]}>
            <Select placeholder={t('common.pleaseSelect') + t('user.role')} options={assignableRoles.map((r) => ({ label: ROLE_MAP[ROLE_TO_NUMERIC[r]], value: ROLE_TO_NUMERIC[r] }))} />
          </Form.Item>
          {!editingUser && parentUsers && parentUsers.length > 0 && (
            <Form.Item name="parentId" label={t('user.parentUser')}>
              <Select
                allowClear
                placeholder={t('user.selectParent')}
                options={parentUsers.map((u) => ({
                  label: `${u.nickname || u.phone} (${ROLE_MAP[String(u.role)] || u.role})`,
                  value: u.id,
                }))}
              />
            </Form.Item>
          )}
          {!editingUser && (
            <Form.Item name="password" label={t('user.newPassword')} rules={[{ required: true, message: t('user.pleaseInputPassword') }, { min: 6, message: t('user.pwdMinLength') }]}>
              <Input.Password placeholder={t('user.pleaseInputPassword')} />
            </Form.Item>
          )}
        </Form>
      </Modal>

      <Modal title={t('user.resetPasswordTitle')} open={resetPwdOpen}
        onCancel={() => { setResetPwdOpen(false); pwdForm.resetFields() }} onOk={handleResetPwd}
        confirmLoading={resetPwdMutation.isPending} destroyOnClose>
        <Form form={pwdForm} layout="vertical">
          <Form.Item name="password" label={t('user.newPassword')} rules={[{ required: true, message: t('user.pleaseInputPassword') }, { min: 6, message: t('user.pwdMinLength') }]}>
            <Input.Password placeholder={t('user.pleaseInputPassword')} />
          </Form.Item>
          <Form.Item name="confirmPassword" label={t('user.confirmPassword')} dependencies={['password']}
            rules={[{ required: true, message: t('common.pleaseInput') + t('user.confirmPassword') }, ({ getFieldValue }) => ({
              validator(_, value) { if (!value || getFieldValue('password') === value) return Promise.resolve(); return Promise.reject(new Error(t('user.pwdMismatch'))) },
            })]}>
            <Input.Password placeholder={t('common.pleaseInput') + t('user.confirmPassword')} />
          </Form.Item>
        </Form>
      </Modal>

      <Drawer
        title={`${selectedUserName} - ${t('user.children')}`}
        open={childrenDrawerOpen}
        onClose={() => { setChildrenDrawerOpen(false); setSelectedUserId(''); setSelectedUserName('') }}
        width={600}
        destroyOnClose
      >
        {childrenRes?.items && childrenRes.items.length > 0 ? (
          <Table<User>
            rowKey="id"
            dataSource={childrenRes.items}
            size="small"
            pagination={false}
            columns={[
              { title: 'ID', dataIndex: 'id', key: 'id', width: 80 },
              { title: t('user.phone'), dataIndex: 'phone', key: 'phone', width: 130 },
              { title: t('user.nickname'), dataIndex: 'nickname', key: 'nickname', width: 120 },
              {
                title: t('user.role'), dataIndex: 'role', key: 'role', width: 110,
                render: (role: any) => {
                  const key = typeof role === 'number' ? String(role) : role
                  return <Tag color={ROLE_COLORS[key] || '#d9d9d9'}>{ROLE_MAP[key] || key}</Tag>
                },
              },
              {
                title: t('user.status'), dataIndex: 'status', key: 'status', width: 90,
                render: (status: number) => {
                  const cfg = STATUS_MAP[status] || { label: String(status), color: '#d9d9d9' }
                  return <Tag color={cfg.color}>{cfg.label}</Tag>
                },
              },
              { title: t('common.createdAt'), dataIndex: 'created_at', key: 'created_at', width: 170, render: (val: string) => formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') },
            ]}
          />
        ) : (
          <Empty description={t('user.noChildren')} />
        )}
      </Drawer>
    </div>
  )
}

export default UsersPage
