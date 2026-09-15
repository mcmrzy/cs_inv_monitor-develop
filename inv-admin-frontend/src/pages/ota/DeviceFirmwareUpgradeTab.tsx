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
  Input,
  Modal,
  Row,
  Select,
  Space,
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
} from '@ant-design/icons'
import { otaApi, createOtaIdempotencyKey } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useAuthStore from '@/stores/authStore'
import useTranslation from '@/hooks/useTranslation'
import useTimezoneStore from '@/stores/timezoneStore'
import { formatInTimezone } from '@/utils/timezone'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { canMutateOta } from '@/router/routeAccess'
import {
  firmwareModuleLabel,
  normalizeFirmwareTarget,
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
  const canCreate = canMutateOta('create', isSystemAdmin, hasAnyPermission)
  const canControl = canMutateOta('control', isSystemAdmin, hasAnyPermission)
  const canDelete = canMutateOta('delete', isSystemAdmin, hasAnyPermission)

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
      .filter((m) => m.update_available && m.latest_firmware_id)
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
      title: t('ota.errorInfo'),
      dataIndex: 'error_message',
      key: 'error_message',
      ellipsis: true,
      render: (v: string) => v || '-',
    },
    {
      title: t('common.createdAt'),
      dataIndex: 'created_at',
      key: 'created_at',
      width: 160,
      render: (v: string) => (v ? formatInTimezone(v, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'),
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

  return (
    <div>
      {queryFailure && (
        <QueryErrorAlert
          error={queryFailure.error}
          onRetry={() => void queryFailure.retry()}
          style={{ marginBottom: 16 }}
        />
      )}
      <Row gutter={16}>
        <Col xs={24} md={8}>
          <Card
            size="small"
            title={t('ota.selectDevice')}
            extra={
              <Button icon={<ReloadOutlined />} size="small" onClick={() => refetchDevices()}>
                {t('common.refresh')}
              </Button>
            }
          >
            <Input.Search
              allowClear
              placeholder={t('ota.filterByDeviceSn')}
              style={{ marginBottom: 12 }}
              value={deviceSearch}
              onChange={(e) => setDeviceSearch(e.target.value)}
            />
            <Table<Device>
              rowKey="sn"
              size="small"
              loading={devicesLoading}
              dataSource={filteredDevices}
              pagination={{ pageSize: 8, size: 'small' }}
              locale={{ emptyText: <Empty description={t('ota.noDeviceData')} /> }}
              onRow={(record) => ({
                onClick: () => {
                  setSelectedSn(record.sn)
                  setHistoryPage(1)
                },
                style: { cursor: 'pointer', background: record.sn === selectedSn ? '#e6f4ff' : undefined },
              })}
              columns={[
                { title: 'SN', dataIndex: 'sn', key: 'sn', ellipsis: true },
                { title: t('ota.model'), dataIndex: 'model', key: 'model', width: 100 },
                {
                  title: t('common.status'),
                  dataIndex: 'status',
                  key: 'status',
                  width: 70,
                  render: (s: string) =>
                    s === 'online' ? (
                      <Tag color="success">{t('ota.online')}</Tag>
                    ) : (
                      <Tag>{t('ota.offline')}</Tag>
                    ),
                },
              ]}
            />
          </Card>
        </Col>
        <Col xs={24} md={16}>
          {!selectedSn ? (
            <Card size="small">
              <Empty description={t('ota.selectDeviceHint')} />
            </Card>
          ) : (
            <Space direction="vertical" size={16} style={{ width: '100%' }}>
              <Card
                size="small"
                title={
                  <Space>
                    <DesktopOutlined />
                    <span>{selectedSn}</span>
                    {overview?.device_model && <Tag>{overview.device_model}</Tag>}
                    {overview && (
                      <Tag color={overview.is_online ? 'success' : 'default'}>
                        {overview.is_online ? t('ota.online') : t('ota.offline')}
                      </Tag>
                    )}
                  </Space>
                }
                extra={
                  <Space>
                    <Button
                      icon={<CheckCircleOutlined />}
                      size="small"
                      onClick={() => refetchOverview()}
                    >
                      {t('ota.checkUpdates')}
                    </Button>
                    {canControl && (
                      <Button
                        type="primary"
                        size="small"
                        icon={<RocketOutlined />}
                        disabled={!modules.some((m) => m.update_available)}
                        onClick={handleUpgradeAll}
                      >
                        {t('ota.upgradeAllModules')}
                      </Button>
                    )}
                  </Space>
                }
              >
                <Title level={5} style={{ marginTop: 0 }}>
                  {t('ota.deviceFirmwareOverview')}
                </Title>
                <Row gutter={[12, 12]}>
                  {modules.length === 0 && (
                    <Col span={24}>
                      <Empty description={t('ota.noFirmwareResources')} />
                    </Col>
                  )}
                  {modules.map((mod) => {
                    const state = VERSION_STATE_MAP[mod.version_state]
                    return (
                      <Col xs={24} sm={12} key={mod.target || mod.latest_firmware_id}>
                        <Card size="small" variant="outlined">
                          <Space direction="vertical" size={6} style={{ width: '100%' }}>
                            <Space style={{ justifyContent: 'space-between', width: '100%' }}>
                              <Text strong>{firmwareModuleLabel(mod.target, t)}</Text>
                              <Tag color={state?.color || 'default'}>
                                {state ? t(state.i18nKey) : mod.version_state}
                              </Tag>
                            </Space>
                            <Descriptions column={1} size="small">
                              <Descriptions.Item label={t('ota.moduleCurrentVersion')}>
                                {mod.current_version || '-'}
                              </Descriptions.Item>
                              <Descriptions.Item label={t('ota.moduleLatestVersion')}>
                                {mod.latest_version || '-'}
                              </Descriptions.Item>
                            </Descriptions>
                            {mod.changelog && (
                              <Text type="secondary" style={{ fontSize: 12 }} ellipsis={{ tooltip: mod.changelog }}>
                                {mod.changelog}
                              </Text>
                            )}
                            <Space>
                              {canControl && mod.update_available && (
                                <Button
                                  type="primary"
                                  size="small"
                                  icon={<CloudUploadOutlined />}
                                  onClick={() => openUpgrade(mod)}
                                >
                                  {t('ota.upgradeModule')}
                                </Button>
                              )}
                              {canDelete && (
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
                            </Space>
                          </Space>
                        </Card>
                      </Col>
                    )
                  })}
                </Row>
              </Card>

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
                  scroll={{ x: 800 }}
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
                  locale={{ emptyText: <Empty description={t('ota.noUpgradeHistory')} /> }}
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
        okButtonProps={{ disabled: !canCreate }}
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
