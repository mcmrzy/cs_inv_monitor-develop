import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Button, Tag, Space, Modal, Form, Input, Select, Row, Col, App, Empty, Alert, Descriptions,
} from 'antd'
import { ProTable } from '@ant-design/pro-components'
import type { ProColumns } from '@ant-design/pro-components'
import { PlusOutlined, ReloadOutlined, EditOutlined, DeleteOutlined, RedoOutlined, SwapOutlined, SearchOutlined } from '@ant-design/icons'

import { channelApi, type OrgMember, type UserLookup } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'
import { roleLabel } from '@/utils/roleLabel'

interface Props {
  selectedOrgId: number | null
}

const MEMBER_ROLES = ['org_admin', 'agent', 'distributor', 'installer', 'customer']

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
  // Add-member flow: email lookup → user info → single-identity checks
  const [lookupResult, setLookupResult] = useState<UserLookup | null>(null)
  const [transferOpen, setTransferOpen] = useState(false)
  const [transferringMember, setTransferringMember] = useState<OrgMember | null>(null)
  const [transferForm] = Form.useForm()

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
    mutationFn: (userId: number) =>
      channelApi.addMember({ organization_id: selectedOrgId!, user_id: userId }),
    onSuccess: () => {
      message.success(t('channel.member.addSuccess'))
      setAddOpen(false)
      addForm.resetFields()
      setLookupResult(null)
      invalidate()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || err?.message || t('admin.operationFailed')),
  })

  // Email lookup: backend enforces org-admin permission; 404 means not registered
  const lookupMutation = useMutation({
    mutationFn: (email: string) =>
      channelApi.getUserByEmail(email).then((r) => r.data?.data as UserLookup),
    onSuccess: (user) => setLookupResult(user ?? null),
    onError: (err: any) => {
      setLookupResult(null)
      message.error(err?.response?.data?.message || err?.message || t('admin.operationFailed'))
    },
  })

  // Target-org options for the transfer modal (flat list, current org excluded)
  const { data: orgOptions } = useQuery({
    queryKey: queryKeys.channels.organizations(),
    queryFn: () => channelApi.getOrganizations().then((r) => (r.data?.data ?? []) as { id: number; name: string }[]),
    enabled: transferOpen,
  })

  const transferMutation = useMutation({
    mutationFn: ({ targetOrgId, reason }: { targetOrgId: number; reason?: string }) =>
      channelApi.transferMember({
        membership_ids: [transferringMember!.id],
        target_org_id: targetOrgId,
        reason: reason || undefined,
      }),
    onSuccess: () => {
      message.success(t('channel.member.transferSubmitted'))
      setTransferOpen(false)
      setTransferringMember(null)
      transferForm.resetFields()
      invalidate()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || err?.message || t('admin.operationFailed')),
  })

  // Single-identity checks for the looked-up user:
  // - already a member of the current org → block with warning
  // - belongs to another org → block, suggest removal or transfer approval
  // - no org at all → allowed to add directly
  const isAlreadyMember = !!lookupResult?.memberships?.some((m) => m.organization_id === selectedOrgId)
  const otherOrgs = (lookupResult?.memberships ?? []).filter((m) => m.organization_id !== selectedOrgId)
  const canAdd = !!lookupResult && !isAlreadyMember && otherOrgs.length === 0

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

  const columns: ProColumns<OrgMember>[] = [
    { title: t('channel.member.email'), dataIndex: 'email', width: 200, ellipsis: true },
    {
      title: t('channel.member.phone'), dataIndex: 'phone', width: 130,
      render: (_, record: OrgMember) => record.phone || '-',
    },
    {
      title: t('channel.member.role'), dataIndex: 'role', width: 180,
      render: (_, record: OrgMember) => {
        const codes = (record.role ?? '').split(',').map((code) => code.trim()).filter(Boolean)
        if (codes.length === 0) return '-'
        return (
          <Space size={[4, 4]} wrap>
            {codes.map((code) => (
              <Tag key={code} color="blue">{roleLabel(code, t)}</Tag>
            ))}
          </Space>
        )
      },
    },
    {
      title: t('channel.member.status'), dataIndex: 'status', width: 90,
      render: (_, record: OrgMember) => (
        <Tag color={record.status === 'active' ? 'success' : 'default'}>
          {t(`channel.member.status.${record.status}`)}
        </Tag>
      ),
    },
    {
      title: t('channel.member.joinedAt'), dataIndex: 'joined_at', width: 170,
      render: (_, record: OrgMember) => record.joined_at ? formatInTimezone(record.joined_at, timezone, 'YYYY-MM-DD HH:mm') : '-',
    },
    {
      title: t('common.actions'), key: 'actions', width: 280,
      render: (_: unknown, record: OrgMember) => (
        <Space size={[4, 4]} wrap>
          <Button
            size="small"
            type="link"
            icon={<EditOutlined />}
            onClick={() => {
              setEditingMember(record)
              editForm.setFieldsValue({ role: record.role })
              setEditOpen(true)
            }}
          >
            {t('channel.member.edit')}
          </Button>
          {record.status === 'active' && (
            <Button
              size="small"
              type="link"
              icon={<SwapOutlined />}
              onClick={() => {
                setTransferringMember(record)
                transferForm.resetFields()
                setTransferOpen(true)
              }}
            >
              {t('channel.member.transfer')}
            </Button>
          )}
          {record.status === 'inactive' && (
            <Popconfirm
              title={t('channel.member.reactivate') + '?'}
              onConfirm={() => reactivateMutation.mutate(record.id)}
            >
              <Button size="small" type="link" icon={<RedoOutlined />}>
                {t('channel.member.reactivate')}
              </Button>
            </Popconfirm>
          )}
          <Popconfirm
            title={t('channel.member.confirmRemove')}
            onConfirm={() => removeMutation.mutate(record.id)}
          >
            <Button size="small" type="link" danger icon={<DeleteOutlined />}>
              {t('channel.member.remove')}
            </Button>
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
          <Button type="primary" icon={<PlusOutlined />} onClick={() => { addForm.resetFields(); setLookupResult(null); setAddOpen(true) }}>
            {t('channel.member.add')}
          </Button>
        </Col>
        <Col>
          <Button icon={<ReloadOutlined />} onClick={() => refetch()}>{t('common.refresh')}</Button>
        </Col>
      </Row>

      <ProTable<OrgMember>
        rowKey="id"
        columns={columns}
        dataSource={listRes?.items ?? []}
        loading={isLoading}
        size="middle"
        search={false}
        options={{ density: true, reload: () => refetch(), setting: true }}
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

      {/* Add Member Modal (email lookup → single-identity check → add) */}
      <Modal
        title={t('channel.member.add')}
        open={addOpen}
        onOk={() => { if (lookupResult) addMutation.mutate(lookupResult.user_id) }}
        onCancel={() => { setAddOpen(false); addForm.resetFields(); setLookupResult(null) }}
        okButtonProps={{ disabled: !canAdd }}
        okText={t('common.confirm')}
        confirmLoading={addMutation.isPending}
        destroyOnHidden
      >
        <Alert type="info" showIcon message={t('channel.member.addHint')} style={{ marginBottom: 16 }} />
        <Form form={addForm} layout="vertical" preserve={false}>
          <Form.Item noStyle>
            <Space.Compact style={{ width: '100%', marginBottom: 16 }}>
              <Form.Item
                name="email"
                noStyle
                rules={[{ required: true, type: 'email', message: t('channel.invite.emailRequired') }]}
                style={{ flex: 1 }}
              >
                <Input
                  placeholder="user@example.com"
                  onChange={() => setLookupResult(null)}
                  onPressEnter={() => {
                    addForm.validateFields().then((v) => lookupMutation.mutate(v.email)).catch(() => {})
                  }}
                />
              </Form.Item>
              <Button
                icon={<SearchOutlined />}
                loading={lookupMutation.isPending}
                onClick={() => {
                  addForm.validateFields().then((v) => lookupMutation.mutate(v.email)).catch(() => {})
                }}
              >
                {t('channel.member.lookup')}
              </Button>
            </Space.Compact>
          </Form.Item>
        </Form>
        {lookupResult && (
          <>
            <Descriptions
              size="small"
              bordered
              column={1}
              style={{ marginBottom: 16 }}
              items={[
                { key: 'nickname', label: t('channel.member.nickname'), children: lookupResult.nickname || '-' },
                { key: 'phone', label: t('channel.member.phone'), children: lookupResult.phone || '-' },
                {
                  key: 'orgs',
                  label: t('channel.member.currentOrgs'),
                  children: lookupResult.memberships?.length
                    ? (
                      <Space size={[4, 4]} wrap>
                        {lookupResult.memberships.map((m) => (
                          <Tag key={m.membership_id} color="blue">{m.org_name}</Tag>
                        ))}
                      </Space>
                    )
                    : t('channel.member.noOrgTag'),
                },
              ]}
            />
            {isAlreadyMember && (
              <Alert type="warning" showIcon message={t('channel.member.alreadyMember')} />
            )}
            {!isAlreadyMember && otherOrgs.length > 0 && (
              <Alert
                type="error"
                showIcon
                message={t('channel.member.belongsToOtherOrg', {
                  orgs: otherOrgs.map((m) => m.org_name).join('、'),
                })}
              />
            )}
            {!isAlreadyMember && otherOrgs.length === 0 && (
              <Alert type="success" showIcon message={t('channel.member.noOrg')} />
            )}
          </>
        )}
      </Modal>

      {/* Transfer Member Modal (approval-based) */}
      <Modal
        title={t('channel.member.transferTitle')}
        open={transferOpen}
        onOk={async () => {
          try {
            const values = await transferForm.validateFields()
            transferMutation.mutate({ targetOrgId: values.target_org_id, reason: values.reason })
          } catch {}
        }}
        onCancel={() => { setTransferOpen(false); setTransferringMember(null); transferForm.resetFields() }}
        confirmLoading={transferMutation.isPending}
        destroyOnHidden
      >
        <div style={{ marginBottom: 16 }}>
          <strong>{transferringMember?.email}</strong>
          <div style={{ color: '#999', marginTop: 4 }}>{t('channel.member.transferHint')}</div>
        </div>
        <Form form={transferForm} layout="vertical" preserve={false}>
          <Form.Item
            name="target_org_id"
            label={t('channel.member.transferTargetOrg')}
            rules={[{ required: true, message: t('channel.member.transferTargetOrgPlaceholder') }]}
          >
            <Select
              showSearch
              optionFilterProp="label"
              placeholder={t('channel.member.transferTargetOrgPlaceholder')}
              options={(orgOptions ?? [])
                .filter((o) => o.id !== selectedOrgId)
                .map((o) => ({ label: o.name, value: o.id }))}
            />
          </Form.Item>
          <Form.Item name="reason" label={t('channel.member.transferReason')}>
            <Input.TextArea rows={3} placeholder={t('channel.member.transferReasonPlaceholder')} />
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
        destroyOnHidden
      >
        <div style={{ marginBottom: 16 }}>
          <strong>{editingMember?.email}</strong>
        </div>
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="role" label={t('channel.member.role')} rules={[{ required: true }]}>
            <Select options={MEMBER_ROLES.map((r) => ({ label: roleLabel(r, t), value: r }))} />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default MemberList
