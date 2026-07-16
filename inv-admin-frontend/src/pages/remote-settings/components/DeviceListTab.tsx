import React from 'react'
import { useQuery } from '@tanstack/react-query'
import { Table, Tag, Typography, Empty } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { WifiOutlined, DisconnectOutlined, CopyOutlined, InboxOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import { DEVICE_STATUS_MAP } from '@/utils/constants'
import { formatInTimezone } from '@/utils/timezone'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { DS } from '../types'

const { Text } = Typography

/* ==================== Types ==================== */

interface DeviceRecord {
  id: string
  sn: string
  model: string
  model_name?: string
  status: number
  last_online_at?: string
  firmware_version?: string
  firmware_dsp?: string
  firmware_bms?: string
  timezone?: string
}

/* ==================== Styles ==================== */

const pulseStyle = `
@keyframes rs-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.7); }
  50%  { box-shadow: 0 0 0 10px rgba(16, 185, 129, 0.18); }
  100% { box-shadow: 0 0 0 0 rgba(16, 185, 129, 0); }
}
@keyframes rs-breathe {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.75; }
}
.rs-dot {
  display: inline-block;
  width: 11px;
  height: 11px;
  border-radius: 50%;
  margin-right: 9px;
  vertical-align: middle;
}
.rs-dot--online {
  background: ${DS.success};
  animation: rs-pulse 2s infinite, rs-breathe 3s infinite ease-in-out;
}
.rs-dot--offline {
  background: #d1d5db;
}
.dl-table .ant-table {
  border-radius: 14px !important;
}
.dl-table .ant-table-thead > tr > th {
  background: #f0f2f5 !important;
  font-weight: 700 !important;
  font-size: 12px !important;
  color: #4b5563 !important;
  border-bottom: none !important;
  padding: 14px 16px !important;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.dl-table .ant-table-tbody > tr > td {
  padding: 14px 16px !important;
  transition: background 0.15s ease;
  vertical-align: middle !important;
}
.dl-table .ant-table-tbody > tr:hover > td {
  background: #f0f5ff !important;
}
.dl-table .ant-table-container {
  border-radius: 14px;
  overflow: hidden;
  border: 1px solid ${DS.border};
}
.dl-table .ant-pagination {
  padding: 14px 16px !important;
}
.dl-sn-text {
  font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
  font-size: 13px;
  font-weight: 600;
  color: ${DS.textPrimary};
  letter-spacing: 0.03em;
  background: ${DS.bgCode};
  padding: 2px 8px;
  border-radius: 6px;
  border: 1px solid ${DS.border};
}
.dl-sn-copy {
  color: ${DS.textMuted};
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 12px;
  margin-left: 7px;
  padding: 3px;
  border-radius: 4px;
}
.dl-sn-copy:hover {
  color: ${DS.primary};
  background: ${DS.primaryLight};
}
.dl-status-tag {
  border-radius: 8px !important;
  font-weight: 600 !important;
  padding: 2px 10px !important;
}
.dl-fw-tag {
  border-radius: 8px !important;
  font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace !important;
  font-size: 12px !important;
  font-weight: 500 !important;
  padding: 2px 10px !important;
}
.dl-model-text {
  font-size: 13px;
  color: ${DS.textPrimary};
  font-weight: 500;
}
.dl-time-text {
  font-size: 13px;
  color: ${DS.textPrimary};
}
`

/* ==================== DeviceListTab ==================== */

interface DeviceListTabProps {
  modelId: number
}

const DeviceListTab: React.FC<DeviceListTabProps> = ({ modelId }) => {
  const { t } = useTranslation()

  const {
    data: devices,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: ['model-devices', modelId],
    queryFn: () =>
      deviceApi.getDevices({ model_id: modelId, page_size: 999 }).then((r) => {
        const d = r.data?.data ?? r.data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as DeviceRecord[]
      }),
    staleTime: 30000,
  })

  const columns: ColumnsType<DeviceRecord> = [
    {
      title: t('remoteSettings.deviceSN'),
      dataIndex: 'sn',
      key: 'sn',
      width: 220,
      render: (sn: string) => (
        <div style={{ display: 'inline-flex', alignItems: 'center' }}>
          <span className="dl-sn-text">{sn}</span>
          <CopyOutlined
            className="dl-sn-copy"
            onClick={() => { navigator.clipboard.writeText(sn) }}
          />
        </div>
      ),
    },
    {
      title: t('remoteSettings.onlineStatus'),
      dataIndex: 'status',
      key: 'status',
      width: 140,
      filters: [
        { text: t('common.online'), value: 1 },
        { text: t('common.offline'), value: 0 },
      ],
      onFilter: (value, record) => record.status === value,
      render: (status: number) => {
        const isOnline = status === 1
        const cfg = DEVICE_STATUS_MAP[String(status)] ?? DEVICE_STATUS_MAP['0']
        return (
          <span style={{ display: 'inline-flex', alignItems: 'center' }}>
            <span className={`rs-dot ${isOnline ? 'rs-dot--online' : 'rs-dot--offline'}`} />
            <Tag
              color={cfg.color}
              icon={isOnline ? <WifiOutlined /> : <DisconnectOutlined />}
              className="dl-status-tag"
              style={{ marginInlineEnd: 0 }}
            >
              {t(cfg.i18nKey)}
            </Tag>
          </span>
        )
      },
    },
    {
      title: t('remoteSettings.lastOnline'),
      dataIndex: 'last_online_at',
      key: 'last_online_at',
      width: 210,
      sorter: (a, b) => (a.last_online_at ?? '').localeCompare(b.last_online_at ?? ''),
      render: (val: string | undefined, record: DeviceRecord) =>
        val ? (
          <Text className="dl-time-text">
            {formatInTimezone(val, record.timezone)}
          </Text>
        ) : <Text type="secondary" style={{ color: DS.textMuted }}>—</Text>,
    },
    {
      title: t('remoteSettings.firmwareVersion'),
      key: 'firmware',
      width: 160,
      render: (_: unknown, record: DeviceRecord) => {
        const fw = record.firmware_version ?? record.firmware_dsp
        return fw
          ? <Tag color="blue" className="dl-fw-tag">{fw}</Tag>
          : <Text type="secondary" style={{ color: DS.textMuted }}>—</Text>
      },
    },
    {
      title: t('remoteSettings.modelName'),
      dataIndex: 'model',
      key: 'model',
      width: 160,
      render: (model: string, record: DeviceRecord) =>
        <Text className="dl-model-text">{record.model_name ?? model ?? '—'}</Text>,
    },
  ]

  return (
    <>
      <style>{pulseStyle}</style>
      {error ? (
        <QueryErrorAlert
          error={error}
          onRetry={() => { void refetch() }}
          style={{ margin: 16 }}
        />
      ) : (
        <div className="dl-table">
          <Table<DeviceRecord>
            rowKey={(r) => r.id ?? r.sn}
            columns={columns}
            dataSource={devices ?? []}
            loading={isLoading}
            size="middle"
            pagination={{ pageSize: 20, showSizeChanger: false }}
            locale={{
              emptyText: (
                <div style={{ padding: '60px 0' }}>
                  <Empty
                    image={<InboxOutlined style={{ fontSize: 48, color: DS.textMuted }} />}
                    description={
                      <span style={{ color: DS.textSecondary, fontSize: 14 }}>
                        {t('remoteSettings.noDevices')}
                      </span>
                    }
                  />
                </div>
              ),
            }}
          />
        </div>
      )}
    </>
  )
}

export default DeviceListTab
