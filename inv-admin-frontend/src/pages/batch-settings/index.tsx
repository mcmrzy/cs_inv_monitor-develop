import { useState, useMemo } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Row, Col, Card, Table, Button, Select, Space, Modal,
  Switch, InputNumber, Typography, Tag, message, Steps, Divider,
  Progress, Checkbox, Alert, Result, Descriptions,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  SettingOutlined,
  CheckCircleOutlined, CloseCircleOutlined, ReloadOutlined,
  ApartmentOutlined, SendOutlined, HistoryOutlined,
} from '@ant-design/icons'
import dayjs from 'dayjs'
import api from '@/services/api'
import { deviceApi } from '@/services/deviceApi'
import StatusBadge from '@/components/StatusBadge'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'

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
  stationId?: string
  station_name?: string
  owner?: { nickname?: string; phone?: string }
  [key: string]: any
}

interface ParameterConfig {
  key: string
  labelKey: string
  categoryKey: string
  unit?: string
  min?: number
  max?: number
  step?: number
  defaultValue?: number | boolean
  type: 'number' | 'boolean'
}

interface BatchHistoryRecord {
  id: string
  timestamp: string
  operator: string
  deviceCount: number
  parameters: Record<string, any>
  successCount: number
  failedCount: number
  status: 'completed' | 'partial' | 'failed'
}

/* ==================== 参数配置 ==================== */

const PARAMETER_CONFIGS: ParameterConfig[] = [
  { key: 'charge_power_limit', labelKey: 'batch.chargePowerLimit', categoryKey: 'batch.chargeSettings', unit: '%', min: 0, max: 100, step: 1, defaultValue: 0, type: 'number' },
  { key: 'max_charge_current', labelKey: 'batch.maxChargeCurrent', categoryKey: 'batch.chargeSettings', unit: 'A', min: 0, max: 200, step: 1, defaultValue: 0, type: 'number' },
  { key: 'charge_voltage_limit', labelKey: 'batch.chargeCutoffVoltage', categoryKey: 'batch.chargeSettings', unit: 'V', min: 40, max: 60, step: 0.1, defaultValue: 0, type: 'number' },
  { key: 'enable_charge', labelKey: 'batch.enableCharge', categoryKey: 'batch.chargeSettings', type: 'boolean', defaultValue: true },
  { key: 'discharge_power_limit', labelKey: 'batch.dischargePowerLimit', categoryKey: 'batch.dischargeSettings', unit: '%', min: 0, max: 100, step: 1, defaultValue: 0, type: 'number' },
  { key: 'max_discharge_current', labelKey: 'batch.maxDischargeCurrent', categoryKey: 'batch.dischargeSettings', unit: 'A', min: 0, max: 200, step: 1, defaultValue: 0, type: 'number' },
  { key: 'soc_lower_limit', labelKey: 'batch.socDischargeMin', categoryKey: 'batch.dischargeSettings', unit: '%', min: 0, max: 50, step: 1, defaultValue: 10, type: 'number' },
  { key: 'enable_discharge', labelKey: 'batch.enableDischarge', categoryKey: 'batch.dischargeSettings', type: 'boolean', defaultValue: true },
  { key: 'grid_frequency', labelKey: 'batch.gridFreq', categoryKey: 'batch.gridSettings', unit: 'Hz', min: 45, max: 65, step: 0.1, defaultValue: 50, type: 'number' },
  { key: 'grid_voltage_upper', labelKey: 'batch.overVoltageThreshold', categoryKey: 'batch.gridSettings', unit: 'V', min: 200, max: 280, step: 1, defaultValue: 264, type: 'number' },
  { key: 'grid_voltage_lower', labelKey: 'batch.underVoltageThreshold', categoryKey: 'batch.gridSettings', unit: 'V', min: 150, max: 220, step: 1, defaultValue: 176, type: 'number' },
  { key: 'anti_backflow_enabled', labelKey: 'batch.antiReflux', categoryKey: 'batch.gridSettings', type: 'boolean', defaultValue: false },
  { key: 'work_mode', labelKey: 'batch.workMode', categoryKey: 'batch.appSettings', unit: '', min: 0, max: 3, step: 1, defaultValue: 0, type: 'number' },
  { key: 'export_power_limit', labelKey: 'batch.gridPowerLimit', categoryKey: 'batch.appSettings', unit: '%', min: 0, max: 100, step: 1, defaultValue: 100, type: 'number' },
  { key: 'peak_shaving_enabled', labelKey: 'batch.peakShaving', categoryKey: 'batch.appSettings', type: 'boolean', defaultValue: false },
  { key: 'backup_reserve_soc', labelKey: 'batch.backupSOC', categoryKey: 'batch.appSettings', unit: '%', min: 0, max: 100, step: 1, defaultValue: 20, type: 'number' },
]

