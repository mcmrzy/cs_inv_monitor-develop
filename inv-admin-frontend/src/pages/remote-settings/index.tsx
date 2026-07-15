import React, { useState, useMemo, useCallback, useRef, useEffect } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Card, Form, InputNumber, Switch, Select, Input, Button, Modal,
  message, Tag, Space, Row, Col, Typography, Spin, Empty, Tooltip,
  Alert, Divider,
} from 'antd'
import {
  SafetyCertificateOutlined, ExclamationCircleOutlined,
  LockOutlined, CheckCircleOutlined, ClockCircleOutlined,
  ReloadOutlined, ThunderboltOutlined,
} from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import useTranslation from '@/hooks/useTranslation'
import useAuthStore from '@/stores/authStore'
import { formatInTimezone } from '@/utils/timezone'
import type { CommandCapability, SchemaArg, ControlState, ParameterSchema } from '@/types'

const { Title, Text } = Typography

/* ==================== Helpers ==================== */

/** Safely parse parameter_schema which may arrive as object, string, or null. */
function parseSchema(raw: unknown): ParameterSchema | null {
  if (!raw) return null
  if (typeof raw === 'string') {
    try { return JSON.parse(raw) as ParameterSchema } catch { return null }
  }
  if (typeof raw === 'object' && raw !== null && 'args' in raw) {
    return raw as ParameterSchema
  }
  return null
}

const RISK_COLORS: Record<number, string> = {
  0: '#52c41a', 1: '#52c41a', 2: '#faad14', 3: '#ff4d4f', 4: '#ff4d4f',
}

const SYNC_CONFIG: Record<string, { color: string; icon: React.ReactNode }> = {
  synced: { color: '#52c41a', icon: <CheckCircleOutlined /> },
  in_sync: { color: '#52c41a', icon: <CheckCircleOutlined /> },
  pending: { color: '#faad14', icon: <ClockCircleOutlined /> },
  unknown: { color: '#d9d9d9', icon: <ExclamationCircleOutlined /> },
}

interface DeviceItem {
  id: string
  sn: string
  model: string
  status: number
  last_online_at?: string
  timezone?: string
  [key: string]: unknown
}

/* ==================== CapabilityCard ==================== */

interface CapabilityCardProps {
  cap: CommandCapability
  controlState?: ControlState
  hasPermission: (perm: string) => boolean
  onSend: (cap: CommandCapability, params: Record<string, unknown>) => void
  sending: boolean
}

