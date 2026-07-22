import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Table, Button, Tag, Space, Modal, Form, Input, Select, InputNumber, Row, Col, App, Empty,
} from 'antd'
import { PlusOutlined, CopyOutlined, ReloadOutlined, StopOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { channelApi, type Invitation } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'

interface Props {
  selectedOrgId: number | null
}

const INVITE_ROLES = ['admin', 'operator', 'dealer', 'installer', 'viewer']

const STATUS_COLORS: Record<string, string> = {
  pending: 'orange',
  used: 'green',
  expired: 'default',
  revoked: 'red',
}

const InvitationManager: React.FC<Props> = ({ selectedOrgId }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [sendOpen, setSendOpen] = useState(false)
  const [sendForm] = Form.useForm()

  const { data: listRes, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.invitations({ page, pageSize }),
    queryFn: () => channelApi.getInvitations({ page, pageSize }).then((r) => ({
      items: r.data?.data?.items ?? [] as Invitation[],
      total: r.data?.data?.total ?? 0,
    })),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.channels.invitations() })

  const sendMutation = useMutation({
    mutationFn: (values: any) => channelApi.sendInvitation({
      ...values,
      organization_id: selectedOrgId ?? values.organization_id,
    }),
    onSuccess: () => { message.success(t('channel.invite.sendSuccess')); setSendOpen(false); sendForm.resetFields(); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const revokeMutation = useMutation({
    mutationFn: (id: number) => channelApi.revokeInvitation(id),
    onSuccess: () => { message.success(t('channel.invite.revokeSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const resendMutation = useMutation({
    mutationFn: (id: number) => channelApi.resendInvitation(id),
    onSuccess: () => { message.success(t('channel.invite.resendSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const copyInviteLink = (token: string) => {
    const link = `${window.location.origin}/invite/${token}`
    navigator.clipboard.writeText(link).then(() => {
      message.success(t('channel.invite.linkCopied'))
    }).catch(() => {
      message.error('Failed to copy')
    })
  }

  const columns: ColumnsType<Invitation> = [
    { title: t('channel.invite.email'), dataIndex: 'email', width: 200, ellipsis: true },
    {
      title: t('channel.invite.role'), dataIndex: 'role_name', width: 100,
      render: (role: string) => <Tag color="blue">{role}</Tag>,
    },
    {
      title: t('channel.invite.status'), dataIndex: 'status', width: 100,
      render: (status: string) => (
        <Tag color={STATUS_COLORS[status] ?? 'default'}>
          {t(`channel.invite.status.${status}`)}
        </Tag>
      ),
    },
    {
      title: t('channel.invite.expiresAt'), dataIndex: 'expires_at', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('channel.invite.createdAt'), dataIndex: 'created_at', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 220,
      render: (_: unknown, record: Invitation) => (
        <Space>
          {record.status === 'pending' && (
            <>
              <Button
                size="small"
                type="link"
                icon={<CopyOutlined />}
                onClick={() => copyInviteLink(record.token_hint)}
              >
                {t('channel.invite.copyLink')}
              </Button>
              <Popconfirm
                title={t('channel.invite.confirmRevoke')}
                onConfirm={() => revokeMutation.mutate(record.id)}
              >
                <Button size="small" type="link" danger icon={<StopOutlined />}>
                  {t('channel.invite.revoke')}
                </Button>
              </Popconfirm>
            </>
          )}
          {record.status === 'expired' && (
            <Button
              size="small"
              type="link"
              onClick={() => resendMutation.mutate(record.id)}
            >
              {t('channel.invite.resend')}
            </Button>
          )}
        </Space>
      ),
    },
  ]

  return (
    <div>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Button
            type="primary"
            icon={<PlusOutlined />}
            onClick={() => {
              sendForm.resetFields()
              if (selectedOrgId) sendForm.setFieldsValue({ organization_id: selectedOrgId })
              setSendOpen(true)
            }}
          >
            {t('channel.invite.send')}
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Col>
      </Row>

      <Table<Invitation>
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

      {/* Send Invitation Modal */}
      <Modal
        title={t('channel.invite.send')}
        open={sendOpen}
        onOk={async () => { try { sendMutation.mutate(await sendForm.validateFields()) } catch {} }}
        onCancel={() => { setSendOpen(false); sendForm.resetFields() }}
        confirmLoading={sendMutation.isPending}
        destroyOnClose
      >
        <Form form={sendForm} layout="vertical" preserve={false}>
          <Form.Item name="email" label={t('channel.invite.email')} rules={[{ required: true, type: 'email' }]}>
            <Input placeholder="user@example.com" />
          </Form.Item>
          <Form.Item name="role_name" label={t('channel.invite.role')} rules={[{ required: true }]}>
            <Select options={INVITE_ROLES.map((r) => ({ label: r, value: r }))} />
          </Form.Item>
          <Form.Item name="expires_in_hours" label={t('channel.invite.expiryHours')} initialValue={72}>
            <InputNumber min={1} max={720} style={{ width: '100%' }} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default InvitationManager