const PARAM_CATEGORY_KEYS = [...new Set(PARAMETER_CONFIGS.map((p) => p.categoryKey))]

/* ==================== 历史记录模拟存储 ==================== */

let batchHistoryStorage: BatchHistoryRecord[] = []

/* ==================== 主组件 ==================== */

const BatchSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const queryClient = useQueryClient()
  const [messageApi, contextHolder] = message.useMessage()

  // 步骤控制
  const [currentStep, setCurrentStep] = useState(0)

  // 目标选择
  const [selectedStationIds, setSelectedStationIds] = useState<string[]>([])
  const [selectedDeviceSns, setSelectedDeviceSns] = useState<string[]>([])

  // 参数配置
  const [enabledParams, setEnabledParams] = useState<Record<string, boolean>>({})
  const [paramValues, setParamValues] = useState<Record<string, any>>({})

  // 执行状态
  const [executing, setExecuting] = useState(false)
  const [executeProgress, setExecuteProgress] = useState(0)
  const [executeResults, setExecuteResults] = useState<{
    sn: string
    success: boolean
    message: string
  }[]>([])
  const [executeDone, setExecuteDone] = useState(false)

  // 历史
  const [batchHistory, setBatchHistory] = useState<BatchHistoryRecord[]>(batchHistoryStorage)

  // 确认弹窗
  const [confirmVisible, setConfirmVisible] = useState(false)

  /* ---------- 数据获取 ---------- */

  const { data: stationsRes } = useQuery({
    queryKey: ['stations', 'all'],
    queryFn: () => api.get('/stations', { params: { pageSize: 999, all: true } }).then((r) => r.data),
    staleTime: 300000,
  })

  const stationList: Station[] = useMemo(() => {
    const items = stationsRes?.data?.items ?? stationsRes?.data ?? []
    return Array.isArray(items) ? items : []
  }, [stationsRes])

  const { data: devicesRes, isLoading: devicesLoading } = useQuery({
    queryKey: ['batch', 'devices', selectedStationIds],
    queryFn: () => {
      const params: any = { pageSize: 9999 }
      if (selectedStationIds.length === 1) {
        params.stationId = selectedStationIds[0]
      }
      return deviceApi.getDevices(params).then((r) => {
        const d = r.data?.data ?? r.data
        return (d?.items ?? []) as DeviceItem[]
      })
    },
  })

  const allDevices = useMemo(() => {
    let devices = devicesRes ?? []
    if (selectedStationIds.length > 1) {
      devices = devices.filter((d) =>
        selectedStationIds.includes(String(d.stationId))
      )
    }
    return devices
  }, [devicesRes, selectedStationIds])

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

  const toggleParam = (key: string) => {
    setEnabledParams((prev) => {
      const next = { ...prev, [key]: !prev[key] }
      if (next[key] && paramValues[key] === undefined) {
        const cfg = PARAMETER_CONFIGS.find((p) => p.key === key)
        if (cfg) {
          setParamValues((pv) => ({ ...pv, [key]: cfg.defaultValue ?? (cfg.type === 'boolean' ? false : 0) }))
        }
      }
      return next
    })
  }

  const setParamValue = (key: string, value: any) => {
    setParamValues((prev) => ({ ...prev, [key]: value }))
  }

  const enabledParamCount = Object.values(enabledParams).filter(Boolean).length

  /* ---------- 预览数据 ---------- */

  const previewColumns: ColumnsType<{ sn: string; model: string; [key: string]: any }> = useMemo(() => {
    const paramCols = PARAMETER_CONFIGS.filter((p) => enabledParams[p.key]).map((p) => ({
      title: `${t(p.labelKey)}${p.unit ? `(${p.unit})` : ''}`,
      dataIndex: p.key,
      key: p.key,
      width: 130,
      render: (_: any, record: any) => {
        const v = paramValues[p.key]
        return p.type === 'boolean' ? (v ? t('batch.on') : t('batch.off')) : String(v)
      },
    }))
    return [
      { title: t('common.deviceSN'), dataIndex: 'sn', key: 'sn', width: 160, fixed: 'left' as const },
      { title: t('common.model'), dataIndex: 'model', key: 'model', width: 120 },
      ...paramCols,
    ]
  }, [enabledParams, paramValues, t])

  /* ---------- 执行逻辑 ---------- */

  const buildCommandPayload = () => {
    const params: Record<string, any> = {}
    PARAMETER_CONFIGS.filter((p) => enabledParams[p.key]).forEach((p) => {
      params[p.key] = paramValues[p.key] ?? p.defaultValue
    })
    return { command: 'batch_config', params }
  }

  const handleExecute = async () => {
    setConfirmVisible(false)
    setExecuting(true)
    setExecuteProgress(0)
    setExecuteResults([])
    setExecuteDone(false)
    setCurrentStep(2)

    const payload = buildCommandPayload()
    const total = selectedDeviceSns.length
    const results: { sn: string; success: boolean; message: string }[] = []

    const promises = selectedDeviceSns.map((sn) =>
      deviceApi.sendCommand(sn, payload)
        .then((res) => {
          const d = res.data?.data ?? res.data
          return { sn, success: d?.success ?? true, message: d?.message ?? t('common.success') }
        })
        .catch((err) => ({
          sn,
          success: false,
          message: err?.response?.data?.message || err?.message || t('common.failed'),
        }))
    )

    let completed = 0
    const wrappedPromises = promises.map((p) =>
      p.then((result) => {
        results.push(result)
        completed++
        setExecuteProgress(Math.round((completed / total) * 100))
        setExecuteResults([...results])
        return result
      })
    )

    await Promise.allSettled(wrappedPromises)

    const successCount = results.filter((r) => r.success).length
    const failedCount = results.filter((r) => !r.success).length

    const historyRecord: BatchHistoryRecord = {
      id: `batch_${Date.now()}`,
      timestamp: new Date().toISOString(),
      operator: t('common.currentUser'),
      deviceCount: total,
      parameters: payload.params,
      successCount,
      failedCount,
      status: failedCount === 0 ? 'completed' : successCount === 0 ? 'failed' : 'partial',
    }
    batchHistoryStorage = [historyRecord, ...batchHistoryStorage].slice(0, 50)
    setBatchHistory([...batchHistoryStorage])

    setExecuting(false)
    setExecuteDone(true)

    if (failedCount === 0) {
      messageApi.success(t('batch.executeSuccess', { total }))
    } else if (successCount > 0) {
      messageApi.warning(t('batch.partialExecuteSuccess', { success: successCount, failed: failedCount }))
    } else {
      messageApi.error(t('batch.executeFailed', { total }))
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
  const canProceedStep1 = enabledParamCount > 0

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
        const station = stationList.find((s) => String(s.id) === String(record.stationId))
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
            {keys.slice(0, 4).map((k) => {
              const cfg = PARAMETER_CONFIGS.find((p) => p.key === k)
              return <Tag key={k}>{cfg ? t(cfg.labelKey) : k}</Tag>
            })}
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
          <Text>/</Text>
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
      <Row gutter={[16, 16]}>
        {PARAM_CATEGORY_KEYS.map((categoryKey) => (
          <Col xs={24} md={12} key={categoryKey}>
            <Card
              size="small"
              title={t(categoryKey)}
              bordered={false}
              style={{ height: '100%', borderRadius: 12 }}
              styles={{ body: { padding: '12px' } }}
            >
              {PARAMETER_CONFIGS.filter((p) => p.categoryKey === categoryKey).map((param) => {
                const isEnabled = !!enabledParams[param.key]
                return (
                  <div
                    key={param.key}
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
                          onChange={() => toggleParam(param.key)}
                        />
                        <Text strong={isEnabled}>{t(param.labelKey)}</Text>
                        {param.unit && <Text type="secondary">({param.unit})</Text>}
                      </Space>
                    </div>
                    <div style={{ width: 160, textAlign: 'right' }}>
                      {param.type === 'number' ? (
                        <InputNumber
                          size="small"
                          style={{ width: '100%' }}
                          min={param.min}
                          max={param.max}
                          step={param.step}
                          value={paramValues[param.key] as number}
                          onChange={(v) => setParamValue(param.key, v)}
                          disabled={!isEnabled}
                          placeholder={`${param.min ?? 0} ~ ${param.max ?? 100}`}
                        />
                      ) : (
                        <Switch
                          checked={!!paramValues[param.key]}
                          onChange={(v) => setParamValue(param.key, v)}
                          disabled={!isEnabled}
                          checkedChildren={t('common.on')}
                          unCheckedChildren={t('common.off')}
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
          status={executeResults.every((r) => r.success) ? 'success' : executeResults.some((r) => r.success) ? 'warning' : 'error'}
          title={
            executeResults.every((r) => r.success)
              ? t('batch.batchSetComplete')
              : executeResults.some((r) => r.success)
                ? t('batch.batchSetPartial')
                : t('batch.batchSetFailed')
          }
          subTitle={t('batch.batchSetResult', {
            total: selectedDeviceSns.length,
            success: executeResults.filter((r) => r.success).length,
            failed: executeResults.filter((r) => !r.success).length,
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
            dataSource={executeResults.map((r, i) => ({ ...r, key: i }))}
            columns={[
              { title: t('batch.resultDeviceSN'), dataIndex: 'sn', key: 'sn', width: 160 },
              {
                title: t('batch.resultStatus'),
                dataIndex: 'success',
                key: 'success',
                width: 100,
                render: (v: boolean) =>
                  v ? (
                    <Tag icon={<CheckCircleOutlined />} color="success">{t('batch.resultSuccess')}</Tag>
                  ) : (
                    <Tag icon={<CloseCircleOutlined />} color="error">{t('batch.resultFailed')}</Tag>
                  ),
              },
              { title: t('batch.resultMessage'), dataIndex: 'message', key: 'message' },
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
      onCancel={() => setConfirmVisible(false)}
      okText={t('batch.confirmExecute')}
      cancelText={t('batch.cancel')}
      okButtonProps={{ danger: true, icon: <SendOutlined /> }}
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

  /* ---------- 步骤配置 ---------- */

  const steps = [
    { title: t('batch.step1'), description: t('batch.step1Desc') },
    { title: t('batch.step2'), description: t('batch.step2Desc') },
    { title: t('batch.step3'), description: t('batch.step3Desc') },
  ]

  return (
    <div>
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
                <Button
                  type="primary"
                  disabled={!canProceedStep0}
                  onClick={() => setCurrentStep(1)}
                >
                  {t('batch.nextStep')}
                </Button>
              )}
              {currentStep === 1 && (
                <Button
                  type="primary"
                  icon={<SendOutlined />}
                  disabled={!canProceedStep1}
                  onClick={() => setConfirmVisible(true)}
                >
                  {t('batch.previewExecute')}
                </Button>
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
          <Space>
            <HistoryOutlined />
            <span>{t('batch.recentOps')}</span>
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
