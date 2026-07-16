import React, { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Card, Row, Col, Tag, Typography, Spin, Empty, Tooltip, Space,
} from 'antd'
import {
  ThunderboltOutlined, ClockCircleOutlined, WifiOutlined,
  DisconnectOutlined, CheckCircleOutlined, StopOutlined,
  CodeOutlined, InboxOutlined,
} from '@ant-design/icons'
import { modelApi } from '@/services/modelApi'
import type { ModelCommandCapability } from '@/services/modelApi'
import type { ParameterSchema } from '@/types'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import { DS, RISK_GRADIENTS } from '../types'

const { Text } = Typography

/* ==================== Helpers ==================== */

const RISK_TAG_MAP: Record<number, { color: string; label: string; bg: string }> = {
  1: { color: DS.success, label: 'R1 Low', bg: '#ecfdf5' },
  2: { color: DS.warning, label: 'R2 Medium', bg: '#fef3c7' },
  3: { color: DS.danger, label: 'R3 High', bg: '#fef2f2' },
}

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

/* ==================== Styles ==================== */

const cmdStyles = `
.cmd-card {
  border-radius: 16px !important;
  border: none !important;
  box-shadow: 0 2px 8px rgba(0,0,0,0.05), 0 4px 16px rgba(0,0,0,0.03);
  overflow: hidden;
  transition: all 0.28s cubic-bezier(0.4, 0, 0.2, 1);
  height: 100%;
  background: #fff;
}
.cmd-card:hover {
  box-shadow: 0 8px 28px rgba(79,70,229,0.13), 0 2px 8px rgba(0,0,0,0.05);
  transform: translateY(-4px);
}
.cmd-card .ant-card-body {
  padding: 0 !important;
}
.cmd-gradient-bar {
  height: 4px;
  width: 100%;
  border-radius: 16px 16px 0 0;
}
.cmd-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  margin-bottom: 16px;
  gap: 8px;
}
.cmd-icon-box {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(79,70,229,0.15);
}
.cmd-risk-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 24px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  box-shadow: 0 1px 3px rgba(0,0,0,0.05);
  flex-shrink: 0;
}
.cmd-param-area {
  background: #f6f8fa;
  border-radius: 12px;
  padding: 12px 16px;
  border: 1px solid ${DS.border};
  font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
}
.cmd-param-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 0;
  font-size: 12px;
}
.cmd-param-row + .cmd-param-row {
  border-top: 1px solid rgba(0,0,0,0.05);
  margin-top: 2px;
  padding-top: 6px;
}
.cmd-code-chip {
  font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
  font-size: 11px;
  background: rgba(79,70,229,0.08);
  color: ${DS.primary};
  padding: 3px 8px;
  border-radius: 5px;
  font-weight: 500;
  letter-spacing: 0.01em;
}
.cmd-status-tag {
  border-radius: 8px !important;
  font-size: 12px !important;
  font-weight: 500 !important;
  padding: 2px 10px !important;
}
.cmd-section-title {
  display: flex;
  align-items: center;
  gap: 7px;
  color: ${DS.textSecondary};
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.03em;
  margin-bottom: 10px;
  text-transform: uppercase;
}
`

/* ==================== CommandCard ==================== */

interface CommandCardProps {
  cmd: ModelCommandCapability
}

