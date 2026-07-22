import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Table, Button, Tag, Space, Modal, Input, Row, Col, App, Empty, Alert,
} from 'antd'
import { CheckOutlined, CloseOutlined, ReloadOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import dayjs from 'dayjs'
import { channelApi, type TransferRequest } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'

const STATUS_COLORS: Record<string, string> = {
  pending: 'orange',
  approved: 'green',
  rejected: 'red',
}

const TransferApprovals: React.FC = () => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(20)
  const [selectedRowKeys, setSelectedRowKeys] = useState<React.Key[]>([])
  const [rejectModalOpen, setRejectModalOpen] = useState(false)
  const [rejectingId, setRejectingId] = useState<number | null>(null)
  const [batchReject, setBatchReject] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  const { data: listRes, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.transfers({ page, pageSize }),
    queryFn: () => channelApi.getTransferRequests({ page, pageSize }).then((r) => ({
      items: r.data?.data?.items ?? [] as TransferRequest[],
      total: r.data?.data?.total ?? 0,
    })),
  })

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.channels.transfers() })

  const approveMutation = useMutation({
    mutationFn: (id: number) => channelApi.approveTransfer(id),
    onSuccess: () => { message.success(t('channel.transfer.approveSuccess')); invalidate() },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const rejectMutation = useMutation({
    mutationFn: ({ id, reason }: { id: number; reason?: string }) => channelApi.rejectTransfer(id, reason),
    onSuccess: () => {
      message.success(t('channel.transfer.rejectSuccess'))
      setRejectModalOpen(false)
      setRejectingId(null)
      setRejectReason('')
      invalidate()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const batchApproveMutation = useMutation({
    mutationFn: (ids: number[]) => channelApi.batchApproveTransfers(ids),
    onSuccess: () => {
      message.success(t('channel.transfer.approveSuccess'))
      setSelectedRowKeys([])
      invalidate()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const batchRejectMutation = useMutation({
    mutationFn: ({ ids, reason }: { ids: number[]; reason?: string }) => channelApi.batchRejectTransfers(ids, reason),
    onSuccess: () => {
      message.success(t('channel.transfer.rejectSuccess'))
      setRejectModalOpen(false)
      setBatchReject(false)
      setSelectedRowKeys([])
      setRejectReason('')
      invalidate()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || t('admin.operationFailed')),
  })

  const handleReject = (id: number) => {
    setRejectingId(id)
    setBatchReject(false)
    setRejectReason('')
    setRejectModalOpen(true)
  }

  const handleBatchReject = () => {
    setBatchReject(true)
    setRejectingId(null)
    setRejectReason('')
    setRejectModalOpen(true)
  }

  const confirmReject = () => {
    if (batchReject) {
      batchRejectMutation.mutate({ ids: selectedRowKeys as number[], reason: rejectReason || undefined })
    } else if (rejectingId) {
      rejectMutation.mutate({ id: rejectingId, reason: rejectReason || undefined })
    }
  }

  const columns: ColumnsType<TransferRequest> = [
    {
      title: t('channel.transfer.resourceType'), dataIndex: 'resource_type', width: 90,
      render: (type: string) => (
        <Tag color={type === 'device' ? 'blue' : 'green'}>
          {t(`channel.transfer.resourceType.${type}`)}
        </Tag>
      ),
    },
    { title: t('channel.transfer.fromOrg'), dataIndex: 'from_org_name', width: 150, ellipsis: true },
    { title: t('channel.transfer.toOrg'), dataIndex: 'to_org_name', width: 150, ellipsis: true },
    { title: t('channel.transfer.requester'), dataIndex: 'requester_email', width: 180, ellipsis: true },
    { title: t('channel.transfer.reason'), dataIndex: 'reason', width: 200, ellipsis: true },
    {
      title: t('channel.transfer.status'), dataIndex: 'status', width: 90,
      render: (status: string) => (
        <Tag color={STATUS_COLORS[status] ?? 'default'}>
          {t(`channel.transfer.status.${status}`)}
        </Tag>
      ),
    },
    {
      title: t('channel.transfer.createdAt'), dataIndex: 'created_at', width: 170,
      render: (v: string) => v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 180,
      render: (_: unknown, record: TransferRequest) => (
        record.status === 'pending' ? (
          <Space>
            <Popconfirm
              title={t('channel.transfer.confirmApprove')}
              onConfirm={() => approveMutation.mutate(record.id)}
            >
              <Button size="small" type="primary" icon={<CheckOutlined />}>
                {t('channel.transfer.approve')}
              </Button>
            </Popconfirm>
            <Button
              size="small"
              danger
              icon={<CloseOutlined />}
              onClick={() => handleReject(record.id)}
            >
              {t('channel.transfer.reject')}
            </Button>
          </Space>
        ) : <span style={{ color: '#999' }}>-</span>
      ),
    },
  ]

  return (
    <div>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Space>
            {selectedRowKeys.length > 0 && (
              <>
                <Alert
                  message={t('channel.transfer.selectedCount', { count: selectedRowKeys.length })}
                  type="info"
                  showIcon
                  style={{ display: 'inline-flex' }}
                />
                <Popconfirm
                  title={t('channel.transfer.confirmApprove')}
                  onConfirm={() => batchApproveMutation.mutate(selectedRowKeys as number[])}
                >
                  <Button type="primary" icon={<CheckOutlined />}>
                    {t('channel.transfer.batchApprove')}
                  </Button>
                </Popconfirm>
                <Button danger icon={<CloseOutlined />} onClick={handleBatchReject}>
                  {t('channel.transfer.batchReject')}
                </Button>
              </>
            )}
          </Space>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Col>
      </Row>

      <Table<TransferRequest>
        rowKey="id"
        columns={columns}
        dataSource={listRes?.items ?? []}
        loading={isLoading}
        size="middle"
        locale={{ emptyText: <Empty description={t('common.noData')} /> }}
        rowSelection={{
          selectedRowKeys,
          onChange: setSelectedRowKeys,
          getCheckboxProps: (record) => ({ disabled: record.status !== 'pending' }),
        }}
        pagination={{
          current: page,
          pageSize,
          total: listRes?.total ?? 0,
          showSizeChanger: true,
          showTotal: (total) => t('common.total', { total }),
          onChange: (p, ps) => { setPage(p); setPageSize(ps) },
        }}
      />

      {/* Reject Modal */}
      <Modal
        title={batchReject ? t('channel.transfer.batchReject') : t('channel.transfer.reject')}
        open={rejectModalOpen}
        onOk={confirmReject}
        onCancel={() => { setRejectModalOpen(false); setRejectingId(null); setBatchReject(false); setRejectReason('') }}
        confirmLoading={rejectMutation.isPending || batchRejectMutation.isPending}
        okButtonProps={{ danger: true }}
      >
        <div style={{ marginBottom: 16 }}>
          {batchReject
            ? t('channel.transfer.selectedCount', { count: selectedRowKeys.length })
            : t('channel.transfer.confirmReject')
          }
        </div>
        <Input.TextArea
          rows={3}
          placeholder={t('channel.transfer.rejectReason')}
          value={rejectReason}
          onChange={(e) => setRejectReason(e.target.value)}
        />
      </Modal>
    </div>
  )
}

export default TransferApprovals
