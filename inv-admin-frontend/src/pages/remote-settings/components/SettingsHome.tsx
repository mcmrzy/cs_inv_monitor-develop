// 第一层：设置首页（Dashboard 卡片式）——每个模块一张卡片，显示模块名 + 关键值摘要

import React from 'react'
import { Row, Col, Typography, Spin } from 'antd'
import {
  RightOutlined, ControlOutlined, ExperimentOutlined, ThunderboltOutlined,
  ExportOutlined, PoweroffOutlined, BulbOutlined, ToolOutlined, AlertOutlined,
  CodeOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import { MODULES } from '../config/fields'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { useFieldFormatter } from '../hooks/useFieldFormatter'

const { Text } = Typography

const MODULE_ICONS: Record<string, React.ReactNode> = {
  mode: <ControlOutlined />,
  battery: <ExperimentOutlined />,
  charge: <ThunderboltOutlined />,
  discharge: <ExportOutlined />,
  output: <PoweroffOutlined />,
  solar: <BulbOutlined />,
  generator: <ToolOutlined />,
  alarm: <AlertOutlined />,
}

interface SettingsHomeProps {
  cfg: DeviceConfigApi
  loading: boolean
  onOpenModule: (moduleId: string) => void
  onOpenAdvanced: () => void
}

const SettingsHome: React.FC<SettingsHomeProps> = ({ cfg, loading, onOpenModule, onOpenAdvanced }) => {
  const { t } = useTranslation()
  const formatValue = useFieldFormatter(cfg)

  return (
    <Spin spinning={loading}>
      <Row gutter={[16, 16]}>
        {MODULES.map((m) => (
          <Col key={m.id} xs={24} sm={12} xl={8} xxl={6}>
            <div
              role="button"
              tabIndex={0}
              onClick={() => onOpenModule(m.id)}
              onKeyDown={(e) => e.key === 'Enter' && onOpenModule(m.id)}
              style={{
                background: '#fff', borderRadius: 16, padding: 18,
                border: '1px solid #edf0f5', cursor: 'pointer',
                boxShadow: '0 1px 4px rgba(17,24,39,0.05)',
                transition: 'all 0.2s ease', height: '100%',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.transform = 'translateY(-2px)'
                e.currentTarget.style.boxShadow = '0 8px 24px rgba(17,24,39,0.10)'
                e.currentTarget.style.borderColor = m.accent
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.transform = 'none'
                e.currentTarget.style.boxShadow = '0 1px 4px rgba(17,24,39,0.05)'
                e.currentTarget.style.borderColor = '#edf0f5'
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div
                  style={{
                    width: 44, height: 44, borderRadius: 12, flexShrink: 0,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    fontSize: 20, color: m.accent,
                    background: `linear-gradient(135deg, ${m.accent}1f, ${m.accent}0a)`,
                    border: `1px solid ${m.accent}33`,
                  }}
                >
                  {MODULE_ICONS[m.id]}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Text strong style={{ fontSize: 15, color: '#111827', display: 'block' }}>{t(m.nameKey)}</Text>
                  <Text type="secondary" style={{ fontSize: 12 }}>{t(m.descKey)}</Text>
                </div>
                <RightOutlined style={{ color: '#c3cad6', fontSize: 12 }} />
              </div>

              <div style={{ marginTop: 14, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {m.summaryKeys.map((key) => {
                  const summary = formatValue(key)
                  return (
                    <div key={key} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 13 }}>
                      <Text type="secondary" ellipsis style={{ maxWidth: '55%' }}>{cfg.fieldLabel(key)}</Text>
                      <Text strong style={{ color: summary ? '#111827' : '#c3cad6' }}>{summary ?? '--'}</Text>
                    </div>
                  )
                })}
              </div>
            </div>
          </Col>
        ))}

        {/* 高级参数入口（工程师模式） */}
        <Col xs={24} sm={12} xl={8} xxl={6}>
          <div
            role="button"
            tabIndex={0}
            onClick={onOpenAdvanced}
            onKeyDown={(e) => e.key === 'Enter' && onOpenAdvanced()}
            style={{
              background: 'linear-gradient(135deg, #111827, #1f2937)', borderRadius: 16, padding: 18,
              cursor: 'pointer', height: '100%',
              boxShadow: '0 1px 4px rgba(17,24,39,0.2)', transition: 'all 0.2s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = 'translateY(-2px)'
              e.currentTarget.style.boxShadow = '0 8px 24px rgba(17,24,39,0.3)'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = 'none'
              e.currentTarget.style.boxShadow = '0 1px 4px rgba(17,24,39,0.2)'
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div
                style={{
                  width: 44, height: 44, borderRadius: 12, flexShrink: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 20, color: '#00D4FF', background: 'rgba(0,212,255,0.1)',
                  border: '1px solid rgba(0,212,255,0.25)',
                }}
              >
                <CodeOutlined />
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <Text strong style={{ fontSize: 15, color: '#fff', display: 'block' }}>{t('remote3.advancedEntry')}</Text>
                <Text style={{ fontSize: 12, color: 'rgba(255,255,255,0.55)' }}>{t('remote3.advancedEntryDesc')}</Text>
              </div>
              <RightOutlined style={{ color: 'rgba(255,255,255,0.4)', fontSize: 12 }} />
            </div>
            <div style={{ marginTop: 14, fontSize: 12, color: 'rgba(255,255,255,0.45)' }}>
              {t('remote3.advancedEntryHint')}
            </div>
          </div>
        </Col>
      </Row>
    </Spin>
  )
}

export default SettingsHome
