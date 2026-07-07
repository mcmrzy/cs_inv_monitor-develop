import { useState, useCallback, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Button, Input, Select, Space, Modal, Form,
  Drawer, Descriptions, Tooltip, Popconfirm, message, Typography,
  Tag, InputNumber, Tabs, List, Empty, Spin,
} from 'antd'
import type { ColumnsType, TablePaginationConfig } from 'antd/es/table'
import {
  PlusOutlined, SearchOutlined, ReloadOutlined, DeleteOutlined,
  EditOutlined, EyeOutlined, ThunderboltOutlined, SyncOutlined,
  ClusterOutlined, ApartmentOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import ReactECharts from 'echarts-for-react'
import { parallelApi } from '@/services/parallelApi'
import { deviceApi } from '@/services/deviceApi'
import { ALARM_LEVEL_MAP } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'

const { Text, Title } = Typography

interface DeviceOption {
  sn: string
  model: string
}

interface MemberStatus {
  id: number
  parallel_id: number
  device_sn: string
  output_power: number
  load_percent: number
  phase_angle_offset: number
  circulating_current: number
  sync_status: string
  role: string
  data_time: string
}

interface ParallelGroup {
  id: number
  group_name: string
  phase_config: string
  master_sn: string
  slave_sns: string
  circulating_current_threshold: number
  load_balance_deviation: number
  status: number
  created_by: number
  created_at: string
  updated_at: string
  slave_count: number
  total_power: number
  member_status: MemberStatus[]
  members?: MemberStatus[]
}

const ParallelPage: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { timezone } = useTimezoneStore()
  const [filters, setFilters] = useState<{
    keyword?: string
    phaseConfig?: string
    status?: string
  }>({})
  const [pagination, setPagination] = useState({ page: 1, pageSize: 20 })

  const [modalOpen, setModalOpen] = useState(false)
  const [editingGroup, setEditingGroup] = useState<ParallelGroup | null>(null)
  const [form] = Form.useForm()

  const [drawerOpen, setDrawerOpen] = useState(false)
  const [detailId, setDetailId] = useState<number | null>(null)

  const PHASE_CONFIG_MAP: Record<string, { label: string; color: string }> = {
    single: { label: t('parallel.singlePhase'), color: '#1677ff' },
    three_phase: { label: t('parallel.threePhase'), color: '#52c41a' },
  }

  const SYNC_STATUS_MAP: Record<string, { label: string; color: string }> = {
    synced: { label: t('parallel.synced'), color: '#52c41a' },
    syncing: { label: t('parallel.syncing'), color: '#1677ff' },
    desynced: { label: t('parallel.outOfSync'), color: '#fa8c16' },
    offline: { label: '离线', color: '#d9d9d9' },
  }

  const { data: groupsData, isLoading, refetch } = useQuery({
    queryKey: ['parallel-groups', filters, pagination],
    queryFn: () =>
      parallelApi.getGroups({
        ...filters,
        page: pagination.page,
        pageSize: pagination.pageSize,
      }),
  })

  const { data: detailData } = useQuery({
    queryKey: ['parallel-group-detail', detailId],
    queryFn: () => parallelApi.getGroup(detailId!),
    enabled: !!detailId && drawerOpen,
  })

  const { data: alertData } = useQuery({
    queryKey: ['parallel-alerts', detailId],
    queryFn: () => parallelApi.getAlerts(detailId!),
    enabled: !!detailId && drawerOpen,
  })

  const { data: allDevices } = useQuery({
    queryKey: ['all-devices-for-select'],
    queryFn: async () => {
      const res = await deviceApi.getAll()
      return (res.data?.data?.items || []).map((d: any) => ({
        sn: d.sn,
        model: d.model,
      }))
    },
  })

  const createMutation = useMutation({
    mutationFn: (data: any) => parallelApi.createGroup(data),
    onSuccess: () => {
      message.success(t('parallel.createSuccess'))
      setModalOpen(false)
      form.resetFields()
      queryClient.invalidateQueries({ queryKey: ['parallel-groups'] })
    },
    onError: (err: any) => {
      message.error(err.response?.data?.message || t('parallel.createFailed'))
    },
  })

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) =>
      parallelApi.updateGroup(id, data),
    onSuccess: () => {
      message.success(t('parallel.updateSuccess'))
      setModalOpen(false)
      setEditingGroup(null)
      form.resetFields()
      queryClient.invalidateQueries({ queryKey: ['parallel-groups'] })
    },
    onError: (err: any) => {
      message.error(err.response?.data?.message || t('parallel.updateFailed'))
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: number) => parallelApi.deleteGroup(id),
    onSuccess: () => {
      message.success(t('parallel.deleteSuccess'))
      queryClient.invalidateQueries({ queryKey: ['parallel-groups'] })
    },
    onError: (err: any) => {
      message.error(err.response?.data?.message || t('parallel.deleteFailed'))
    },
  })

  const syncMutation = useMutation({
    mutationFn: (id: number) => parallelApi.syncParams(id),
    onSuccess: (res: any) => {
      message.success(res.data?.message || t('parallel.syncSuccess'))
      queryClient.invalidateQueries({ queryKey: ['parallel-group-detail'] })
    },
    onError: (err: any) => {
      message.error(err.response?.data?.message || t('parallel.syncFailed'))
    },
  })

  const handleCreate = () => {
    setEditingGroup(null)
    form.resetFields()
    form.setFieldsValue({
      phaseConfig: 'single',
      circulatingCurrentThreshold: 5.0,
      loadBalanceDeviation: 10.0,
    })
    setModalOpen(true)
  }

  const handleEdit = (record: ParallelGroup) => {
    setEditingGroup(record)
    form.setFieldsValue({
      groupName: record.group_name,
      phaseConfig: record.phase_config,
      masterSn: record.master_sn,
      slaveSns: record.slave_sns,
      circulatingCurrentThreshold: record.circulating_current_threshold,
      loadBalanceDeviation: record.load_balance_deviation,
    })
    setModalOpen(true)
  }

  const handleSubmit = async () => {
    try {
      const values = await form.validateFields()
      const payload = {
        groupName: values.groupName,
        phaseConfig: values.phaseConfig,
        masterSn: values.masterSn,
        slaveSns: Array.isArray(values.slaveSns)
          ? values.slaveSns.join(',')
          : values.slaveSns,
        circulatingCurrentThreshold: values.circulatingCurrentThreshold,
        loadBalanceDeviation: values.loadBalanceDeviation,
      }
      if (editingGroup) {
        updateMutation.mutate({ id: editingGroup.id, data: payload })
      } else {
        createMutation.mutate(payload)
      }
    } catch {
      // validation failed
    }
  }

  const handleDetail = (id: number) => {
    setDetailId(id)
    setDrawerOpen(true)
  }

  const handleSync = (id: number) => {
    syncMutation.mutate(id)
  }

  const handleTableChange = (pag: TablePaginationConfig) => {
    setPagination({
      page: pag.current || 1,
      pageSize: pag.pageSize || 20,
    })
  }

  const deviceOptions: { value: string; label: string }[] =
    allDevices?.map((d: DeviceOption) => ({
      value: d.sn,
      label: `${d.sn} (${d.model || 'N/A'})`,
    })) || []

  const slaveOptions = deviceOptions.filter(
    (opt) => opt.value !== form.getFieldValue('masterSn'),
  )

  const columns: ColumnsType<ParallelGroup> = [
    {
      title: t('parallel.groupName'),
      dataIndex: 'group_name',
      key: 'group_name',
      render: (text: string, record: ParallelGroup) => (
        <a onClick={() => handleDetail(record.id)}>{text}</a>
      ),
    },
    {
      title: t('parallel.phaseConfig'),
      dataIndex: 'phase_config',
      key: 'phase_config',
      render: (val: string) => {
        const cfg = PHASE_CONFIG_MAP[val] || { label: val, color: '#999' }
        return <Tag color={cfg.color}>{cfg.label}</Tag>
      },
    },
    {
      title: t('parallel.masterSN'),
      dataIndex: 'master_sn',
      key: 'master_sn',
    },
    {
      title: t('parallel.slaveCount'),
      dataIndex: 'slave_count',
      key: 'slave_count',
      align: 'center',
    },
    {
      title: t('parallel.totalPower_W'),
      dataIndex: 'total_power',
      key: 'total_power',
      render: (val: number) => (val ? val.toFixed(0) : 0),
      align: 'right',
    },
    {
      title: t('parallel.status'),
      dataIndex: 'status',
      key: 'status',
      align: 'center',
      render: (val: number) =>
        val === 1 ? (
          <Tag color="#52c41a">{t('common.enabled')}</Tag>
        ) : (
          <Tag color="#d9d9d9">{t('common.disabled')}</Tag>
        ),
    },
    {
      title: t('parallel.createTime'),
      dataIndex: 'created_at',
      key: 'created_at',
      render: (val: string) => (val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm') : '-'),
    },
    {
      title: t('common.actions'),
      key: 'actions',
      align: 'center',
      render: (_: any, record: ParallelGroup) => (
        <Space size="small">
          <Tooltip title={t('common.detail')}>
            <Button
              type="link"
              size="small"
              icon={<EyeOutlined />}
              onClick={() => handleDetail(record.id)}
            />
          </Tooltip>
          <Tooltip title={t('common.edit')}>
            <Button
              type="link"
              size="small"
              icon={<EditOutlined />}
              onClick={() => handleEdit(record)}
            />
          </Tooltip>
          <Tooltip title={t('parallel.syncStatus')}>
            <Button
              type="link"
              size="small"
              icon={<SyncOutlined />}
              onClick={() => handleSync(record.id)}
              loading={syncMutation.isPending}
            />
          </Tooltip>
          <Popconfirm
            title={t('parallel.confirmDelete')}
            onConfirm={() => deleteMutation.mutate(record.id)}
          >
            <Tooltip title={t('common.delete')}>
              <Button
                type="link"
                size="small"
                danger
                icon={<DeleteOutlined />}
              />
            </Tooltip>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  const group = detailData?.data?.data || {}

  const getTopologyChartOption = useCallback(() => {
    const members: MemberStatus[] = group.members || []
    if (members.length === 0) return {}

    const nodes: any[] = []
    const links: any[] = []

    const masterNode = members.find((m) => m.role === 'master')
    const slaveNodes = members.filter((m) => m.role === 'slave')

    if (masterNode) {
      nodes.push({
        name: masterNode.device_sn,
        symbolSize: 60,
        itemStyle: { color: '#52c41a' },
        label: {
          show: true,
          formatter: `{b}\n${t('parallel.master')} | ${Number(masterNode.output_power).toFixed(0)}W | ${Number(masterNode.load_percent).toFixed(1)}%`,
        },
      })
    }

    slaveNodes.forEach((m) => {
      nodes.push({
        name: m.device_sn,
        symbolSize: 50,
        itemStyle: { color: '#1677ff' },
        label: {
          show: true,
          formatter: `{b}\n${t('parallel.slave')} | ${Number(m.output_power).toFixed(0)}W | ${Number(m.load_percent).toFixed(1)}%`,
        },
      })
    })

    if (masterNode) {
      slaveNodes.forEach((m) => {
        links.push({
          source: masterNode.device_sn,
          target: m.device_sn,
        })
      })
    }

    return {
      tooltip: {},
      series: [
        {
          type: 'graph',
          layout: 'force',
          roam: false,
          draggable: false,
          force: { repulsion: 200, edgeLength: [150, 200] },
          data: nodes,
          links: links,
          lineStyle: { color: '#aaa', curveness: 0 },
        },
      ],
    }
  }, [group, t])

  const getPowerChartOption = useCallback(() => {
    const members: MemberStatus[] = group.members || []
    if (members.length === 0) return {}

    return {
      tooltip: { trigger: 'axis' },
      xAxis: {
        type: 'category',
        data: members.map((m) => m.device_sn),
        axisLabel: { rotate: 30 },
      },
      yAxis: { type: 'value', name: t('parallel.power_W') },
      series: [
        {
          name: t('parallel.outputPower'),
          type: 'bar',
          data: members.map((m) => ({
            value: Number(m.output_power),
            itemStyle: {
              color: m.role === 'master' ? '#52c41a' : '#1677ff',
            },
          })),
          label: {
            show: true,
            position: 'top',
            formatter: (p: any) => `${p.value.toFixed(0)}W`,
          },
        },
      ],
    }
  }, [group, t])

  const getCirculatingCurrentOption = useCallback(() => {
    const members: MemberStatus[] = group.members || []
    if (members.length === 0) return {}

    return {
      tooltip: { trigger: 'axis' },
      xAxis: {
        type: 'category',
        data: members.map((m) => m.device_sn),
        axisLabel: { rotate: 30 },
      },
      yAxis: { type: 'value', name: t('parallel.circulatingCurrent') },
      series: [
        {
          name: t('parallel.circulating'),
          type: 'bar',
          data: members.map((m) => ({
            value: Number(m.circulating_current),
            itemStyle: {
              color:
                Number(m.circulating_current) >
                Number(group.circulating_current_threshold || 5)
                  ? '#ff4d4f'
                  : '#faad14',
            },
          })),
          label: {
            show: true,
            position: 'top',
            formatter: (p: any) => `${p.value.toFixed(3)}A`,
          },
          markLine: {
            silent: true,
            data: [
              {
                yAxis: Number(group.circulating_current_threshold || 5),
                lineStyle: { color: '#ff4d4f', type: 'dashed' },
                label: { formatter: t('parallel.threshold') },
              },
            ],
          },
        },
      ],
    }
  }, [group, t])

  const memberColumns: ColumnsType<MemberStatus> = [
    { title: 'SN', dataIndex: 'device_sn', key: 'device_sn' },
    {
      title: t('parallel.status'),
      dataIndex: 'role',
      key: 'role',
      render: (val: string) =>
        val === 'master' ? (
          <Tag color="#52c41a">{t('parallel.master')}</Tag>
        ) : (
          <Tag color="#1677ff">{t('parallel.slave')}</Tag>
        ),
    },
    {
      title: t('parallel.outputPower_W'),
      dataIndex: 'output_power',
      key: 'output_power',
      render: (val: number) => Number(val).toFixed(0),
      align: 'right',
    },
    {
      title: t('parallel.load'),
      dataIndex: 'load_percent',
      key: 'load_percent',
      render: (val: number) => `${Number(val).toFixed(1)}%`,
      align: 'right',
    },
    {
      title: t('parallel.phaseOffset'),
      dataIndex: 'phase_angle_offset',
      key: 'phase_angle_offset',
      render: (val: number) => Number(val).toFixed(4),
      align: 'right',
    },
    {
      title: t('parallel.circulatingCurrent_A'),
      dataIndex: 'circulating_current',
      key: 'circulating_current',
      render: (val: number) => {
        const num = Number(val)
        const threshold = Number(group.circulating_current_threshold || 5)
        return (
          <Text style={{ color: num > threshold ? '#ff4d4f' : undefined }}>
            {num.toFixed(3)}
          </Text>
        )
      },
      align: 'right',
    },
    {
      title: t('parallel.syncStatus'),
      dataIndex: 'sync_status',
      key: 'sync_status',
      render: (val: string) => {
        const m = SYNC_STATUS_MAP[val] || { label: val, color: '#999' }
        return <Tag color={m.color}>{m.label}</Tag>
      },
    },
  ]

  const alertColumns: ColumnsType<any> = [
    { title: t('common.deviceSN'), dataIndex: 'device_sn', key: 'device_sn' },
    {
      title: t('parallel.alertLevel'),
      dataIndex: 'alarm_level',
      key: 'alarm_level',
      render: (val: number) => {
        const m = ALARM_LEVEL_MAP[String(val)] || { label: String(val), color: '#999' }
        return <Tag color={m.color}>{m.label}</Tag>
      },
    },
    { title: t('parallel.faultCode'), dataIndex: 'fault_code', key: 'fault_code' },
    { title: t('parallel.faultInfo'), dataIndex: 'fault_message', key: 'fault_message' },
    {
      title: t('parallel.occurTime'),
      dataIndex: 'occurred_at',
      key: 'occurred_at',
      render: (val: string) => (val ? formatInTimezone(val, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'),
    },
    {
      title: t('parallel.status'),
      dataIndex: 'status',
      key: 'status',
      render: (val: number) => {
        const statusMap: Record<number, { label: string; color: string }> = {
          0: { label: t('parallel.unprocessed'), color: '#ff4d4f' },
          1: { label: t('parallel.acknowledged'), color: '#fa8c16' },
          2: { label: t('parallel.recovered'), color: '#52c41a' },
        }
        const m = statusMap[val] || { label: String(val), color: '#999' }
        return <Tag color={m.color}>{m.label}</Tag>
      },
    },
  ]

  return (
    <div>
      <Card
        bordered={false}
        style={{ borderRadius: 12 }}
        title={
          <Space>
            <ClusterOutlined />
            <span>{t('parallel.title')}</span>
          </Space>
        }
        extra={
          <Space>
            <Input.Search
              placeholder={t('parallel.searchGroup')}
              allowClear
              style={{ width: 200 }}
              onSearch={(val) => setFilters({ ...filters, keyword: val })}
            />
            <Select
              placeholder={t('parallel.filterPhase')}
              allowClear
              style={{ width: 120 }}
              value={filters.phaseConfig || undefined}
              onChange={(val) => setFilters({ ...filters, phaseConfig: val })}
              options={[
                { value: 'single', label: t('parallel.singlePhase') },
                { value: 'three_phase', label: t('parallel.threePhase') },
              ]}
            />
            <Select
              placeholder={t('parallel.filterStatus')}
              allowClear
              style={{ width: 100 }}
              value={filters.status || undefined}
              onChange={(val) => setFilters({ ...filters, status: val })}
              options={[
                { value: '1', label: t('common.enabled') },
                { value: '0', label: t('common.disabled') },
              ]}
            />
            <Button icon={<ReloadOutlined />} onClick={() => refetch()}>
              {t('common.refresh')}
            </Button>
            <Button type="primary" icon={<PlusOutlined />} onClick={handleCreate}>
              {t('parallel.createGroup')}
            </Button>
          </Space>
        }
      >
        <Table<ParallelGroup>
          rowKey="id"
          columns={columns}
          dataSource={groupsData?.data?.data?.items || []}
          loading={isLoading}
          size="small"
          pagination={{
            current: pagination.page,
            pageSize: pagination.pageSize,
            total: groupsData?.data?.data?.total || 0,
            showSizeChanger: true,
            showTotal: (total) => t('common.total', { total }),
          }}
          onChange={handleTableChange}
        />
      </Card>

      <Modal
        title={editingGroup ? t('parallel.editGroup') : t('parallel.createGroup')}
        open={modalOpen}
        onOk={handleSubmit}
        onCancel={() => {
          setModalOpen(false)
          setEditingGroup(null)
          form.resetFields()
        }}
        confirmLoading={createMutation.isPending || updateMutation.isPending}
        width={640}
        destroyOnClose
      >
        <Form form={form} layout="vertical" preserve={false}>
          <Form.Item
            name="groupName"
            label={t('parallel.groupName')}
            rules={[{ required: true, message: '请输入组名' }]}
          >
            <Input placeholder="请输入并机组名" maxLength={100} />
          </Form.Item>
          <Form.Item
            name="phaseConfig"
            label={t('parallel.phaseConfig')}
            rules={[{ required: true, message: '请选择相配置' }]}
          >
            <Select
              options={[
                { value: 'single', label: t('parallel.singlePhase') },
                { value: 'three_phase', label: t('parallel.threePhase') },
              ]}
            />
          </Form.Item>
          <Form.Item
            name="masterSn"
            label={t('parallel.masterSN')}
            rules={[{ required: true, message: '请选择主机' }]}
          >
            <Select
              showSearch
              placeholder="搜索并选择主机SN"
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
              }
              options={deviceOptions}
              onChange={() => {
                form.setFieldValue('slaveSns', undefined)
              }}
            />
          </Form.Item>
          <Form.Item
            name="slaveSns"
            label={`${t('parallel.slaveCount')}（最多8台）`}
            rules={[{ required: true, message: '请选择至少一台从机' }]}
          >
            <Select
              mode="multiple"
              showSearch
              placeholder="搜索并选择从机SN"
              filterOption={(input, option) =>
                (option?.label as string)?.toLowerCase().includes(input.toLowerCase())
              }
              options={slaveOptions}
              maxTagCount={8}
              onChange={(values: string[]) => {
                if (values.length > 8) {
                  message.warning(t('parallel.maxSlaves'))
                  form.setFieldValue('slaveSns', values.slice(0, 8))
                }
              }}
            />
          </Form.Item>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item
                name="circulatingCurrentThreshold"
                label={`${t('parallel.circulatingCurrent_A')}${t('parallel.threshold')}`}
              >
                <InputNumber
                  style={{ width: '100%' }}
                  min={0}
                  step={0.1}
                  placeholder="默认5.0A"
                />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item
                name="loadBalanceDeviation"
                label="允许负载偏差(%)"
              >
                <InputNumber
                  style={{ width: '100%' }}
                  min={0}
                  max={100}
                  step={0.5}
                  placeholder="默认10.0%"
                />
              </Form.Item>
            </Col>
          </Row>
        </Form>
      </Modal>

      <Drawer
        title={
          <Space>
            <ClusterOutlined />
            <span>{t('parallel.title')} - {group.group_name || ''}</span>
          </Space>
        }
        open={drawerOpen}
        onClose={() => {
          setDrawerOpen(false)
          setDetailId(null)
        }}
        width={900}
        extra={
          <Space>
            <Button
              icon={<SyncOutlined />}
              onClick={() => detailId && handleSync(detailId)}
              loading={syncMutation.isPending}
            >
              {t('parallel.syncStatus')}
            </Button>
            <Button
              icon={<ReloadOutlined />}
              onClick={() => {
                queryClient.invalidateQueries({ queryKey: ['parallel-group-detail', detailId] })
                queryClient.invalidateQueries({ queryKey: ['parallel-alerts', detailId] })
              }}
            >
              {t('admin.refreshStatus')}
            </Button>
          </Space>
        }
      >
        <Descriptions bordered size="small" column={3} style={{ marginBottom: 16 }}>
          <Descriptions.Item label={t('parallel.groupName')}>{group.group_name}</Descriptions.Item>
          <Descriptions.Item label={t('parallel.phaseConfig')}>
            <Tag color={PHASE_CONFIG_MAP[group.phase_config]?.color}>
              {PHASE_CONFIG_MAP[group.phase_config]?.label || group.phase_config}
            </Tag>
          </Descriptions.Item>
          <Descriptions.Item label={t('parallel.totalPower_W')}>
            <Text strong>{(group.total_power || 0).toFixed(0)} W</Text>
          </Descriptions.Item>
          <Descriptions.Item label={t('parallel.masterSN')}>{group.master_sn}</Descriptions.Item>
          <Descriptions.Item label={`${t('parallel.circulatingCurrent_A')}${t('parallel.threshold')}`}>
            {group.circulating_current_threshold || 5.0} A
          </Descriptions.Item>
          <Descriptions.Item label="负载偏差">
            {group.load_balance_deviation || 10.0}%
          </Descriptions.Item>
        </Descriptions>

        <Tabs
          defaultActiveKey="topology"
          items={[
            {
              key: 'topology',
              label: '拓扑视图',
              children: (
                <Card size="small">
                  {(group.members || []).length > 0 ? (
                    <ReactECharts
                      option={getTopologyChartOption()}
                      style={{ height: 350 }}
                    />
                  ) : (
                    <Empty description="暂无拓扑数据" />
                  )}
                </Card>
              ),
            },
            {
              key: 'members',
              label: '成员状态',
              children: (
                <Table<MemberStatus>
                  rowKey="id"
                  columns={memberColumns}
                  dataSource={group.members || []}
                  pagination={false}
                  size="small"
                />
              ),
            },
            {
              key: 'power',
              label: '功率分布',
              children: (
                <Card size="small">
                  {(group.members || []).length > 0 ? (
                    <ReactECharts
                      option={getPowerChartOption()}
                      style={{ height: 300 }}
                    />
                  ) : (
                    <Empty description="暂无功率数据" />
                  )}
                </Card>
              ),
            },
            {
              key: 'circulating',
              label: '环流监测',
              children: (
                <Card size="small">
                  {(group.members || []).length > 0 ? (
                    <ReactECharts
                      option={getCirculatingCurrentOption()}
                      style={{ height: 300 }}
                    />
                  ) : (
                    <Empty description="暂无环流数据" />
                  )}
                </Card>
              ),
            },
            {
              key: 'alerts',
              label: '相关告警',
              children: (
                <Table<any>
                  rowKey="id"
                  columns={alertColumns}
                  dataSource={alertData?.data?.data?.items || []}
                  pagination={{
                    pageSize: 10,
                    showTotal: (total) => t('common.total', { total }),
                  }}
                  size="small"
                />
              ),
            },
          ]}
        />
      </Drawer>
    </div>
  )
}

export default ParallelPage