const CapabilityCard: React.FC<CapabilityCardProps> = ({
  cap, controlState, hasPermission, onSend, sending,
}) => {
  const { t } = useTranslation()
  const [form] = Form.useForm()

  const schema = useMemo(() => parseSchema(cap.parameter_schema), [cap.parameter_schema])
  const args = schema?.args ?? []
  const hasArgs = args.length > 0
  const riskColor = RISK_COLORS[cap.risk_level] ?? '#52c41a'
  const permAllowed = !cap.permission_code || hasPermission(cap.permission_code)

  const desired = controlState?.desired ?? {}
  const reported = controlState?.reported ?? {}

  /* Initialize form defaults from schema defaults + reported state */
  useEffect(() => {
    if (!hasArgs) return
    const defaults: Record<string, unknown> = {}
    args.forEach((arg) => {
      if (reported[arg.key] !== undefined) {
        defaults[arg.key] = reported[arg.key]
      } else if (arg.default !== undefined) {
        defaults[arg.key] = arg.default
      } else if (arg.type === 'boolean') {
        defaults[arg.key] = false
      }
    })
    form.setFieldsValue(defaults)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cap.command_code, JSON.stringify(reported)])

  const handleSend = async () => {
    let params: Record<string, unknown> = {}
    if (hasArgs) {
      try {
        params = await form.validateFields()
      } catch {
        message.warning(t('remote.pleaseCheckForm'))
        return
      }
    }
    onSend(cap, params)
  }

  /* Render a single form field based on schema arg type */
  const renderField = (arg: SchemaArg) => {
    const label = arg.label ?? arg.description ?? arg.key
    const labelText = arg.unit ? `${label} (${arg.unit})` : label

    // Enum → Select
    if (arg.enum && arg.enum.length > 0) {
      return (
        <Form.Item key={arg.key} name={arg.key} label={labelText}>
          <Select placeholder={`Select ${label}`}>
            {arg.enum.map((v) => (
              <Select.Option key={String(v)} value={v}>{String(v)}</Select.Option>
            ))}
          </Select>
        </Form.Item>
      )
    }

    // Boolean → Switch
    if (arg.type === 'boolean') {
      return (
        <Form.Item key={arg.key} name={arg.key} label={labelText} valuePropName="checked">
          <Switch checkedChildren={t('common.on')} unCheckedChildren={t('common.off')} />
        </Form.Item>
      )
    }

    // Integer / Number → InputNumber
    if (arg.type === 'integer' || arg.type === 'number') {
      return (
        <Form.Item key={arg.key} name={arg.key} label={labelText}>
          <InputNumber
            style={{ width: '100%' }}
            min={arg.min}
            max={arg.max}
            step={arg.step ?? (arg.type === 'integer' ? 1 : 0.1)}
            suffix={arg.unit}
          />
        </Form.Item>
      )
    }

    // Default: string → Input
    return (
      <Form.Item key={arg.key} name={arg.key} label={labelText}>
        <Input placeholder={`Enter ${label}`} />
      </Form.Item>
    )
  }

  /* Render desired/reported comparison for args that have state data */
  const renderStateComparison = () => {
    if (!hasArgs) return null
    const stateArgs = args.filter(
      (arg) => desired[arg.key] !== undefined || reported[arg.key] !== undefined,
    )
    if (stateArgs.length === 0) return null

    return (
      <div style={{ marginTop: 4 }}>
        <Divider style={{ margin: '8px 0' }} />
        {stateArgs.map((arg) => {
          const d = desired[arg.key]
          const r = reported[arg.key]
          const isDiff = JSON.stringify(d) !== JSON.stringify(r)
          return (
            <Row key={arg.key} gutter={8} style={{ marginBottom: 2 }}>
              <Col span={8}>
                <Text type="secondary" style={{ fontSize: 12 }}>{arg.key}</Text>
              </Col>
              <Col span={8}>
                <Tag color={isDiff ? 'orange' : 'green'} style={{ fontSize: 11 }}>
                  {t('remote.desiredValue')}: {d !== undefined ? String(d) : '-'}
                </Tag>
              </Col>
              <Col span={8}>
                <Text style={{ fontSize: 12 }}>
                  {t('remote.reportedValue')}: {r !== undefined ? String(r) : '-'}
                </Text>
              </Col>
            </Row>
          )
        })}
      </div>
    )
  }

  return (
    <Card
      bordered={false}
      style={{ borderRadius: 12, marginBottom: 12 }}
      styles={{ body: { padding: 16 } }}
    >
      {/* Header row */}
      <Row align="middle" justify="space-between" style={{ marginBottom: hasArgs ? 12 : 0 }}>
        <Col>
          <Space>
            <Text strong>{cap.display_name || cap.command_code}</Text>
            <Tag color={riskColor}>R{cap.risk_level}</Tag>
            <Text type="secondary" style={{ fontSize: 12 }}>{cap.command_code}</Text>
          </Space>
        </Col>
        <Col>
          {permAllowed ? (
            <Button
              type={hasArgs ? 'default' : 'primary'}
              danger={cap.risk_level >= 3}
              loading={sending}
              onClick={handleSend}
              icon={cap.risk_level >= 3 ? <ExclamationCircleOutlined /> : <ThunderboltOutlined />}
            >
              {t('remote.execute')}
            </Button>
          ) : (
            <Tooltip title={t('remote.noPermissionDesc')}>
              <Button disabled icon={<LockOutlined />}>
                {t('remote.execute')}
              </Button>
            </Tooltip>
          )}
        </Col>
      </Row>

      {/* Risk warning for R3+ */}
      {cap.risk_level >= 3 && (
        <Alert
          type="warning"
          showIcon
          message={`${t('remote.riskWarning')} R${cap.risk_level}`}
          style={{ marginBottom: 12, borderRadius: 8 }}
        />
      )}

      {/* Dynamic form fields */}
      {hasArgs && (
        <Form form={form} layout="vertical" size="small">
          <Row gutter={[16, 0]}>
            {args.map((arg) => (
              <Col key={arg.key} xs={24} md={12}>
                {renderField(arg)}
              </Col>
            ))}
          </Row>
        </Form>
      )}

      {/* Desired vs Reported comparison */}
      {renderStateComparison()}
    </Card>
  )
}

