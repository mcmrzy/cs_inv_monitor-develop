import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Button, Tag, Space, App, Empty } from 'antd'
import { ProTable } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { CopyOutlined, ReloadOutlined, StopOutlined } from '@ant-design/icons'

import { channelApi, type Invitation } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'
import { roleLabel } from '@/utils/roleLabel'

// Full status set returned by the backend
const STATUS_COLORS: Record<string, string> = {
  pending: 'orange',
  accepted: 'green',
  rejected: 'red',
  expired: 'default',
  revoked: 'red',
}

const InvitationList: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)

  const { data: listRes, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.invitations({ page, pageSize }),
    queryFn: () => channelApi.getInvitations({ page, pageSize }).then((r) => ({
      items: r.data?.data?.items ?? [],
      total: r.data?.data?.total ?? 0,
    })),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.channels.invitations() })

  const revokeMutation = useMutation({
    mutationFn: (id: number) => channelApi.revokeInvitation(id),
    onSuccess: () => { message.success(t('channel.invite.revokeSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  // Resend an expired invitation by creating a fresh one with the same email+org+role
  const resendMutation = useMutation({
    mutationFn: (inv: Invitation) => {
      const assignments = (inv.role_codes?.length ? inv.role_codes : ['customer'])
        .map((roleCode) => ({ organization_id: inv.organization_id ?? 0, role_code: roleCode }))
        .filter((a) => a.organization_id > 0)
      if (assignments.length === 0) return Promise.reject(new Error('missing org assignment'))
      return channelApi.sendInvitation({ emails: [inv.email], assignments, expires_hours: 72 })
    },
    onSuccess: () => { message.success(t('channel.invite.resendSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const copyInviteLink = () => {
    // The DB stores only the token digest; the full link is returned once at
    // creation time. Guide the user instead of producing an unusable link.
    message.info(t('channel.invite.linkOnlyVisible'))
  }

  const columns: ProColumns<Invitation>[] = [
    { title: t('channel.invite.email'), dataIndex: 'email', width: 200, ellipsis: true },
    {
      title: t('channel.invite.organization'), dataIndex: 'organization', width: 160, ellipsis: true,
      render: (_, record: Invitation) => record.organization || '-',
    },
    {
      title: t('channel.invite.role'), dataIndex: 'role_codes', width: 180,
      render: (_, record: Invitation) => {
        const codes = record.role_codes?.length ? record.role_codes : (record.role_name ? record.role_name.split(',') : [])
        if (codes.length === 0) return '-'
        return (
          <Space size={[4, 4]} wrap>
            {codes.map((code) => (
              <Tag key={code} color="blue">{roleLabel(code.trim(), t)}</Tag>
            ))}
          </Space>
        )
      },
    },
    {
      title: t('channel.invite.status'), dataIndex: 'status', width: 100,
      render: (_, record: Invitation) => (
        <Tag color={STATUS_COLORS[record.status] ?? 'default'}>
          {t(`channel.invite.status.${record.status}`)}
        </Tag>
      ),
    },
    {
      title: t('channel.invite.inviter'), dataIndex: 'inviter_name', width: 130, ellipsis: true,
      render: (_, record: Invitation) => record.inviter_name || '-',
    },
    {
      title: t('channel.invite.expiresAt'), dataIndex: 'expires_at', width: 150,
      render: (_, record: Invitation) => record.expires_at ? formatInTimezone(record.expires_at, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('channel.invite.createdAt'), dataIndex: 'created_at', width: 150,
      render: (_, record: Invitation) => record.created_at ? formatInTimezone(record.created_at, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 160,
      render: (_: unknown, record: Invitation) => (
        <Space>
          {record.status === 'pending' && (
            <>
              <Button
                size="small"
                type="link"
                icon={<CopyOutlined />}
                onClick={copyInviteLink}
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
              onClick={() => resendMutation.mutate(record)}
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
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
        <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
      </div>
      <ProTable<Invitation>
        rowKey="id"
        columns={columns}
        dataSource={listRes?.items ?? []}
        loading={isLoading}
        size="middle"
        search={false}
        options={false}
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
    </div>
  )
}

export default InvitationList