const CommandCard: React.FC<CommandCardProps> = ({ cmd }) => {
  const { t } = useTranslation()

  const schema = useMemo(() => parseSchema(cmd.parameter_schema), [cmd.parameter_schema])
  const args = schema?.args ?? []
  const riskCfg = RISK_TAG_MAP[cmd.risk_level] ?? RISK_TAG_MAP[1]
  const riskGradient = RISK_GRADIENTS[cmd.risk_level] ?? RISK_GRADIENTS[1]

  const displayName = cmd.display_name_key
    ? (t(cmd.display_name_key) !== cmd.display_name_key ? t(cmd.display_name_key) : cmd.display_name_key)
    : cmd.command_code

  return (
    <Card bordered={false} className="cmd-card" styles={{ body: { padding: 0 } }}>
      {/* Top gradient bar */}
      <div className="cmd-gradient-bar" style={{ background: riskGradient }} />

      <div style={{ padding: '18px 22px 22px' }}>
        {/* Card header */}
        <div className="cmd-header">
          <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
            <div className="cmd-icon-box" style={{ background: `linear-gradient(135deg, ${DS.primary}18, ${DS.secondary}20)` }}>
              <ThunderboltOutlined style={{ fontSize: 17, color: DS.primary }} />
            </div>
            <div>
              <Text strong style={{ fontSize: 15, color: DS.textPrimary, lineHeight: 1.4, display: 'block' }}>
                {displayName}
              </Text>
              <code style={{
                fontSize: 11,
                color: DS.textMuted,
                fontFamily: "'SF Mono', 'Monaco', 'Inconsolata', monospace",
                background: DS.bgCode,
                padding: '1px 6px',
                borderRadius: 4,
                border: `1px solid ${DS.border}`,
              }}>
                {cmd.command_code}
              </code>
            </div>
          </div>
          <div className="cmd-risk-badge" style={{ background: riskCfg.bg, color: riskCfg.color }}>
            {riskCfg.label}
          </div>
        </div>

        {/* Status tags row */}
        <Space wrap size={[6, 6]} style={{ marginBottom: args.length > 0 ? 16 : 0 }}>
          <Tooltip title={cmd.requires_online ? t('remoteSettings.requiresOnlineYes') : t('remoteSettings.requiresOnlineNo')}>
            <Tag
              className="cmd-status-tag"
              icon={cmd.requires_online ? <WifiOutlined /> : <DisconnectOutlined />}
              color={cmd.requires_online ? 'blue' : 'default'}
              style={{ marginInlineEnd: 0 }}
            >
              {cmd.requires_online ? t('remoteSettings.requiresOnline') : t('remoteSettings.offlineOk')}
            </Tag>
          </Tooltip>
          <Tag
            className="cmd-status-tag"
            icon={cmd.is_enabled ? <CheckCircleOutlined /> : <StopOutlined />}
            color={cmd.is_enabled ? 'green' : 'default'}
            style={{ marginInlineEnd: 0 }}
          >
            {cmd.is_enabled ? t('remoteSettings.enabled') : t('remoteSettings.disabled')}
          </Tag>
          <Tag
            className="cmd-status-tag"
            icon={<ClockCircleOutlined />}
            style={{ marginInlineEnd: 0 }}
          >
            {cmd.timeout_seconds}s
          </Tag>
        </Space>

        {/* Parameter schema preview */}
        {args.length > 0 && (
          <div>
            <div className="cmd-section-title">
              <CodeOutlined />
              <span>{t('remoteSettings.parameters')} ({args.length})</span>
            </div>
            <div className="cmd-param-area" style={{ maxHeight: 150, overflow: 'auto' }}>
              {args.map((arg) => (
                <div key={arg.key} className="cmd-param-row">
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                    <span className="cmd-code-chip">{arg.key}</span>
                    <span style={{ color: DS.textMuted, fontSize: 11, fontStyle: 'italic' }}>{arg.type}</span>
                  </div>
                  <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
                    {arg.required && (
                      <Tag
                        color="red"
                        style={{
                          fontSize: 10,
                          lineHeight: '18px',
                          borderRadius: 10,
                          margin: 0,
                          padding: '0 8px',
                          fontWeight: 600,
                        }}
                      >
                        {t('remoteSettings.required')}
                      </Tag>
                    )}
                    {arg.unit && (
                      <Tag
                        style={{
                          fontSize: 10,
                          lineHeight: '18px',
                          borderRadius: 10,
                          margin: 0,
                          padding: '0 8px',
                          border: `1px solid ${DS.border}`,
                          color: DS.textSecondary,
                        }}
                      >
                        {arg.unit}
                      </Tag>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {args.length === 0 && (
          <Text type="secondary" style={{ fontSize: 12, color: DS.textMuted }}>
            {t('remoteSettings.noParameters')}
          </Text>
        )}
      </div>
    </Card>
  )
}

/* ==================== CommandTab ==================== */

interface CommandTabProps {
  modelId: number
}

const CommandTab: React.FC<CommandTabProps> = ({ modelId }) => {
  const { t } = useTranslation()

  const {
    data: commands,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: ['model-commands', modelId],
    queryFn: () =>
      modelApi.getCommandCapabilities(modelId).then((r) => {
        const d = r.data?.data ?? r.data
        return (Array.isArray(d) ? d : []) as ModelCommandCapability[]
      }),
    staleTime: 30000,
  })

  if (isLoading) {
    return (
      <div style={{ textAlign: 'center', padding: 60 }}>
        <Spin tip={t('remoteSettings.loading')} />
      </div>
    )
  }

  if (error) {
    return (
      <QueryErrorAlert
        error={error}
        onRetry={() => { void refetch() }}
        style={{ margin: 16 }}
      />
    )
  }

  if (!commands || commands.length === 0) {
    return (
      <div style={{ padding: 60, textAlign: 'center' }}>
        <Empty
          image={<InboxOutlined style={{ fontSize: 48, color: DS.textMuted }} />}
          description={
            <span style={{ color: DS.textSecondary, fontSize: 14 }}>
              {t('remoteSettings.noCommands')}
            </span>
          }
        />
      </div>
    )
  }

  return (
    <>
      <style>{cmdStyles}</style>
      <Row gutter={[18, 18]} style={{ padding: '0 0 16px' }}>
        {commands.map((cmd) => (
          <Col key={cmd.id} xs={24} sm={24} md={12} lg={8}>
            <CommandCard cmd={cmd} />
          </Col>
        ))}
      </Row>
    </>
  )
}

export default CommandTab
