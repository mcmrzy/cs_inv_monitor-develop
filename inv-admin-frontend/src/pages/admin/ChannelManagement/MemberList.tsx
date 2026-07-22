import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Table, Button, Tag, Space, Modal, Form, Input, Select, Row, Col, App, Empty, Alert,
} from 'antd'
import { PlusOutlined, ReloadOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { channelApi, type OrgMember } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'

interface Props {
  selectedOrgId: number | null
}

const MEMBER_ROLES = ['admin', 'operator', 'dealer', 'installer', 'viewer']

const MemberList: React.FC<Props> = ({ selectedOrgId }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [addOpen, setAddOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [editingMember, setEditingMember] = useState<OrgMember | null>(null)
  const [addForm] = Form.useForm()
  const [editForm] = Form.useForm()

  const { data: listRes, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.members(selectedOrgId ?? 0, { page, pageSize }),
    queryFn: () => channelApi.getOrganizationMembers(selectedOrgId!, { page, pageSize }).then((r) => ({
      items: r.data?.data?.items ?? [] as OrgMember[],
      total: r.data?.data?.total ?? 0,
    })),
    enabled: !!selectedOrgId,
  })

  const invalidate = () => {
    if (selectedOrgId) {
      queryClient.invalidateQueries({ queryKey: queryKeys.channels.members(selectedOrgId) })
    }
  }

  const addMutation = useMutation({
    mutationFn: (values: any) => channelApi.addMember({ ...values, organization_id: selectedOrgId! }),
    onSuccess: () => { message.success(t('channel.member.addSuccess')); setAddOpen(false); addForm.resetFields(); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const removeMutation = useMutation({
    mutationFn: (membershipId: number) => channelApi.removeMember(membershipId),
    onSuccess: () => { message.success(t('channel.member.removeSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const updateRoleMutation = useMutation({
    mutationFn: ({ id, role }: { id: number; role: string }) => channelApi.updateMemberRole(id, role),
    onSuccess: () => { message.success(t('channel.member.updateSuccess')); setEditOpen(false); setEditingMember(null); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const reactivateMutation = useMutation({
    mutationFn: (membershipId: number) => channelApi.reactivateMember(membershipId),
    onSuccess: () => { message.success(t('channel.member.updateSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const columns: ColumnsType<OrgMember> = [
    { title: t('channel.member.email'), dataIndex: 'email', width: 200, ellipsis: true },
    { title: t('channel.member.phone'), dataIndex: 'phone', width: 130 },
    {
      title: t('channel.member.role'), dataIndex: 'role', width: 100,
      render: (role: string) => <Tag color="blue">{role}</Tag>,
    },
    {
      title: t('channel.member.status'), dataIndex: 'status', width: 90,
      render: (status: string) => (
        <Tag color={status === 'active' ? 'success' : 'default'}>
          {t(`channel.member.status.${status}`)}
        </Tag>
      ),
    },
    {
      title: t('channel.member.joinedAt'), dataIndex: 'joined_at', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 200,
      render: (_: unknown, record: OrgMember) => (
        <Space>
          <Button
            size="small"
            type="link"
            onClick={() => {
              setEditingMember(record)
              editForm.setFieldsValue({ role: record.role })
              setEditOpen(true)
            }}
          >
            {t('channel.member.edit')}
          </Button>
          {record.status === 'inactive' && (
            <Popconfirm
              title={t('channel.member.reactivate') + '?'}
              onConfirm={() => reactivateMutation.mutate(record.id)}
            >
              <Button size="small" type="link">{t('channel.member.reactivate')}</Button>
            </Popconfirm>
          )}
          <Popconfirm
            title={t('channel.member.confirmRemove')}
            onConfirm={() => removeMutation.mutate(record.id)}
          >
            <Button size="small" type="link" danger>{t('channel.member.remove')}</Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  if (!selectedOrgId) {
    return (
      <Alert
        message={t('channel.member.selectOrg')}
        type="info"
        showIcon
        style={{ margin: '40px auto', maxWidth: 400, textAlign: 'center' }}
      />
    )
  }

  return (
    <div>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Button type="primary" icon={<PlusOutlined />} onClick={() => { addForm.resetFields(); setAddOpen(true) }}>
            {t('channel.member.add')}
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Col>
      </Row>

      <Table<OrgMember>
        rowKey="id"
        columns={columns}
        dataSource={listRes?.items ?? []}
        loading={isLoading}
        size="middle"
        locale={{ emptyText: <Empty description={t('common.noData')} /> }}
        pagination={{
          current: page,
          pageSize,
          total: listRes?.total ?? 0,
          showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      {/* Add Member Modal */}
      <Modal
        title={t('channel.member.add')}
        open={addOpen}
        onOk={async () => { try { addMutation.mutate(await addForm.validateFields()) } catch {} }}
        onCancel={() => { setAddOpen(false); addForm.resetFields() }}
        confirmLoading={addMutation.isPending}
        destroyOnClose
      >
        <Form form={addForm} layout="vertical" preserve={false}>
          <Form.Item name="email" label={t('channel.member.email')} rules={[{ required: true, type: 'email' }]}>
            <Input placeholder="user@example.com" />
          </Form.Item>
          <Form.Item name="role" label={t('channel.member.role')} rules={[{ required: true }]}>
            <Select options={MEMBER_ROLES.map((r) => ({ label: r, value: r }))} />
          </Form.Item>
        </Form>
      </Modal>

      {/* Edit Role Modal */}
      <Modal
        title={t('channel.member.edit')}
        open={editOpen}
        onOk={async () => {
          try {
            const values = await editForm.validateFields()
            updateRoleMutation.mutate({ id: editingMember!.id, role: values.role })
          } catch {}
        }}
        onCancel={() => { setEditOpen(false); setEditingMember(null) }}
        confirmLoading={updateRoleMutation.isPending}
        destroyOnClose
      >
        <div style={{ marginBottom: 16 }}>
          <strong>{editingMember?.email}</strong>
        </div>
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="role" label={t('channel.member.role')} rules={[{ required: true }]}>
            <Select options={MEMBER_ROLES.map((r) => ({ label: r, value: r }))} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default MemberList
