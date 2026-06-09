import React, { useState, useEffect, useCallback } from 'react'
import {
  Card,
  Table,
  Button,
  Modal,
  Form,
  Input,
  Select,
  Tag,
  Space,
  Row,
  Col,
  Popconfirm,
  message,
} from 'antd'
import {
  PlusOutlined,
  ReloadOutlined,
  EditOutlined,
  DeleteOutlined,
  LockOutlined,
  StopOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { userApi } from '@/services/userApi'
import useAuthStore from '@/stores/authStore'
import { Role } from '@/types'
import { ROLE_MAP, ROLE_COLORS } from '@/utils/constants'
import type { User } from '@/types'

const ROLE_TO_NUMERIC: Record<Role, number> = {
  [Role.SUPER_ADMIN]: 0,
  [Role.AGENT]: 1,
  [Role.INSTALLER]: 2,
  [Role.END_USER]: 3,
}

const NUMERIC_TO_ROLE: Record<number, Role> = {
  0: Role.SUPER_ADMIN,
  1: Role.AGENT,
  2: Role.INSTALLER,
  3: Role.END_USER,
}

const ROLE_ORDER: Record<string, number> = {
  [Role.SUPER_ADMIN]: 0,
  [Role.AGENT]: 1,
  [Role.INSTALLER]: 2,
  [Role.END_USER]: 3,
}

const STATUS_MAP: Record<number, { label: string; color: string }> = {
  1: { label: '正常', color: '#52c41a' },
  0: { label: '已禁用', color: '#ff4d4f' },
  2: { label: '已锁定', color: '#fa8c16' },
}

function canManageUser(currentRole: Role | undefined, targetRole: Role): boolean {
  if (currentRole === undefined) return false
  if (currentRole === Role.SUPER_ADMIN) return true
  const currentLevel = ROLE_ORDER[currentRole] ?? 99
  const targetLevel = ROLE_ORDER[targetRole] ?? 99
  return currentLevel < targetLevel
}

function getAssignableRoles(currentRole: Role | undefined): Role[] {
  if (currentRole === undefined) return []
  switch (currentRole) {
    case Role.SUPER_ADMIN:
      return [Role.SUPER_ADMIN, Role.AGENT, Role.INSTALLER, Role.END_USER]
    case Role.AGENT:
      return [Role.INSTALLER, Role.END_USER]
    case Role.INSTALLER:
      return [Role.END_USER]
    default:
      return []
  }
}

interface UserFormValues {
  phone: string
  email: string
  password?: string
  nickname: string
  role: Role
}

const UsersPage: React.FC = () => {
  const { user: currentUser } = useAuthStore()
  const [loading, setLoading] = useState(false)
  const [data, setData] = useState<User[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(10)
  const [keyword, setKeyword] = useState<string>()
  const [roleFilter, setRoleFilter] = useState<number>()
  const [statusFilter, setStatusFilter] = useState<number>()
  const [modalOpen, setModalOpen] = useState(false)
  const [modalSaving, setModalSaving] = useState(false)
  const [editingUser, setEditingUser] = useState<User | null>(null)
  const [resetPwdOpen, setResetPwdOpen] = useState(false)
  const [resetPwdSaving, setResetPwdSaving] = useState(false)
  const [resetUserId, setResetUserId] = useState<string>('')
  const [form] = Form.useForm<UserFormValues>()
  const [pwdForm] = Form.useForm()

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const res = await userApi.list({
        page,
        pageSize,
        keyword: keyword || undefined,
        role: roleFilter !== undefined ? roleFilter : undefined,
        status: statusFilter !== undefined ? statusFilter : undefined,
      })
      const responseData = res.data as Record<string, unknown>
      const d = (responseData?.data ?? responseData) as { items?: User[], total?: number }
      setData(d?.items ?? [])
      setTotal(d?.total ?? 0)
    } catch {
      message.error('获取用户列表失败')
    } finally {
      setLoading(false)
    }
  }, [page, pageSize, keyword, roleFilter, statusFilter])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const assignableRoles = getAssignableRoles(currentUser?.role)

  const openAdd = () => {
    setEditingUser(null)
    form.resetFields()
    setModalOpen(true)
  }

  const openEdit = (record: User) => {
    setEditingUser(record)
    form.setFieldsValue({
      phone: record.phone,
      email: record.email,
      nickname: record.nickname,
      role: record.role,
    })
    setModalOpen(true)
  }

  const handleSave = async () => {
    try {
      const values = await form.validateFields()
      setModalSaving(true)

      if (editingUser) {
        await userApi.update(editingUser.id, {
          phone: values.phone,
          email: values.email,
          nickname: values.nickname,
          role: values.role,
        })
        message.success('用户更新成功')
      } else {
        if (!values.password) {
          message.warning('请输入密码')
          setModalSaving(false)
          return
        }
        await userApi.create({
          phone: values.phone,
          email: values.email,
          password: values.password,
          nickname: values.nickname,
          role: values.role,
        })
        message.success('用户创建成功')
      }

      setModalOpen(false)
      form.resetFields()
      fetchData()
    } catch {
      message.error(editingUser ? '更新失败' : '创建失败')
    } finally {
      setModalSaving(false)
    }
  }

  const handleDelete = async (id: string) => {
    try {
      await userApi.delete(id)
      message.success('删除成功')
      fetchData()
    } catch {
      message.error('删除失败')
    }
  }

  const handleToggleStatus = async (record: User) => {
    try {
      const newStatus = record.status === 1 ? 0 : 1
      await userApi.toggleStatus(record.id, newStatus)
      message.success(newStatus === 1 ? '已启用' : '已禁用')
      fetchData()
    } catch {
      message.error('操作失败')
    }
  }

  const openResetPwd = (id: string) => {
    setResetUserId(id)
    pwdForm.resetFields()
    setResetPwdOpen(true)
  }

  const handleResetPwd = async () => {
    try {
      const values = await pwdForm.validateFields()
      setResetPwdSaving(true)
      await userApi.resetPassword(Number(resetUserId), { password: values.password })
      message.success('密码重置成功')
      setResetPwdOpen(false)
    } catch {
      message.error('密码重置失败')
    } finally {
      setResetPwdSaving(false)
    }
  }

  const columns: ColumnsType<User> = [
    { title: 'ID', dataIndex: 'id', key: 'id', width: 80, ellipsis: true },
    { title: '手机号', dataIndex: 'phone', key: 'phone', width: 130 },
    { title: '邮箱', dataIndex: 'email', key: 'email', width: 180, ellipsis: true },
    { title: '昵称', dataIndex: 'nickname', key: 'nickname', width: 120 },
    {
      title: '角色',
      dataIndex: 'role',
      key: 'role',
      width: 110,
      render: (role: any) => {
        const key = typeof role === 'number' ? String(role) : role
        return (
          <Tag color={ROLE_COLORS[key] || '#d9d9d9'}>{ROLE_MAP[key] || key}</Tag>
        )
      },
    },
    {
      title: '状态',
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (status: number) => {
        const cfg = STATUS_MAP[status] || { label: String(status), color: '#d9d9d9' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: '最后登录',
      dataIndex: 'last_login_at',
      key: 'last_login_at',
      width: 170,
      render: (val: string) => val ? dayjs(val).format('YYYY-MM-DD HH:mm:ss') : '-',
    },
    {
      title: '注册时间',
      dataIndex: 'created_at',
      key: 'created_at',
      width: 170,
      render: (val: string) => dayjs(val).format('YYYY-MM-DD HH:mm:ss'),
    },
    {
      title: '操作',
      key: 'action',
      width: 220,
      render: (_: any, record: User) => {
        const canManage = canManageUser(currentUser?.role, record.role)
        const isSuperAdmin = currentUser?.role === Role.SUPER_ADMIN

        return (
          <Space>
            {canManage && (
              <Button type="link" size="small" icon={<EditOutlined />} onClick={() => openEdit(record)}>
                编辑
              </Button>
            )}
            {canManage && (
              <Popconfirm
                title={record.status === 1 ? '确认禁用该用户？' : '确认启用该用户？'}
                onConfirm={() => handleToggleStatus(record)}
              >
                <Button type="link" size="small" icon={record.status === 1 ? <StopOutlined /> : <CheckCircleOutlined />}>
                  {record.status === 1 ? '禁用' : '启用'}
                </Button>
              </Popconfirm>
            )}
            {canManage && (
              <Button type="link" size="small" icon={<LockOutlined />} onClick={() => openResetPwd(record.id)}>
                重置密码
              </Button>
            )}
            {isSuperAdmin && (
              <Popconfirm title="确认删除该用户？此操作不可恢复" onConfirm={() => handleDelete(record.id)}>
                <Button type="link" size="small" danger icon={<DeleteOutlined />} />
              </Popconfirm>
            )}
          </Space>
        )
      },
    },
  ]

  return (
    <div>
      <Card style={{ marginBottom: 16 }}>
        <Row gutter={16} align="middle">
          <Col>
            <Input.Search
              allowClear
              placeholder="搜索手机号/邮箱/昵称"
              style={{ width: 240 }}
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              onSearch={() => { setPage(1); fetchData() }}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="角色筛选"
              style={{ width: 140 }}
              value={roleFilter}
              onChange={(val) => { setRoleFilter(val); setPage(1) }}
             options={[
               { label: '超级管理员', value: 0 },
               { label: '代理商', value: 1 },
               { label: '安装商', value: 2 },
               { label: '终端用户', value: 3 },
            ]}
            />
          </Col>
          <Col>
            <Select
              allowClear
              placeholder="状态筛选"
              style={{ width: 120 }}
              value={statusFilter}
              onChange={(val) => { setStatusFilter(val); setPage(1) }}
              options={Object.entries(STATUS_MAP).map(([k, v]) => ({ label: v.label, value: Number(k) }))}
            />
          </Col>
          <Col>
            <Button icon={<ReloadOutlined />} onClick={fetchData}>刷新</Button>
          </Col>
          {assignableRoles.length > 0 && (
            <Col>
              <Button type="primary" icon={<PlusOutlined />} onClick={openAdd}>
                添加用户
              </Button>
            </Col>
          )}
        </Row>
      </Card>

      <Table<User>
        rowKey="id"
        columns={columns}
        dataSource={data}
        loading={loading}
        pagination={{
          current: page,
          pageSize,
          total,
          showSizeChanger: true,
          showTotal: (t) => `共 ${t} 条`,
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      <Modal
        title={editingUser ? '编辑用户' : '添加用户'}
        open={modalOpen}
        onCancel={() => { setModalOpen(false); form.resetFields() }}
        onOk={handleSave}
        confirmLoading={modalSaving}
        destroyOnClose
      >
        <Form form={form} layout="vertical">
          <Form.Item name="phone" label="手机号" rules={[{ required: true, message: '请输入手机号' }]}>
            <Input placeholder="请输入手机号" />
          </Form.Item>
          <Form.Item name="email" label="邮箱" rules={[{ required: true, message: '请输入邮箱' }, { type: 'email', message: '邮箱格式不正确' }]}>
            <Input placeholder="请输入邮箱" />
          </Form.Item>
          <Form.Item name="nickname" label="昵称" rules={[{ required: true, message: '请输入昵称' }]}>
            <Input placeholder="请输入昵称" />
          </Form.Item>
          <Form.Item name="role" label="角色" rules={[{ required: true, message: '请选择角色' }]}>
            <Select
              placeholder="选择角色"
              options={assignableRoles.map((r) => ({
                label: ROLE_MAP[ROLE_TO_NUMERIC[r]],
                value: ROLE_TO_NUMERIC[r],
              }))}
            />
          </Form.Item>
          {!editingUser && (
            <Form.Item
              name="password"
              label="密码"
              rules={[
                { required: true, message: '请输入密码' },
                { min: 6, message: '密码至少6位' },
              ]}
            >
              <Input.Password placeholder="请输入密码" />
            </Form.Item>
          )}
        </Form>
      </Modal>

      <Modal
        title="重置密码"
        open={resetPwdOpen}
        onCancel={() => { setResetPwdOpen(false); pwdForm.resetFields() }}
        onOk={handleResetPwd}
        confirmLoading={resetPwdSaving}
        destroyOnClose
      >
        <Form form={pwdForm} layout="vertical">
          <Form.Item
            name="password"
            label="新密码"
            rules={[
              { required: true, message: '请输入新密码' },
              { min: 6, message: '密码至少6位' },
            ]}
          >
            <Input.Password placeholder="请输入新密码" />
          </Form.Item>
          <Form.Item
            name="confirmPassword"
            label="确认密码"
            dependencies={['password']}
            rules={[
              { required: true, message: '请确认新密码' },
              ({ getFieldValue }) => ({
                validator(_, value) {
                  if (!value || getFieldValue('password') === value) {
                    return Promise.resolve()
                  }
                  return Promise.reject(new Error('两次输入的密码不一致'))
                },
              }),
            ]}
          >
            <Input.Password placeholder="请再次输入新密码" />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default UsersPage
