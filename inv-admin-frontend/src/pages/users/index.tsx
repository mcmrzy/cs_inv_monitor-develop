import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Table, Button, Modal, Form, Input, Select, Tag, Space,
  Row, Col, Popconfirm, Typography, App, Empty,
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

const { Title } = Typography

const ROLE_TO_NUMERIC: Record<Role, number> = {
  [Role.SUPER_ADMIN]: 0, [Role.AGENT]: 1, [Role.INSTALLER]: 2, [Role.END_USER]: 3,
}
const ROLE_ORDER: Record<string, number> = {
  [Role.SUPER_ADMIN]: 0, [Role.AGENT]: 1, [Role.INSTALLER]: 2, [Role.END_USER]: 3,
}


function canManageUser(currentRole: Role | undefined, targetRole: Role): boolean {
  if (currentRole === undefined) return false
  if (currentRole === Role.SUPER_ADMIN) return true
  return (ROLE_ORDER[currentRole] ?? 99) < (ROLE_ORDER[targetRole] ?? 99)
}

function getAssignableRoles(currentRole: Role | undefined): Role[] {
  if (currentRole === undefined) return []
  switch (currentRole) {
    case Role.SUPER_ADMIN: return [Role.SUPER_ADMIN, Role.AGENT, Role.INSTALLER, Role.END_USER]
    case Role.AGENT: return [Role.INSTALLER, Role.END_USER]
    case Role.INSTALLER: return [Role.END_USER]
    default: return []
  }
}

const UsersPage: React.FC = () => {
  const { user: currentUser } = useAuthStore()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [keyword, setKeyword] = useState<string>()
  const [roleFilter, setRoleFilter] = useState<number>()
  const [statusFilter, setStatusFilter] = useState<number>()
  const [modalOpen, setModalOpen] = useState(false)
  const [editingUser, setEditingUser] = useState<User | null>(null)
  const [resetPwdOpen, setResetPwdOpen] = useState(false)
  const [resetUserId, setResetUserId] = useState<string>('')
  const [form] = Form.useForm()
  const [pwdForm] = Form.useForm()

  const STATUS_MAP: Record<number, { label: string; color: string }> = {
    1: { label: t('user.normal'), color: '#52c41a' },
    0: { label: t('user.disabled'), color: '#ff4d4f' },
    2: { label: t('user.locked'), color: '#fa8c16' },
  }

  const queryParams = { page, pageSize, keyword: keyword || undefined, role: roleFilter, status: statusFilter }

  const { data: listRes, isLoading, refetch } = useQuery({
    queryKey: queryKeys.users.list(queryParams),
    queryFn: () => userApi.list(queryParams).then((r) => {
      const d = (r.data?.data ?? r.data) as { items?: User[]; total?: number }
      return { items: d?.items ?? [], total: d?.total ?? 0 }
    }),
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
    { title: t('user.lastLogin'), dataIndex: 'last_login_at', key: 'last_login_at', width: 170, render: (val: string) => val ? dayjs(val).format('YYYY-MM-DD HH:mm:ss') : '-' },
    { title: t('user.registerTime'), dataIndex: 'created_at', key: 'created_at', width: 170, render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss') },
    {
      title: t('common.operation'), key: 'action', width: 220,
      render: (_: any, record: User) => {
        const canManage = canManageUser(currentUser?.role, record.role)
        const isSuperAdmin = currentUser?.role === Role.SUPER_ADMIN
        return (
          <Space>
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

  return (
    <div>
      <Title level={4} style={{ marginBottom: 16 }}>
        <TeamOutlined style={{ marginRight: 8 }} />{t('user.title')}
      </Title>
      <Card bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Input.Search allowClear placeholder={t('user.searchPlaceholder')} style={{ width: 240 }}
              value={keyword} onChange={(e) => setKeyword(e.target.value)} onSearch={() => { setPage(1); refetch() }} />
          </Col>
          <Col>
            <Select allowClear placeholder={t('user.filterRole')} style={{ width: 140 }}
              value={roleFilter} onChange={(val) => { setRoleFilter(val); setPage(1) }}
              options={[{ label: t('user.superAdmin'), value: 0 }, { label: t('user.agent'), value: 1 }, { label: t('user.installer'), value: 2 }, { label: t('user.endUser'), value: 3 }]} />
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

      <Table<User> rowKey="id" columns={columns} dataSource={data} loading={isLoading} size="small"
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
    </div>
  )
}

export default UsersPage
