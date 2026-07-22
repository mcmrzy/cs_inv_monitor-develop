import { useState, useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Tree, Button, Input, Space, Tag, Spin, Modal, Form, Select, Row, Col, App, Empty,
} from 'antd'
import {
  PlusOutlined, EditOutlined, DeleteOutlined, SwapOutlined, ReloadOutlined,
} from '@ant-design/icons'
import type { DataNode } from 'antd/es/tree'
import dayjs from 'dayjs'
import { channelApi, type Organization } from '@/services/channelApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import Popconfirm from '@/components/LocalizedPopconfirm'

interface Props {
  selectedOrgId: number | null
  onSelectOrg: (id: number | null) => void
}

const ORG_TYPES = ['manufacturer', 'distributor', 'dealer', 'installer', 'end_user']

const OrganizationTree: React.FC<Props> = ({ selectedOrgId, onSelectOrg }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()
  const [searchText, setSearchText] = useState('')
  const [createOpen, setCreateOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [moveOpen, setMoveOpen] = useState(false)
  const [editingOrg, setEditingOrg] = useState<Organization | null>(null)
  const [movingOrg, setMovingOrg] = useState<Organization | null>(null)
  const [createForm] = Form.useForm()
  const [editForm] = Form.useForm()
  const [moveForm] = Form.useForm()

  const { data: orgs, isLoading, error, refetch } = useQuery({
    queryKey: queryKeys.channels.organizations(),
    queryFn: () => channelApi.getOrganizations().then((r) => r.data?.data ?? []),
  })

  const orgList = (orgs ?? []) as Organization[]

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.channels.organizations() })

  // ── Build tree data ──
  const buildTree = (items: Organization[], parentId: number | null = null): DataNode[] => {
    return items
      .filter((o) => o.parent_id === parentId)
      .map((o) => ({
        key: o.id,
        title: o.name,
        data: o,
        children: buildTree(items, o.id),
      }))
  }

  const filteredOrgs = useMemo(() => {
    if (!searchText.trim()) return orgList
    const keyword = searchText.toLowerCase()
    const matchIds = new Set<number>()
    const findMatches = (items: Organization[]): Organization[] => {
      const result: Organization[] = []
      for (const org of items) {
        if (org.name.toLowerCase().includes(keyword) || org.type.toLowerCase().includes(keyword)) {
          matchIds.add(org.id)
          result.push(org)
        }
      }
      return result
    }
    findMatches(orgList)
    // include parents of matched items
    const includeParents = (items: Organization[]): Organization[] => {
      const res: Organization[] = []
      for (const org of items) {
        if (matchIds.has(org.id)) {
          res.push(org)
        } else {
          const children = includeParents(items.filter((o) => o.parent_id === org.id))
          if (children.length > 0) {
            res.push(org, ...children)
          }
        }
      }
      return res
    }
    return includeParents(orgList).length > 0 ? includeParents(orgList) : orgList
  }, [orgList, searchText])

  const treeData = useMemo(() => buildTree(filteredOrgs), [filteredOrgs])

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

  const getTypeColor = (type: string) => {
    const colors: Record<string, string> = {
      manufacturer: 'blue',
      distributor: 'purple',
      dealer: 'cyan',
      installer: 'green',
      end_user: 'orange',
    }
    return colors[type] ?? 'default'
  }

  return (
    <div>
      {error && <QueryErrorAlert error={error} onRetry={() => { void refetch() }} style={{ marginBottom: 16 }} />}
      <Row justify="space-between" align="middle" style={{ marginBottom: 16 }}>
        <Col>
          <Space>
            <Button type="primary" icon={<PlusOutlined />} onClick={() => {
              createForm.resetFields()
              if (selectedOrgId) createForm.setFieldsValue({ parent_id: selectedOrgId })
              setCreateOpen(true)
            }}>
              {t('channel.org.create')}
            </Button>
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
        {treeData.length === 0 ? (
          <Empty description={t('common.noData')} style={{ padding: 40 }} />
        ) : (
          <Tree
            treeData={treeData}
            showLine={{ showLeafIcon: false }}
            defaultExpandAll
            selectedKeys={selectedOrgId ? [selectedOrgId] : []}
            onSelect={(keys) => onSelectOrg(keys[0] as number ?? null)}
            titleRender={(node: any) => {
              const org = node.data as Organization
              return (
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '2px 0' }}>
                  <strong>{org.name}</strong>
                  <Tag color={getTypeColor(org.type)}>{t(`channel.org.type.${org.type}`)}</Tag>
                  <Tag color={org.status === 'active' ? 'success' : 'default'}>
                    {t(`channel.org.status.${org.status}`)}
                  </Tag>
                  <span style={{ color: '#999', fontSize: 12 }}>
                    {t('channel.org.memberCount')}: {org.member_count}
                  </span>
                  <Space size={2} style={{ marginLeft: 4 }}>
                    <Button
                      size="small"
                      type="link"
                      icon={<EditOutlined />}
                      onClick={(e) => {
                        e.stopPropagation()
                        setEditingOrg(org)
                        editForm.setFieldsValue({ name: org.name, type: org.type, description: org.description })
                        setEditOpen(true)
                      }}
                    />
                    <Button
                      size="small"
                      type="link"
                      icon={<SwapOutlined />}
                      onClick={(e) => {
                        e.stopPropagation()
                        setMovingOrg(org)
                        moveForm.setFieldsValue({ parent_id: org.parent_id })
                        setMoveOpen(true)
                      }}
                    />
                    <Popconfirm
                      title={t('channel.org.confirmToggle')}
                      onConfirm={() => toggleMutation.mutate(org.id)}
                    >
                      <Button
                        size="small"
                        type="link"
                        danger={org.status === 'active'}
                        onClick={(e) => e.stopPropagation()}
                      >
                        {org.status === 'active' ? t('channel.org.status.disabled') : t('channel.org.status.active')}
                      </Button>
                    </Popconfirm>
                    <Popconfirm
                      title={t('channel.org.confirmDelete')}
                      onConfirm={() => deleteMutation.mutate(org.id)}
                    >
                      <Button
                        size="small"
                        type="link"
                        danger
                        icon={<DeleteOutlined />}
                        onClick={(e) => e.stopPropagation()}
                      />
                    </Popconfirm>
                  </Space>
                </span>
              )
            }}
          />
        )}
      </Spin>

      {/* Create Modal */}
      <Modal
        title={t('channel.org.create')}
        open={createOpen}
        onOk={async () => { try { createMutation.mutate(await createForm.validateFields()) } catch {} }}
        onCancel={() => { setCreateOpen(false); createForm.resetFields() }}
        confirmLoading={createMutation.isPending}
        destroyOnClose
      >
        <Form form={createForm} layout="vertical" preserve={false}>
          <Form.Item name="name" label={t('channel.org.name')} rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="type" label={t('channel.org.type')} rules={[{ required: true }]}>
            <Select options={ORG_TYPES.map((type) => ({ label: t(`channel.org.type.${type}`), value: type }))} />
          </Form.Item>
          <Form.Item name="parent_id" label={t('channel.org.parent')}>
            <Select
              allowClear
              placeholder={t('channel.org.parentNone')}
              options={orgList.map((o) => ({ label: o.name, value: o.id }))}
            />
          </Form.Item>
          <Form.Item name="description" label={t('channel.org.description')}>
            <Input.TextArea rows={3} />
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
        destroyOnClose
      >
        <Form form={editForm} layout="vertical" preserve={false}>
          <Form.Item name="name" label={t('channel.org.name')} rules={[{ required: true }]}>
            <Input />
          </Form.Item>
          <Form.Item name="type" label={t('channel.org.type')} rules={[{ required: true }]}>
            <Select options={ORG_TYPES.map((type) => ({ label: t(`channel.org.type.${type}`), value: type }))} />
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
        destroyOnClose
      >
        <div style={{ marginBottom: 16 }}>
          <strong>{movingOrg?.name}</strong>
        </div>
        <Form form={moveForm} layout="vertical" preserve={false}>
          <Form.Item name="parent_id" label={t('channel.org.parent')}>
            <Select
              allowClear
              placeholder={t('channel.org.parentNone')}
              options={orgList
                .filter((o) => o.id !== movingOrg?.id)
                .map((o) => ({ label: o.name, value: o.id }))}
            />
          </Form.Item>
        </Form>
      </Modal>
    </div>
  )
}

export default OrganizationTree
