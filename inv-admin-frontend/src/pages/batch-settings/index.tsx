import { useState, useMemo, useEffect, useRef } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Button, Select, Space, Modal,
  Switch, InputNumber, Typography, Tag, message, Divider,
  Progress, Checkbox, Alert, Result, Descriptions, Tooltip, Spin,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  SettingOutlined, ReloadOutlined,
  ApartmentOutlined, SendOutlined, HistoryOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import useAuthStore from '@/stores/authStore'
import StatusBadge from '@/components/StatusBadge'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { commandErrorDetail } from '../remote-settings/controlContract'
import { commonBatchFields, executeDeviceSettings, isBatchValueValid, loadBatchTarget, type BatchTarget, type DeviceBatchResult, type SettingValue } from './remoteBatch'

const { Title, Text } = Typography

/* ==================== 类型定义 ==================== */

interface Station {
  id: number
  name: string
  location?: string
  [key: string]: any
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  status: number
  /** 后端 JSON 字段为 snake_case */
  station_id?: number | string | null
  station_name?: string
  owner?: { nickname?: string; phone?: string }
  [key: string]: any
}

interface BatchHistoryRecord {
  id: string
  timestamp: string
  operator: string
  deviceCount: number
  parameters: Record<string, SettingValue>
  successCount: number
  failedCount: number
  incompleteCount: number
  status: 'completed' | 'partial' | 'failed'
}

/* ==================== 历史记录模拟存储 ==================== */

let batchHistoryStorage: BatchHistoryRecord[] = []

/* ==================== 主组件 ==================== */

const BatchSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [messageApi, contextHolder] = message.useMessage()
  const user = useAuthStore((state) => state.user)
  const { hasPermission } = useAuthStore()
  const canControlDevices = hasPermission('devices:control')
  const operatorName = user?.nickname || user?.phone || '-'

  // 步骤控制
  const [currentStep, setCurrentStep] = useState(0)

  // 目标选择
  const [selectedStationIds, setSelectedStationIds] = useState<string[]>([])
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])

  // 参数配置
  const [enabledParams, setEnabledParams] = useState<Record<string, boolean>>({})
  const [paramValues, setParamValues] = useState<Record<string, SettingValue | undefined>>({})

  // 执行状态
  const [executing, setExecuting] = useState(false)
  const [executeProgress, setExecuteProgress] = useState(0)
  const [executeResults, setExecuteResults] = useState<DeviceBatchResult[]>([])
  const [executeDone, setExecuteDone] = useState(false)
  const execution = useRef<AbortController | null>(null)
  useEffect(() => () => execution.current?.abort(), [])

  // 历史
  const [batchHistory, setBatchHistory] = useState<BatchHistoryRecord[]>(batchHistoryStorage)

  // 确认弹窗
  const [confirmVisible, setConfirmVisible] = useState(false)

  /* ---------- 数据获取 ---------- */

  const { data: stationsData, error: stationsError, refetch: refetchStations } = useQuery({
    queryKey: ['stations', 'all'],
    // queryFn 归一化返回数组：该 queryKey 与远程设置 DeviceSelector 等页面共用，
    // 不同形状的缓存会互相污染（他页 find/map 崩溃），必须统一为纯数组形状
    queryFn: () =>
      api.get('/stations', { params: { page_size: 999, all: true }, expectedDataShape: 'page' }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d?.items) ? d.items : (Array.isArray(d) ? d : [])) as Station[]
      }),
    staleTime: 300000,
  })

  const stationList: Station[] = Array.isArray(stationsData) ? stationsData : []

  const { data: devicesRes, isLoading: devicesLoading, error: devicesError, refetch: refetchDevices } = useQuery({
    queryKey: ['batch', 'devices', selectedStationIds],
    queryFn: () => {
      const params: any = { page: 1, page_size: 200 }
      // 后端只接受 station_id（snake_case）。单选时服务端过滤；多选时拉全量后本地过滤
      if (selectedStationIds.length === 1) {
        params.station_id = Number(selectedStationIds[0])
      }
      return deviceApi.getDevices(params).then((r) => {
        const d = r.data?.data ?? r.data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
      })
    },
  })

  const allDevices = useMemo(() => {
    let devices = Array.isArray(devicesRes) ? devicesRes : []
    if (selectedStationIds.length > 0) {
      const ids = new Set(selectedStationIds.map(String))
      devices = devices.filter((d) => ids.has(String(d.station_id ?? '')))
    }
    return devices
  }, [devicesRes, selectedStationIds])

  // 设备列表变化（切换电站/过滤）时，清理已不在当前列表中的已选 SN，避免"所见非所发"
  useEffect(() => {
    setSelectedDeviceSns((prev) => {
      if (prev.length === 0) return prev
      const available = new Set(allDevices.map((d) => d.sn))
      const next = prev.filter((sn) => available.has(sn))
      return next.length === prev.length ? prev : next
    })
  }, [allDevices])

  /* ---------- 设备选择逻辑 ---------- */

  const handleSelectAll = () => {
    setSelectedDeviceSns(allDevices.map((d) => d.sn))
  }

  const handleClearAll = () => {
    setSelectedDeviceSns([])
  }

  const toggleDevice = (sn: string) => {
    setSelectedDeviceSns((prev) =>
      prev.includes(sn) ? prev.filter((s) => s !== sn) : [...prev, sn]
    )
  }

  /* ---------- 参数配置逻辑 ---------- */

  const targetsQuery = useQuery({
    queryKey: ['batch', 'remote-settings', selectedDeviceSns],
    enabled: currentStep === 1 && selectedDeviceSns.length > 0 && canControlDevices,
    queryFn: async ({ signal }) => {
      const targets: BatchTarget[] = []
      for (let index = 0; index < selectedDeviceSns.length; index += 4) {
        if (signal.aborted) throw signal.reason
        const chunk = await Promise.all(selectedDeviceSns.slice(index, index + 4).map(loadBatchTarget))
        targets.push(...chunk)
      }
      return targets
    },
    retry: false,
  })
  const fields = commonBatchFields(targetsQuery.data ?? [], hasPermission)
  const activeFields = fields.filter((field) => enabledParams[field.param_key])
  const enabledParamCount = activeFields.length
  const fieldLabel = (key: string, displayKey = 'config.' + key) => t(displayKey) !== displayKey ? t(displayKey) : key
  const enumLabel = (label: string) => {
    const key = 'config.enum.' + label
    return t(key) !== key ? t(key) : label
  }
  const formatValue = (key: string, value: unknown) => {
    if (value == null) return '—'
    const field = fields.find((item) => item.param_key === key)
    if (field?.control_type === 'boolean' || typeof value === 'boolean') return t(Number(value) ? 'batch.on' : 'batch.off')
    const label = field?.enum_map?.[String(value)]
    return label ? enumLabel(label) : String(value)
  }

  const toggleParam = (key: string) => {
    setEnabledParams((prev) => ({ ...prev, [key]: !prev[key] }))
  }

  const setParamValue = (key: string, value: SettingValue | undefined) => {
    setParamValues((prev) => ({ ...prev, [key]: value }))
  }

  /* ---------- 预览数据 ---------- */

  const previewColumns: ColumnsType<DeviceItem> = [
      { title: t('common.deviceSN'), dataIndex: 'sn', key: 'sn', width: 160, fixed: 'left' as const },
      { title: t('common.model'), dataIndex: 'model', key: 'model', width: 120 },
      ...activeFields.map((field) => ({
        title: [fieldLabel(field.param_key, field.display_name_key), field.unit].filter(Boolean).join(' · '),
        key: field.param_key,
        width: 130,
        render: () => formatValue(field.param_key, paramValues[field.param_key]),
      })),
  ]

  /* ---------- 执行逻辑 ---------- */

  const handleExecute = async () => {
    if (execution.current || !canProceedStep1 || !canControlDevices) return
    const controller = new AbortController()
    execution.current = controller
    const changes: Record<string, SettingValue> = {}
    for (const field of activeFields) changes[field.param_key] = paramValues[field.param_key]!
    const available = new Set(allDevices.map((device) => device.sn))
    const targetSns = selectedDeviceSns.filter((sn) => available.has(sn))
    const total = targetSns.length
    if (!total || total !== selectedDeviceSns.length) {
      execution.current = null
      setConfirmVisible(false)
      messageApi.warning(t('batch.noValidTargets'))
      return
    }
    setExecuting(true)
    try {
      const latest = await targetsQuery.refetch({ throwOnError: true })
      if (controller.signal.aborted) return
      const allowed = new Map(commonBatchFields(latest.data ?? [], hasPermission).map((item) => [item.param_key, item]))
      const changed = Object.entries(changes).some(([key, value]) => {
        const field = allowed.get(key)
        return !field || !isBatchValueValid(field, value)
      })
      if (changed) {
        setConfirmVisible(false)
        messageApi.warning(t('batch.targetsChanged'))
        return
      }
    } catch (error) {
      if (!controller.signal.aborted) messageApi.error(commandErrorDetail(error) || t('batch.targetsChanged'))
      return
    } finally {
      if (!controller.signal.aborted) setExecuting(false)
      execution.current = null
    }
    execution.current = controller
    setConfirmVisible(false)
    setExecuting(true)
    setExecuteProgress(0)
    setExecuteResults([])
    setExecuteDone(false)
    setCurrentStep(2)

    const results: DeviceBatchResult[] = []
    for (let index = 0; index < total && !controller.signal.aborted; index += 4) {
      await Promise.all(targetSns.slice(index, index + 4).map(async (sn) => {
        const result = await executeDeviceSettings(sn, changes, controller.signal)
        if (controller.signal.aborted) return
        results.push(result)
        setExecuteProgress(Math.round((results.length / total) * 100))
        setExecuteResults([...results])
      }))
    }
    execution.current = null
    if (controller.signal.aborted) return

    const successCount = results.filter((r) => r.status === 'applied').length
    const failedCount = results.filter((r) => r.status === 'failed').length
    const incompleteCount = total - successCount - failedCount

    const historyRecord: BatchHistoryRecord = {
      id: `batch_${Date.now()}`,
      timestamp: new Date().toISOString(),
      operator: operatorName,
      deviceCount: total,
      parameters: changes,
      successCount,
      failedCount,
      incompleteCount,
      status: successCount === total ? 'completed' : failedCount === total ? 'failed' : 'partial',
    }
    batchHistoryStorage = [historyRecord, ...batchHistoryStorage].slice(0, 50)
    setBatchHistory([...batchHistoryStorage])

    setExecuting(false)
    setExecuteDone(true)

    if (successCount === total) {
      messageApi.success(t('batch.executeSuccess', { total }))
    } else if (failedCount === total) {
      messageApi.error(t('batch.executeFailed', { total }))
    } else {
      messageApi.warning(t('batch.batchSetResult', { total, success: successCount, failed: failedCount, incomplete: incompleteCount }))
    }

    queryClient.invalidateQueries({ queryKey: ['devices'] })
  }

  const handleReset = () => {
    setCurrentStep(0)
    setSelectedStationIds([])
    setSelectedDeviceSns([])
    setEnabledParams({})
    setParamValues({})
    setExecuteResults([])
    setExecuteDone(false)
    setExecuteProgress(0)
  }

  /* ---------- 步骤验证 ---------- */

  const canProceedStep0 = selectedDeviceSns.length > 0
  const canProceedStep1 = !targetsQuery.isError && !targetsQuery.isFetching &&
    enabledParamCount > 0 && activeFields.every((field) => isBatchValueValid(field, paramValues[field.param_key]))
  const appliedCount = executeResults.filter((item) => item.status === 'applied').length
  const failedCount = executeResults.filter((item) => item.status === 'failed').length
  const incompleteCount = executeResults.length - appliedCount - failedCount
  const fieldGroups = [...new Set(fields.map((field) => field.group_code))]

  /* ---------- 设备表格列定义 ---------- */

  const deviceColumns: ColumnsType<DeviceItem> = [
    {
      title: '',
      key: 'checkbox',
      width: 50,
      render: (_: any, record: DeviceItem) => (
        <Checkbox
          checked={selectedDeviceSns.includes(record.sn)}
          onChange={() => toggleDevice(record.sn)}
        />
      ),
    },
    { title: t('common.deviceSN'), dataIndex: 'sn', key: 'sn', width: 160 },
    { title: t('common.model'), dataIndex: 'model', key: 'model', width: 120 },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 90,
      render: (status: number) => <StatusBadge status={status} />,
    },
    {
      title: t('batch.station'),
      key: 'station',
      width: 150,
      render: (_: any, record: DeviceItem) => {
        const station = stationList.find((s) => String(s.id) === String(record.station_id))
        return station?.name || record.station_name || t('batch.noStation')
      },
    },
  ]

  /* ---------- 历史表格列定义 ---------- */

  const historyColumns: ColumnsType<BatchHistoryRecord> = [
    {
      title: t('batch.time'),
      dataIndex: 'timestamp',
      key: 'timestamp',
      width: 180,
      render: (v: string) => formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    { title: t('batch.operator'), dataIndex: 'operator', key: 'operator', width: 100 },
    { title: t('batch.deviceCount'), dataIndex: 'deviceCount', key: 'deviceCount', width: 100 },
    {
      title: t('batch.paramChange'),
      key: 'parameters',
      width: 200,
      render: (_: any, record: BatchHistoryRecord) => {
        const keys = Object.keys(record.parameters)
        return (
          <Space size={[0, 4]} wrap>
            {keys.slice(0, 4).map((key) => <Tag key={key}>{fieldLabel(key)}</Tag>)}
            {keys.length > 4 && <Tag>+{keys.length - 4}</Tag>}
          </Space>
        )
      },
    },
    {
      title: t('batch.successFail'),
      key: 'result',
      width: 120,
      render: (_: any, record: BatchHistoryRecord) => (
        <Space>
          <Text style={{ color: '#52c41a' }}>{record.successCount}</Text>
          <Text style={{ color: '#d48806' }}>{record.incompleteCount}</Text>
          <Text style={{ color: '#ff4d4f' }}>{record.failedCount}</Text>
        </Space>
      ),
    },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (status: string) => {
        const map: Record<string, { labelKey: string; color: string }> = {
          completed: { labelKey: 'batch.allSuccess', color: 'green' },
          partial: { labelKey: 'batch.partialSuccess', color: 'orange' },
          failed: { labelKey: 'batch.allFailed', color: 'red' },
        }
        const cfg = map[status] || { labelKey: status, color: 'default' }
        return <Tag color={cfg.color}>{t(cfg.labelKey)}</Tag>
      },
    },
  ]

  /* ---------- 渲染步骤内容 ---------- */

  const renderStep0 = () => (
    <Row gutter={16}>
      <Col xs={24} lg={8}>
        <Card title={<span><ApartmentOutlined /> {t('batch.stationFilter')}</span>} size="small" bordered={false} style={{ borderRadius: 12 }}>
          <Select
            mode="multiple"
            style={{ width: '100%' }}
            placeholder={t('batch.stationPlaceholder')}
            value={selectedStationIds}
            onChange={setSelectedStationIds}
            options={stationList.map((s) => ({ label: s.name, value: String(s.id) }))}
            allowClear
            showSearch
            optionFilterProp="label"
            maxTagCount={3}
          />
        </Card>
      </Col>
      <Col xs={24} lg={16}>
        <Card
          title={
            <Space>
              <span>{t('batch.deviceList')}</span>
              <Tag color="blue">{t('batch.selectedCount', { selected: selectedDeviceSns.length, total: allDevices.length })}</Tag>
            </Space>
          }
          size="small"
          bordered={false}
          style={{ borderRadius: 12 }}
          extra={
            <Space>
              <Button size="small" onClick={handleSelectAll} disabled={allDevices.length === 0}>
                {t('batch.selectAll')}
              </Button>
              <Button size="small" onClick={handleClearAll} disabled={selectedDeviceSns.length === 0}>
                {t('batch.clearAll')}
              </Button>
            </Space>
          }
        >
          <Table
            rowKey="sn"
            columns={deviceColumns}
            dataSource={allDevices}
            loading={devicesLoading}
            size="small"
            pagination={{ pageSize: 10, showTotal: (total) => t('common.total', { total }) }}
            scroll={{ x: 600 }}
          />
        </Card>
      </Col>
    </Row>
  )

  const renderStep1 = () => (
    <Card title={<span><SettingOutlined /> {t('batch.paramConfig')}</span>} bordered={false} style={{ borderRadius: 12 }}>
      <Alert
        message={t('batch.paramHint')}
        description={t('batch.paramHintDesc')}
        type="info"
        showIcon
        style={{ marginBottom: 16 }}
      />
      {targetsQuery.isFetching && <Spin style={{ marginBottom: 12 }} />}
      {targetsQuery.isError && (
        <QueryErrorAlert error={targetsQuery.error} onRetry={() => void targetsQuery.refetch()} />
      )}
      {!targetsQuery.isPending && !targetsQuery.isError && !fields.length &&
        <Alert type="warning" showIcon message={t('batch.noCommonSettings')} />}
      <Row gutter={[16, 16]}>
        {fieldGroups.map((group) => (
          <Col xs={24} md={12} key={group}>
            <Card
              size="small"
              title={t(`remote.schema.${group}`)}
              bordered={false}
              style={{ height: '100%', borderRadius: 12 }}
              styles={{ body: { padding: '12px' } }}
            >
              {fields.filter((field) => field.group_code === group).map((field) => {
                const key = field.param_key
                const isEnabled = !!enabledParams[key]
                return (
                  <div
                    key={key}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '8px 0',
                      borderBottom: '1px solid #f0f0f0',
                    }}
                  >
                    <div style={{ flex: 1 }}>
                      <Space>
                        <Switch
                          size="small"
                          checked={isEnabled}
                          onChange={() => toggleParam(key)}
                        />
                        <Text strong={isEnabled}>{fieldLabel(key, field.display_name_key)}</Text>
                        {field.unit && <Text type="secondary">({field.unit})</Text>}
                      </Space>
                    </div>
                    <div style={{ width: 160, textAlign: 'right' }}>
                      {field.control_type === 'number' ? (
                        <InputNumber
                          size="small"
                          style={{ width: '100%' }}
                          min={field.min ?? undefined}
                          max={field.max ?? undefined}
                          step={field.step ?? undefined}
                          value={paramValues[key] as number | undefined}
                          onChange={(v) => setParamValue(key, v ?? undefined)}
                          disabled={!isEnabled}
                        />
                      ) : (
                        <Select
                          size="small"
                          style={{ width: '100%' }}
                          value={paramValues[key] === undefined ? undefined : Number(paramValues[key])}
                          onChange={(value: number) => setParamValue(key, field.control_type === 'boolean' ? Boolean(value) : value)}
                          disabled={!isEnabled}
                          options={field.control_type === 'boolean'
                            ? [{ value: 1, label: t('batch.on') }, { value: 0, label: t('batch.off') }]
                            : Object.entries(field.enum_map ?? {}).map(([value, label]) => ({ value: Number(value), label: enumLabel(label) }))}
                        />
                      )}
                    </div>
                  </div>
                )
              })}
            </Card>
          </Col>
        ))}
      </Row>
    </Card>
  )

  const renderStep2 = () => (
    <Card bordered={false} style={{ borderRadius: 12 }}>
      {executeDone ? (
        <Result
          status={incompleteCount > 0 || (appliedCount > 0 && failedCount > 0) ? 'warning' : failedCount > 0 ? 'error' : 'success'}
          title={
            failedCount === 0 && incompleteCount === 0
              ? t('batch.batchSetComplete')
              : appliedCount > 0 || incompleteCount > 0
                ? t('batch.batchSetPartial')
                : t('batch.batchSetFailed')
          }
          subTitle={t('batch.batchSetResult', {
            total: executeResults.length,
            success: appliedCount,
            failed: failedCount,
            incomplete: incompleteCount,
          })}
          extra={[
            <Button type="primary" key="again" onClick={handleReset}>
              {t('batch.continueBatch')}
            </Button>,
          ]}
        />
      ) : (
        <div style={{ textAlign: 'center', padding: '40px 0' }}>
          <Progress
            type="circle"
            percent={executeProgress}
            status={executing ? 'active' : 'normal'}
            style={{ marginBottom: 24 }}
          />
          <div>
            <Text style={{ fontSize: 16 }}>
              {executing
                ? t('batch.executing', { current: executeResults.length, total: selectedDeviceSns.length })
                : t('batch.preparing')}
            </Text>
          </div>
        </div>
      )}

      {executeResults.length > 0 && (
        <div style={{ marginTop: 24 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('batch.executeResult')}:</Text>
          <Table
            rowKey="sn"
            size="small"
            pagination={false}
            dataSource={executeResults}
            columns={[
              { title: t('batch.resultDeviceSN'), dataIndex: 'sn', key: 'sn', width: 160 },
              {
                title: t('batch.resultStatus'),
                dataIndex: 'status',
                key: 'status',
                width: 140,
                render: (status: DeviceBatchResult['status']) => (
                  <Tag color={status === 'applied' ? 'success' : status === 'failed' ? 'error' : 'warning'}>
                    {t(`batch.device.${status}`)}
                  </Tag>
                ),
              },
              {
                title: t('batch.resultMessage'),
                key: 'tasks',
                render: (_, result) => (
                  <Space direction="vertical" size={4}>
                    {result.tasks.map((task) => (
                      <Space key={task.key} wrap>
                        <Text>{fieldLabel(task.key)} · {t(`batch.task.${task.state}`)}</Text>
                        <Text type="secondary">{t('remote.targetValue')} · {formatValue(task.key, paramValues[task.key])}</Text>
                        {task.reported !== undefined &&
                          <Text type="secondary">{t('batch.reportedValue')} · {formatValue(task.key, task.reported)}</Text>}
                        {task.taskId && <Text copyable>{task.taskId}</Text>}
                        {task.message && <Text type="secondary">{task.message}</Text>}
                      </Space>
                    ))}
                  </Space>
                ),
              },
            ]}
            scroll={{ x: 500 }}
          />
        </div>
      )}
    </Card>
  )

  /* ---------- 预览确认弹窗 ---------- */

  const renderConfirmModal = () => (
    <Modal
      title={t('batch.confirmTitle')}
      open={confirmVisible}
      onOk={handleExecute}
      onCancel={() => { if (!executing) setConfirmVisible(false) }}
      okText={t('batch.confirmExecute')}
      cancelText={t('batch.cancel')}
      confirmLoading={executing}
      cancelButtonProps={{ disabled: executing }}
      okButtonProps={{ danger: true, icon: <SendOutlined />, disabled: !canProceedStep1 }}
      width={800}
    >
      <Alert
        message={t('batch.confirmHint')}
        description={t('batch.confirmWarning')}
        type="warning"
        showIcon
        style={{ marginBottom: 16 }}
      />
      <Descriptions bordered size="small" column={2}>
        <Descriptions.Item label={t('batch.targetDevices')}>{selectedDeviceSns.length} {t('batch.targetDevicesUnit')}</Descriptions.Item>
        <Descriptions.Item label={t('batch.changeParams')}>{enabledParamCount} {t('batch.changeParamsUnit')}</Descriptions.Item>
      </Descriptions>
      <Divider />
      <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('batch.paramPreview')}:</Text>
      <Table
        rowKey="sn"
        size="small"
        pagination={false}
        dataSource={allDevices.filter((d) => selectedDeviceSns.includes(d.sn)).map((d, i) => ({ ...d, key: i }))}
        columns={previewColumns}
        scroll={{ x: 600, y: 300 }}
      />
    </Modal>
  )

  const queryFailure = stationsError
    ? { error: stationsError, retry: refetchStations }
    : devicesError
      ? { error: devicesError, retry: refetchDevices }
      : null

  return (
    <div>
      {queryFailure && (
        <QueryErrorAlert
          error={queryFailure.error}
          onRetry={() => { void queryFailure.retry() }}
          style={{ marginBottom: 16 }}
        />
      )}
      {contextHolder}
      <Title level={4} style={{ marginBottom: 24 }}>
        <SettingOutlined style={{ marginRight: 8 }} />
        {t('batch.title')}
      </Title>

      {/* 摘要卡片 */}
      {currentStep < 2 && (
        <Card size="small" bordered={false} style={{ marginBottom: 16, borderRadius: 12 }}>
          <Row>
            <Col>
              <Space>
                <Tag icon={<ApartmentOutlined />} color="blue">
                  {t('batch.selectedDevicesCount', { count: selectedDeviceSns.length })}
                </Tag>
                <Tag icon={<SettingOutlined />} color="orange">
                  {t('batch.paramChangesCount', { count: enabledParamCount })}
                </Tag>
              </Space>
            </Col>
          </Row>
        </Card>
      )}

      {/* 步骤内容 */}
      {currentStep === 0 && renderStep0()}
      {currentStep === 1 && renderStep1()}
      {currentStep === 2 && renderStep2()}

      {/* 操作按钮 */}
      <Card bordered={false} style={{ marginTop: 16, borderRadius: 12 }}>
        <Row justify="space-between">
          <Col>
            {currentStep > 0 && currentStep < 2 && (
              <Button onClick={() => setCurrentStep((s) => s - 1)}>{t('batch.prevStep')}</Button>
            )}
          </Col>
          <Col>
            <Space>
              {currentStep === 0 && (
                <Tooltip title={!canControlDevices ? t('batch.noControlPermission') : undefined}>
                  <Button
                    type="primary"
                    disabled={!canProceedStep0 || !canControlDevices}
                    onClick={() => setCurrentStep(1)}
                  >
                    {t('batch.nextStep')}
                  </Button>
                </Tooltip>
              )}
              {currentStep === 1 && (
                <Tooltip title={!canControlDevices ? t('batch.noControlPermission') : undefined}>
                  <Button
                    type="primary"
                    icon={<SendOutlined />}
                    disabled={!canProceedStep1 || !canControlDevices}
                    onClick={() => setConfirmVisible(true)}
                  >
                    {t('batch.previewExecute')}
                  </Button>
                </Tooltip>
              )}
            </Space>
          </Col>
        </Row>
      </Card>

      {/* 确认弹窗 */}
      {renderConfirmModal()}

      {/* 历史记录 */}
      <Divider />
      <Card
        bordered={false}
        style={{ borderRadius: 12 }}
        title={
          <Space direction="vertical" size={0}>
            <Space>
              <HistoryOutlined />
              <span>{t('batch.recentOps')}</span>
            </Space>
            <Text type="secondary" style={{ fontSize: 12, fontWeight: 400 }}>
              {t('batch.localHistoryOnly')}
            </Text>
          </Space>
        }
        extra={
          <Button
            icon={<ReloadOutlined />}
            size="small"
            onClick={() => setBatchHistory([...batchHistoryStorage])}
          >
            {t('batch.refresh')}
          </Button>
        }
      >
        <Table
          rowKey="id"
          columns={historyColumns}
          dataSource={batchHistory}
          size="small"
          pagination={{ pageSize: 5, showTotal: (total) => t('common.total', { total }) }}
          scroll={{ x: 900 }}
          locale={{ emptyText: t('batch.noRecords') }}
        />
      </Card>
    </div>
  )
}

export default BatchSettingsPage