/* ==================== Main Page ==================== */

const RemoteSettingsPage: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [selectedSn, setSelectedSn] = useState('')
  const [searchKeyword, setSearchKeyword] = useState('')
  const [sendingCmd, setSendingCmd] = useState<string | null>(null)
  const [taskStatuses, setTaskStatuses] = useState<Record<string, string>>({})
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const { hasPermission } = useAuthStore()

  /* Clean up polling on unmount */
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
    }
  }, [])

  /* ---------- Device list ---------- */
  const { data: devicesData, isLoading: devicesLoading } = useQuery({
    queryKey: ['remote-settings', 'devices'],
    queryFn: () =>
      deviceApi.getDevices({ pageSize: 9999 }).then((r) => {
        const d = r.data?.data ?? r.data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceItem[]
      }),
    staleTime: 30000,
  })

  const deviceList = useMemo(() => devicesData ?? [], [devicesData])

  const filteredDevices = useMemo(() => {
    if (!searchKeyword) return deviceList
    const kw = searchKeyword.toLowerCase()
    return deviceList.filter(
      (d) => d.sn?.toLowerCase().includes(kw) || d.model?.toLowerCase().includes(kw),
    )
  }, [deviceList, searchKeyword])

  const selectedDevice = deviceList.find((d) => d.sn === selectedSn)

  /* ---------- Control capabilities ---------- */
  const { data: capabilitiesData, isLoading: capsLoading } = useQuery({
    queryKey: ['control-capabilities', selectedSn],
    queryFn: () =>
      deviceApi.getControlCapabilities(selectedSn).then((r) => {
        const d = r.data?.data ?? r.data
        return (Array.isArray(d) ? d : []) as CommandCapability[]
      }),
    enabled: !!selectedSn,
    staleTime: 30000,
  })

  const capabilities = useMemo(
    () => (capabilitiesData ?? []).filter((c) => c.is_enabled),
    [capabilitiesData],
  )

  /* ---------- Control state ---------- */
  const { data: controlState, refetch: refetchState } = useQuery({
    queryKey: ['control-state', selectedSn],
    queryFn: () =>
      deviceApi.getControlState(selectedSn).then((r) => {
        const d = r.data?.data ?? r.data
        return d as ControlState
      }),
    enabled: !!selectedSn,
    staleTime: 10000,
    refetchInterval: 15000,
  })

  /* ---------- Group capabilities by ui_schema.group or config_domain ---------- */
  const groupedCaps = useMemo(() => {
    const groups: Record<string, CommandCapability[]> = {}
    capabilities.forEach((cap) => {
      const group =
        cap.ui_schema?.group ?? cap.config_domain ?? 'default'
      if (!groups[group]) groups[group] = []
      groups[group].push(cap)
    })
    // Sort within each group by ui_schema.order, then risk_level, then command_code
    Object.values(groups).forEach((caps) => {
      caps.sort((a, b) => {
        const orderA = a.ui_schema?.order ?? 999
        const orderB = b.ui_schema?.order ?? 999
        if (orderA !== orderB) return orderA - orderB
        if (a.risk_level !== b.risk_level) return a.risk_level - b.risk_level
        return a.command_code.localeCompare(b.command_code)
      })
    })
    return groups
  }, [capabilities])

  /* ---------- Send command with risk confirmation ---------- */
  const handleSendCommand = useCallback(
    async (cap: CommandCapability, params: Record<string, unknown>) => {
      const doSend = async () => {
        setSendingCmd(cap.command_code)
        try {
          const res = await deviceApi.sendCommand(selectedSn, {
            command: cap.command_code,
            params,
          })
          const respData = res.data?.data ?? res.data
          const taskID = respData?.task_id

          if (taskID) {
            message.info(t('remote.waitingDevice'))
            setTaskStatuses((prev) => ({ ...prev, [taskID]: 'pending' }))
            pollTaskStatus(taskID)
          } else {
            message.success(t('remote.setSuccess'))
          }
          // Invalidate control state to reflect new desired values
          queryClient.invalidateQueries({ queryKey: ['control-state', selectedSn] })
        } catch {
          message.error(t('remote.setFailed'))
        } finally {
          setSendingCmd(null)
        }
      }

      // R3+ requires confirmation modal
      if (cap.risk_level >= 3) {
        Modal.confirm({
          title: `${t('remote.riskWarning')} R${cap.risk_level}`,
          icon: <ExclamationCircleOutlined />,
          content: t('remote.riskConfirmContent', {
            level: cap.risk_level,
            name: cap.display_name || cap.command_code,
          }),
          okText: t('remote.confirmExecute'),
          cancelText: t('remote.cancel'),
          okType: 'danger',
          onOk: doSend,
        })
      } else {
        doSend()
      }
    },
    [selectedSn, t, queryClient],
  )

  /* ---------- Poll task status ---------- */
  const pollTaskStatus = useCallback(
    (taskID: string) => {
      const startTime = Date.now()
      const timeout = 60000
      const interval = 3000

      if (pollRef.current) clearInterval(pollRef.current)

      const poll = async () => {
        if (Date.now() - startTime >= timeout) {
          setTaskStatuses((prev) => ({ ...prev, [taskID]: 'timeout' }))
          message.warning(t('remote.commandTimeout'))
          if (pollRef.current) clearInterval(pollRef.current)
          return
        }

        try {
          const res = await deviceApi.getCommands(selectedSn, {
            task_id: taskID,
            page_size: 50,
          })
          const data = res.data?.data ?? res.data
          const items: unknown[] = data?.items ?? (Array.isArray(data) ? data : [])
          const cmd = (items as Record<string, unknown>[]).find(
            (item) => item.task_id === taskID,
          )
          if (!cmd) return

          const status = cmd.status as string
          setTaskStatuses((prev) => {
            if (prev[taskID] === status) return prev
            return { ...prev, [taskID]: status }
          })

          // Show status messages on terminal states
          if (status === 'success' || status === 'completed') {
            message.success(t('remote.commandSuccess'))
            if (pollRef.current) clearInterval(pollRef.current)
            refetchState()
          } else if (
            status === 'failed' ||
            status === 'timeout' ||
            status === 'cancelled'
          ) {
            message.error(t('remote.commandFailed'))
            if (pollRef.current) clearInterval(pollRef.current)
          }
        } catch {
          // Network error during poll — continue polling
        }
      }

      poll()
      pollRef.current = setInterval(poll, interval)
    },
    [selectedSn, t, refetchState],
  )

  /* ---------- Sync status display ---------- */
  const syncStatus = controlState?.sync_status ?? 'unknown'
  const syncCfg = SYNC_CONFIG[syncStatus] ?? SYNC_CONFIG.unknown

  /* ==================== Render ==================== */

  return (
    <div>
      <Row align="middle" justify="space-between" style={{ marginBottom: 16 }}>
        <Col>
          <Title level={4} style={{ margin: 0 }}>
            <SafetyCertificateOutlined style={{ marginRight: 8 }} />
            {t('remote.title')}
          </Title>
        </Col>
      </Row>

      {/* Device selector */}
      <Card bordered={false} style={{ borderRadius: 12, marginBottom: 16 }}>
        <Row gutter={[16, 12]} align="middle">
          <Col xs={24} sm={12} md={8} lg={6}>
            <Text strong style={{ display: 'block', marginBottom: 4 }}>
              {t('remote.selectDevice')}:
            </Text>
            <Select
              showSearch
              optionFilterProp="label"
              placeholder={t('remote.searchDevice')}
              style={{ width: '100%' }}
              value={selectedSn || undefined}
              onChange={(v) => setSelectedSn(v)}
              allowClear
              onSearch={setSearchKeyword}
              filterOption={false}
              loading={devicesLoading}
              notFoundContent={
                devicesLoading ? <Spin size="small" /> : <Empty description={t('remote.noMatch')} />
              }
              options={filteredDevices.map((d) => {
                const statusCfg = DEVICE_STATUS_MAP[d.status] ?? DEVICE_STATUS_MAP[0]
                return {
                  label: (
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <span>{d.sn} {d.model ? `(${d.model})` : ''}</span>
                      <span style={{ fontSize: 12, color: statusCfg.color }}>{statusCfg.label}</span>
                    </div>
                  ),
                  value: d.sn,
                }
              })}
            />
          </Col>
          {selectedDevice && (
            <Col>
              <Space split={<span style={{ color: '#d9d9d9' }}>|</span>}>
                <Text strong>SN: {selectedDevice.sn}</Text>
                {selectedDevice.model && (
                  <Text type="secondary">
                    {t('remote.model')}: {selectedDevice.model}
                  </Text>
                )}
                <Tag color={DEVICE_STATUS_MAP[selectedDevice.status]?.color ?? '#d9d9d9'}>
                  {DEVICE_STATUS_MAP[selectedDevice.status]?.label ?? t('remote.unknown')}
                </Tag>
                {selectedDevice.last_online_at && (
                  <Tooltip title={t('remote.lastCommunication')}>
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      {t('remote.lastOnline')}:{' '}
                      {formatInTimezone(
                        selectedDevice.last_online_at,
                        selectedDevice.timezone,
                      )}
                    </Text>
                  </Tooltip>
                )}
              </Space>
            </Col>
          )}
        </Row>
      </Card>

      {!selectedSn ? (
        <Card bordered={false} style={{ borderRadius: 12, padding: 60 }}>
          <Empty description={t('remote.pleaseSelectDevice')} />
        </Card>
      ) : capsLoading ? (
        <Card bordered={false} style={{ borderRadius: 12, padding: 60 }}>
          <div style={{ textAlign: 'center' }}>
            <Spin tip={t('remote.schemaLoading')} />
          </div>
        </Card>
      ) : capabilities.length === 0 ? (
        <Card bordered={false} style={{ borderRadius: 12, padding: 60 }}>
          <Empty description={t('remote.noCapabilities')} />
        </Card>
      ) : (
        <>
          {/* Sync status bar */}
          <Card
            bordered={false}
            style={{ borderRadius: 12, marginBottom: 16 }}
            styles={{ body: { padding: '12px 16px' } }}
          >
            <Row align="middle" justify="space-between">
              <Col>
                <Space>
                  <span style={{ color: syncCfg.color }}>{syncCfg.icon}</span>
                  <Text>{t('remote.syncStatus')}:</Text>
                  <Tag color={syncCfg.color}>
                    {t(`remote.${syncStatus === 'in_sync' ? 'synced' : syncStatus}`)}
                  </Tag>
                  {controlState?.desired_at && (
                    <Text type="secondary" style={{ fontSize: 12 }}>
                      {t('remote.desiredValue')}: {formatInTimezone(controlState.desired_at, selectedDevice?.timezone)}
                    </Text>
                  )}
                </Space>
              </Col>
              <Col>
                <Button
                  size="small"
                  icon={<ReloadOutlined />}
                  onClick={() => refetchState()}
                >
                  {t('remote.refreshState')}
                </Button>
              </Col>
            </Row>
          </Card>

          {/* Grouped capability cards */}
          {Object.entries(groupedCaps).map(([group, caps]) => (
            <div key={group}>
              <Title level={5} style={{ marginTop: 16, marginBottom: 8, textTransform: 'capitalize' }}>
                {group === 'default' ? t('remote.commandParams') : group}
              </Title>
              {caps.map((cap) => (
                <CapabilityCard
                  key={cap.command_code}
                  cap={cap}
                  controlState={controlState}
                  hasPermission={hasPermission}
                  onSend={handleSendCommand}
                  sending={sendingCmd === cap.command_code}
                />
              ))}
            </div>
          ))}
        </>
      )}
    </div>
  )
}

export default RemoteSettingsPage
