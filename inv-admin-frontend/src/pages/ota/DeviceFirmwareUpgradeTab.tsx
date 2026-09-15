import React, { useMemo, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  App,
  Alert,
  Button,
  Card,
  Col,
  Descriptions,
  Empty,
  Flex,
  Input,
  List,
  Modal,
  Row,
  Select,
  Space,
  Statistic,
  Table,
  Tag,
  Typography,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import {
  CheckCircleOutlined,
  CloudUploadOutlined,
  DesktopOutlined,
  ReloadOutlined,
  RollbackOutlined,
  RocketOutlined,
  SearchOutlined,
} from '@ant-design/icons'
import { otaApi, createOtaIdempotencyKey } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { canControlDeviceFirmware } from '@/router/routeAccess'
import {
  firmwareModuleLabel,
  normalizeFirmwareTarget,
  canRemoteUpgradeFirmwareModule,
} from './firmwarePresentation'
import type {
  Device,
  DeviceFirmwareOverview,
  DeviceUpgrade,
  FirmwareModuleOverview,
  FirmwareResource,
} from '@/types'

const { Text, Title } = Typography

const VERSION_STATE_MAP: Record<string, { i18nKey: string; color: string }> = {
  unreported: { i18nKey: 'ota.moduleStateUnreported', color: 'default' },
  current: { i18nKey: 'ota.moduleStateCurrent', color: 'success' },
  outdated: { i18nKey: 'ota.moduleStateOutdated', color: 'warning' },
}

const UPGRADE_STATUS_MAP: Record<string, { i18nKey: string; color: string }> = {
  pending: { i18nKey: 'ota.taskStatusPending', color: 'processing' },
  downloading: { i18nKey: 'ota.downloading', color: 'cyan' },
  upgrading: { i18nKey: 'ota.upgrading', color: 'warning' },
  success: { i18nKey: 'ota.success', color: 'success' },
  failed: { i18nKey: 'ota.failed', color: 'error' },
  cancelled: { i18nKey: 'ota.cancelled', color: 'default' },
  blocked: { i18nKey: 'ota.statusBlocked', color: 'orange' },
  skipped: { i18nKey: 'ota.statusSkipped', color: 'default' },
}

function extractItems(res: any): Device[] {
  const d = res?.data?.data ?? res?.data ?? {}
  const list = d?.items ?? (Array.isArray(d) ? d : [])
  return Array.isArray(list) ? list : []
}

const DeviceFirmwareUpgradeTab: React.FC = () => {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { timezone } = useTimezoneStore()
  const isSystemAdmin = useAuthStore((s) => s.user?.isSystemAdmin === true)
  const hasAnyPermission = useAuthStore((s) => s.hasAnyPermission)
  const canControl = canControlDeviceFirmware(isSystemAdmin, hasAnyPermission)

  const [selectedSn, setSelectedSn] = useState<string | null>(null)
  const [deviceSearch, setDeviceSearch] = useState('')
  const [historyPage, setHistoryPage] = useState(1)
  const [historyPageSize, setHistoryPageSize] = useState(10)
  const [upgradeOpen, setUpgradeOpen] = useState(false)
  const [upgradeTarget, setUpgradeTarget] = useState<FirmwareModuleOverview | null>(null)
  const [selectedFirmwareId, setSelectedFirmwareId] = useState<number | null>(null)
  const [forceReason, setForceReason] = useState('')
  const [rollbackOpen, setRollbackOpen] = useState(false)
  const [rollbackResource, setRollbackResource] = useState<FirmwareResource | null>(null)
  const resourcesNeeded = upgradeOpen || rollbackOpen

  const { data: devices = [], isLoading: devicesLoading, error: devicesError, refetch: refetchDevices } = useQuery({
    queryKey: ['devices', 'all'],
    queryFn: () => deviceApi.getAll().then(extractItems),
  })

  const filteredDevices = useMemo(() => {
    const q = deviceSearch.trim().toLowerCase()
    if (!q) return devices
    return devices.filter(
      (d) => d.sn?.toLowerCase().includes(q) || d.model?.toLowerCase().includes(q),
    )
  }, [devices, deviceSearch])
  const selectedDevice = useMemo(
    () => devices.find((device) => device.sn === selectedSn),
    [devices, selectedSn],
  )

  const {
    data: overview,
    isLoading: overviewLoading,
    error: overviewError,
    refetch: refetchOverview,
  } = useQuery({
    queryKey: queryKeys.ota.firmwareOverview(selectedSn ?? ''),
    queryFn: () =>
      otaApi.getFirmwareOverview(selectedSn!).then((r) => {
        const d = r.data?.data ?? r.data ?? {}
        return d as DeviceFirmwareOverview
      }),
    enabled: !!selectedSn,
  })

  const {
    data: resources = [],
    isLoading: resourcesLoading,
    error: resourcesError,
    refetch: refetchResources,
  } = useQuery({
    queryKey: queryKeys.ota.firmwareResources(selectedSn ?? '', upgradeTarget?.target),
    queryFn: () =>
      otaApi.getFirmwareResources(selectedSn!, upgradeTarget?.target).then((r) => {
        const d = r.data?.data ?? r.data ?? {}
        const list = d?.items ?? (Array.isArray(d) ? d : [])
        return (Array.isArray(list) ? list : []) as FirmwareResource[]
      }),
    enabled: !!selectedSn && resourcesNeeded,
  })

  const {
    data: historyRes,
    isLoading: historyLoading,
    error: historyError,
    refetch: refetchHistory,
  } = useQuery({
    queryKey: queryKeys.ota.deviceHistory(selectedSn ?? '', {
      page: historyPage,
      page_size: historyPageSize,
    }),
    queryFn: () =>
      otaApi
        .getDeviceUpgradeHistory(selectedSn!, { page: historyPage, page_size: historyPageSize })
        .then((r) => {
          const d = r.data?.data ?? r.data ?? {}
          const items = d?.items ?? []
          return {
            items: (Array.isArray(items) ? items : []) as DeviceUpgrade[],
            total: (d?.total ?? 0) as number,
          }
        }),
    enabled: !!selectedSn,
  })

  const invalidateDevice = () => {
    if (!selectedSn) return
    queryClient.invalidateQueries({ queryKey: queryKeys.ota.firmwareOverview(selectedSn) })
    queryClient.invalidateQueries({ queryKey: ['ota', 'firmware-resources', selectedSn] })
    queryClient.invalidateQueries({ queryKey: queryKeys.ota.deviceHistory(selectedSn) })
  }

  const triggerMutation = useMutation({
    mutationFn: (data: { device_sn: string; firmware_ids: number[]; idempotency_key: string; force_reason?: string }) =>
      otaApi.triggerFirmwareUpgrade(data),
    onSuccess: () => {
      message.success(t('ota.triggerSuccess'))
      setUpgradeOpen(false)
      setUpgradeTarget(null)
      setSelectedFirmwareId(null)
      setForceReason('')
      invalidateDevice()
    },
    onError: (err: any) => {
      const code = err?.response?.data?.error || err?.response?.data?.code
      const msg =
        code === 'legacy_package_retired'
          ? t('ota.legacyPackageRetired')
          : err?.response?.data?.message || err?.message || t('ota.triggerFailed')
      message.error(msg)
    },
  })

  const rollbackMutation = useMutation({
    mutationFn: (data: { device_sn: string; firmware_id: number; idempotency_key: string; force_reason?: string }) =>
      otaApi.rollbackFirmware(data),
    onSuccess: () => {
      message.success(t('ota.triggerSuccess'))
      setRollbackOpen(false)
      setRollbackResource(null)
      setForceReason('')
      invalidateDevice()
    },
    onError: (err: any) => message.error(err?.response?.data?.message || err?.message || t('ota.triggerFailed')),
  })

  const openUpgrade = (mod: FirmwareModuleOverview) => {
    setUpgradeTarget(mod)
    setSelectedFirmwareId(null)
    setForceReason('')
    setUpgradeOpen(true)
  }

  const handleUpgradeOne = () => {
    if (!selectedSn || !selectedFirmwareId) {
      message.warning(t('ota.selectFirmwareToUpgrade'))
      return
    }
    triggerMutation.mutate({
      device_sn: selectedSn,
      firmware_ids: [selectedFirmwareId],
      idempotency_key: createOtaIdempotencyKey('trigger'),
      force_reason: forceReason || undefined,
    })
  }

  const handleUpgradeAll = () => {
    if (!selectedSn || !overview?.modules) return
    const ids = overview.modules
      .filter((m) => m.update_available && m.latest_firmware_id && canRemoteUpgradeFirmwareModule(m))
      .map((m) => Number(m.latest_firmware_id))
      .filter((id) => Number.isFinite(id) && id > 0)
    if (ids.length === 0) {
      message.info(t('ota.moduleNoUpdate'))
      return
    }
    Modal.confirm({
      title: t('ota.confirmUpgradeAllModules'),
      onOk: () => {
        triggerMutation.mutate({
          device_sn: selectedSn,
          firmware_ids: ids,
          idempotency_key: createOtaIdempotencyKey('trigger'),
        })
      },
    })
  }

  const handleRollback = () => {
    if (!selectedSn || !rollbackResource) return
    rollbackMutation.mutate({
      device_sn: selectedSn,
      firmware_id: Number(rollbackResource.id),
      idempotency_key: createOtaIdempotencyKey('rollback'),
      force_reason: forceReason || undefined,
    })
  }

  const historyColumns: ColumnsType<DeviceUpgrade> = [
    {
      title: t('ota.module'),
      dataIndex: 'target_chip',
      key: 'target_chip',
      width: 110,
      render: (v: string) => firmwareModuleLabel(v, t),
    },
    { title: t('ota.oldVersion'), dataIndex: 'old_version', key: 'old_version', width: 110, render: (v: string) => v || '-' },
    { title: t('ota.firmwareVersion'), dataIndex: 'firmware_version', key: 'firmware_version', width: 110 },
    {
      title: t('common.status'),
      dataIndex: 'status',
      key: 'status',
      width: 100,
      render: (s: string) => {
        const cfg = UPGRADE_STATUS_MAP[s]
        return <Tag color={cfg?.color || 'default'}>{cfg ? t(cfg.i18nKey) : s}</Tag>
      },
    },
    { title: t('ota.progress'), dataIndex: 'progress', key: 'progress', width: 80, render: (v: number) => `${v ?? 0}%` },
    {
      title: t('ota.executeTime'),
      dataIndex: 'started_at',
      key: 'started_at',
      width: 160,
      render: (v: string, r) =>
        v
          ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss')
          : r.created_at
            ? formatInTimezone(r.created_at, timezone, 'YYYY-MM-DD HH:mm:ss')
            : '-',
    },
    {
      title: t('ota.completeTime'),
      dataIndex: 'completed_at',
      key: 'completed_at',
      width: 160,
      render: (v: string) => (v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'),
    },
    {
      title: t('ota.errorInfo'),
      dataIndex: 'error_message',
      key: 'error_message',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
  ]

  const queryFailure = devicesError
    ? { error: devicesError, retry: refetchDevices }
    : overviewError
      ? { error: overviewError, retry: refetchOverview }
      : historyError
        ? { error: historyError, retry: refetchHistory }
        : null

  const modules = overview?.modules ?? []
  const upgradeableCount = modules.filter((m) => m.update_available && canRemoteUpgradeFirmwareModule(m)).length

  return (
    <div>
      {queryFailure && (
        <QueryErrorAlert
          error={queryFailure.error}
          onRetry={() => void queryFailure.retry()}
          style={{ marginBottom: 16 }}
        />
      )}
      <Row gutter={[16, 16]}>
        {/* 设备选择栏 */}
        <Col xs={24} md={7} lg={6}>
          <Card
            size="small"
            title={
              <Space>
                <DesktopOutlined />
                <span>{t('ota.selectDevice')}</span>
              </Space>
            }
            extra={
              <Button icon={<ReloadOutlined />} size="small" type="text" onClick={() => refetchDevices()}>
                {t('common.refresh')}
              </Button>
            }
            styles={{ body: { padding: 12 } }}
          >
            <Input
              allowClear
              prefix={<SearchOutlined />}
              placeholder={t('ota.filterByDeviceSn')}
              style={{ marginBottom: 12 }}
              value={deviceSearch}
              onChange={(e) => setDeviceSearch(e.target.value)}
            />
            <div style={{ maxHeight: 520, overflow: 'auto' }}>
              <List
                size="small"
                loading={devicesLoading}
                dataSource={filteredDevices}
                locale={{ emptyText: <Empty description={t('ota.noDeviceData')} image={Empty.PRESENTED_IMAGE_SIMPLE} /> }}
                pagination={{ pageSize: 8, size: 'small', hideOnSinglePage: false }}
                renderItem={(device) => {
                  const active = device.sn === selectedSn
                  return (
                    <List.Item
                      onClick={() => {
                        setSelectedSn(device.sn)
                        setHistoryPage(1)
                      }}
                      style={{
                        cursor: 'pointer',
                        padding: '10px 12px',
                        borderRadius: 8,
                        marginBottom: 6,
                        background: active ? '#e6f4ff' : '#fafafa',
                        border: active ? '1px solid #91caff' : '1px solid transparent',
                      }}
                    >
                      <div style={{ width: '100%' }}>
                        <Flex justify="space-between" align="center" gap={8}>
                          <Text strong ellipsis style={{ maxWidth: '70%' }}>
                            {device.alias || device.name || device.model || device.sn}
                          </Text>
                          <Tag color={device.status === 'online' ? 'success' : 'default'} style={{ marginRight: 0 }}>
                            {device.status === 'online' ? t('ota.online') : t('ota.offline')}
                          </Tag>
                        </Flex>
                        <div style={{ marginTop: 2, display: 'flex', gap: 6 }}>
                          <Text type="secondary" style={{ fontSize: 12 }}>
                            {device.sn}
                          </Text>
                          {device.model && (
                            <Text type="secondary" style={{ fontSize: 12 }}>
                              · {device.model}
                            </Text>
                          )}
                        </div>
                      </div>
                    </List.Item>
                  )
                }}
              />
            </div>
          </Card>
        </Col>

        {/* 设备固件详情 */}
        <Col xs={24} md={17} lg={18}>
          {!selectedSn ? (
            <Card size="small" styles={{ body: { padding: 48 } }}>
              <Empty description={t('ota.selectDeviceHint')} />
            </Card>
          ) : (
            <Space direction="vertical" size={16} style={{ width: '100%' }}>
              {/* 设备信息 + 总览统计 */}
              <Card
                size="small"
                title={
                  <Space wrap>
                    <DesktopOutlined />
                    <Text strong>{selectedSn}</Text>
                    {overview?.device_model && <Tag>{overview.device_model}</Tag>}
                    {overview && (
                      <Tag color={overview.is_online ? 'success' : 'default'}>
                        {overview.is_online ? t('ota.online') : t('ota.offline')}
                      </Tag>
                    )}
                  </Space>
                }
                extra={
                  <Space wrap>
                    <Button
                      icon={<CheckCircleOutlined />}
                      size="small"
                      loading={overviewLoading}
                      onClick={() => refetchOverview()}
                    >
                      {t('ota.checkUpdates')}
                    </Button>
                    {canControl && (
                      <Button
                        type="primary"
                        size="small"
                        icon={<RocketOutlined />}
                        disabled={upgradeableCount === 0}
                        onClick={handleUpgradeAll}
                      >
                        {t('ota.upgradeAllModules')}
                      </Button>
                    )}
                  </Space>
                }
              >
                <Row gutter={[16, 12]} style={{ marginBottom: 12 }}>
                  <Col xs={12} sm={6}>
                    <Statistic
                      title={t('ota.model')}
                      value={selectedDevice?.model || overview?.device_model || '-'}
                      valueStyle={{ fontSize: 16 }}
                    />
                  </Col>
                  <Col xs={12} sm={6}>
                    <Statistic
                      title={t('dev.hardwareVersion')}
                      value={selectedDevice?.hardware_version || selectedDevice?.hardwareVersion || '-'}
                      valueStyle={{ fontSize: 16 }}
                    />
                  </Col>
                  <Col xs={12} sm={6}>
                    <Statistic title={t('ota.module')} value={`${modules.length}`} valueStyle={{ fontSize: 16 }} />
                  </Col>
                  <Col xs={12} sm={6}>
                    <Statistic
                      title={t('ota.moduleUpdateAvailable')}
                      value={`${upgradeableCount}`}
                      valueStyle={{ fontSize: 16, color: upgradeableCount > 0 ? '#fa8c16' : undefined }}
                    />
                  </Col>
                </Row>
                <Descriptions column={{ xs: 1, sm: 2 }} size="small">
                  <Descriptions.Item label={t('dev.deviceName')}>
                    {selectedDevice?.alias || selectedDevice?.name || selectedDevice?.model || selectedSn}
                  </Descriptions.Item>
                  <Descriptions.Item label={t('dev.deviceSN')}>{selectedSn}</Descriptions.Item>
                </Descriptions>
              </Card>

              {/* 模块固件总览 */}
              <Card
                size="small"
                title={t('ota.deviceFirmwareOverview')}
                loading={overviewLoading}
                styles={{ body: { padding: 12 } }}
              >
                {modules.length === 0 ? (
                  <Empty description={t('ota.noFirmwareResources')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
                ) : (
                  <Row gutter={[12, 12]}>
                    {modules.map((mod) => {
                      const state = VERSION_STATE_MAP[mod.version_state]
                      const canUpgrade = canControl && mod.update_available && canRemoteUpgradeFirmwareModule(mod)
                      return (
                        <Col xs={24} sm={12} xl={8} key={mod.target || mod.latest_firmware_id}>
                          <Card
                            size="small"
                            variant="outlined"
                            styles={{
                              body: {
                                background: mod.update_available ? '#fffbe6' : undefined,
                                borderRadius: 8,
                              },
                            }}
                          >
                            <Flex vertical gap={8}>
                              <Flex justify="space-between" align="center">
                                <Text strong>{firmwareModuleLabel(mod.target, t)}</Text>
                                <Tag color={state?.color || 'default'} style={{ marginRight: 0 }}>
                                  {state ? t(state.i18nKey) : mod.version_state}
                                </Tag>
                              </Flex>
                              <Flex vertical gap={2}>
                                <Flex justify="space-between">
                                  <Text type="secondary">{t('ota.moduleCurrentVersion')}</Text>
                                  <Text>{mod.current_version || '-'}</Text>
                                </Flex>
                                <Flex justify="space-between">
                                  <Text type="secondary">{t('ota.moduleLatestVersion')}</Text>
                                  <Text>{mod.latest_version || '-'}</Text>
                                </Flex>
                              </Flex>
                              {mod.changelog && (
                                <Text type="secondary" style={{ fontSize: 12 }} ellipsis={{ tooltip: mod.changelog }}>
                                  {mod.changelog}
                                </Text>
                              )}
                              <Flex gap={8} wrap>
                                {canUpgrade && (
                                  <Button
                                    type="primary"
                                    size="small"
                                    icon={<CloudUploadOutlined />}
                                    onClick={() => openUpgrade(mod)}
                                  >
                                    {t('ota.upgradeModule')}
                                  </Button>
                                )}
                                {canControl && (
                                  <Button
                                    size="small"
                                    icon={<RollbackOutlined />}
                                    onClick={() => {
                                      setUpgradeTarget(mod)
                                      setForceReason('')
                                      setRollbackOpen(true)
                                      setRollbackResource(null)
                                    }}
                                  >
                                    {t('ota.rollbackFirmware')}
                                  </Button>
                                )}
                              </Flex>
                            </Flex>
                          </Card>
                        </Col>
                      )
                    })}
                  </Row>
                )}
              </Card>

              {/* 本机升级历史 */}
              <Card
                size="small"
                title={t('ota.upgradeHistory')}
                extra={
                  <Button size="small" icon={<ReloadOutlined />} onClick={() => refetchHistory()}>
                    {t('common.refresh')}
                  </Button>
                }
              >
                {historyError && (
                  <QueryErrorAlert
                    error={historyError}
                    onRetry={() => void refetchHistory()}
                    style={{ marginBottom: 12 }}
                  />
                )}
                <Table<DeviceUpgrade>
                  rowKey={(r) => `${r.id}`}
                  size="small"
                  loading={historyLoading}
                  columns={historyColumns}
                  dataSource={historyRes?.items ?? []}
                  scroll={{ x: 1000 }}
                  pagination={{
                    current: historyPage,
                    pageSize: historyPageSize,
                    total: historyRes?.total ?? 0,
                    showSizeChanger: true,
                    onChange: (p, ps) => {
                      setHistoryPage(p)
                      setHistoryPageSize(ps)
                    },
                  }}
                  locale={{ emptyText: <Empty description={t('ota.noUpgradeHistory')} image={Empty.PRESENTED_IMAGE_SIMPLE} /> }}
                />
              </Card>
            </Space>
          )}
        </Col>
      </Row>

      {/* 单模块升级 Modal */}
      <Modal
        title={`${t('ota.upgradeModule')} · ${upgradeTarget ? firmwareModuleLabel(upgradeTarget.target, t) : ''}`}
        open={upgradeOpen}
        onCancel={() => {
          setUpgradeOpen(false)
          setUpgradeTarget(null)
          setSelectedFirmwareId(null)
          setForceReason('')
        }}
        onOk={handleUpgradeOne}
        confirmLoading={triggerMutation.isPending}
        destroyOnClose
        width={520}
        okButtonProps={{ disabled: !canControl || !selectedFirmwareId }}
      >
        {resourcesError && (
          <QueryErrorAlert error={resourcesError} onRetry={() => void refetchResources()} style={{ marginBottom: 12 }} />
        )}
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <div>
            <div style={{ marginBottom: 4 }}>{t('ota.selectFirmwareToUpgrade')}</div>
            <Select
              style={{ width: '100%' }}
              placeholder={t('ota.selectFirmwareToUpgrade')}
              loading={resourcesLoading}
              value={selectedFirmwareId}
              onChange={setSelectedFirmwareId}
              options={resources.map((fw) => ({
                label: fw.version,
                value: Number(fw.id),
              }))}
              notFoundContent={t('ota.noFirmwareResources')}
            />
          </div>
          <div>
            <div style={{ marginBottom: 4 }}>{t('ota.forceReason')}</div>
            <Input.TextArea
              rows={2}
              value={forceReason}
              onChange={(e) => setForceReason(e.target.value)}
              placeholder={t('ota.forceReasonPlaceholder')}
            />
          </div>
          {upgradeTarget?.current_version && (
            <Alert
              type="info"
              showIcon
              message={`${t('ota.moduleCurrentVersion')}: ${upgradeTarget.current_version}`}
            />
          )}
        </Space>
      </Modal>

      {/* 固件回退 Modal */}
      <Modal
        title={t('ota.rollbackFirmware')}
        open={rollbackOpen}
        onCancel={() => {
          setRollbackOpen(false)
          setRollbackResource(null)
          setForceReason('')
        }}
        onOk={handleRollback}
        confirmLoading={rollbackMutation.isPending}
        destroyOnClose
        width={520}
        okButtonProps={{ disabled: !canControl }}
      >
        {resourcesError && !upgradeOpen && (
          <QueryErrorAlert error={resourcesError} onRetry={() => void refetchResources()} style={{ marginBottom: 12 }} />
        )}
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <Alert type="warning" showIcon message={t('ota.confirmRollbackFirmware')} />
          <Select
            style={{ width: '100%' }}
            placeholder={t('ota.selectFirmwareToUpgrade')}
            loading={resourcesLoading && !upgradeOpen}
            value={rollbackResource ? Number(rollbackResource.id) : undefined}
            onChange={(id) => {
              const found = resources.find((fw) => Number(fw.id) === id) || null
              setRollbackResource(found)
            }}
            options={resources.map((fw) => ({
              label: fw.version,
              value: Number(fw.id),
            }))}
            notFoundContent={t('ota.noFirmwareResources')}
          />
          <Input.TextArea
            rows={2}
            value={forceReason}
            onChange={(e) => setForceReason(e.target.value)}
            placeholder={t('ota.forceReasonPlaceholder')}
          />
        </Space>
      </Modal>
    </div>
  )
}

export default DeviceFirmwareUpgradeTab
export { normalizeFirmwareTarget }
