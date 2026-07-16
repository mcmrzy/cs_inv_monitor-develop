import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Select, Card, Tag, Row, Col, Typography } from 'antd'
import {
  SearchOutlined, AppstoreOutlined, ThunderboltOutlined,
  FieldNumberOutlined, CrownOutlined,
} from '@ant-design/icons'
import { modelApi } from '@/services/modelApi'
import type { DeviceModelItem } from '@/services/modelApi'
import useTranslation from '@/hooks/useTranslation'
import { DS } from '../types'

const { Title, Text } = Typography

interface ModelSelectorProps {
  selectedModelId: number | null
  onModelChange: (modelId: number) => void
  fieldCount?: number
}

const STATUS_COLOR_MAP: Record<string, { color: string; bg: string; label: string }> = {
  active: { color: DS.success, bg: '#ecfdf5', label: 'Active' },
  draft: { color: DS.primary, bg: DS.primaryLight, label: 'Draft' },
  retired: { color: DS.textMuted, bg: '#f3f4f6', label: 'Retired' },
}

const msCardStyle = `
.ms-summary-card {
  border-radius: 16px;
  border: none;
  box-shadow: 0 2px 8px rgba(0,0,0,0.06), 0 6px 20px rgba(0,0,0,0.04);
  overflow: hidden;
  transition: all 0.25s ease;
  background: #fff;
}
.ms-summary-card:hover {
  box-shadow: 0 6px 20px rgba(79,70,229,0.12), 0 2px 8px rgba(0,0,0,0.06);
  transform: translateY(-3px);
}
.ms-select-wrapper .ant-select-selector {
  border-radius: 12px !important;
  height: 52px !important;
  border: 1.5px solid ${DS.border} !important;
  box-shadow: none !important;
  transition: all 0.22s ease !important;
  font-size: 15px !important;
  padding: 0 14px !important;
}
.ms-select-wrapper .ant-select-selector:hover {
  border-color: ${DS.primary} !important;
}
.ms-select-wrapper .ant-select-focused .ant-select-selector {
  border-color: ${DS.primary} !important;
  box-shadow: 0 0 0 3px ${DS.primaryLight} !important;
}
.ms-select-wrapper .ant-select-selection-search-input {
  height: 50px !important;
}
.ms-stat-chip {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 16px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 500;
  transition: all 0.2s ease;
  box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.ms-stat-chip:hover {
  box-shadow: 0 2px 6px rgba(0,0,0,0.08);
  transform: translateY(-1px);
}
.ms-model-icon {
  width: 48px;
  height: 48px;
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 12px rgba(79,70,229,0.25);
}
.ms-status-pill {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 6px 14px;
  border-radius: 24px;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.02em;
  box-shadow: 0 1px 4px rgba(0,0,0,0.06);
}
.ms-status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  box-shadow: 0 0 0 3px rgba(0,0,0,0.04);
}
.ms-desc-block {
  padding: 14px 0 0;
  border-top: 1px solid ${DS.border};
}
`

const ModelSelector: React.FC<ModelSelectorProps> = ({
  selectedModelId,
  onModelChange,
  fieldCount,
}) => {
  const { t } = useTranslation()

  const { data: models = [], isLoading } = useQuery<DeviceModelItem[]>({
    queryKey: ['remote-settings', 'models'],
    queryFn: () =>
      modelApi.listModels().then((res) => {
        const d = res.data
        return (Array.isArray(d?.data) ? d.data : Array.isArray(d) ? d : []) as DeviceModelItem[]
      }),
    staleTime: 60000,
  })

  const selectedModel = useMemo(
    () => models.find((m) => m.id === selectedModelId) ?? null,
    [models, selectedModelId],
  )

  const statusCfg = STATUS_COLOR_MAP[selectedModel?.lifecycle_status ?? 'active'] ?? STATUS_COLOR_MAP.active

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
      <style>{msCardStyle}</style>

      <div className="ms-select-wrapper">
        <Select
          style={{ width: '100%' }}
          size="large"
          placeholder={t('remoteSettings.selectModel')}
          loading={isLoading}
          showSearch
          allowClear
          suffixIcon={<SearchOutlined style={{ color: DS.textMuted, fontSize: 16 }} />}
          value={selectedModelId ?? undefined}
          onChange={(val: number | undefined) => {
            if (val !== undefined) {
              onModelChange(val)
            } else {
              onModelChange(null as unknown as number)
            }
          }}
          onClear={() => onModelChange(null as unknown as number)}
          optionFilterProp="label"
          options={models.map((m) => ({
            label: `${m.model_name}${m.manufacturer ? ` · ${m.manufacturer}` : ''}`,
            value: m.id,
          }))}
        />
      </div>

      {selectedModel && (
        <Card bordered={false} className="ms-summary-card" styles={{ body: { padding: 0 } }}>
          <Row gutter={0}>
            {/* Left color accent bar */}
            <Col
              flex="5px"
              style={{
                background: `linear-gradient(180deg, ${statusCfg.color}, ${statusCfg.color}aa)`,
                minHeight: '100%',
                borderRadius: '16px 0 0 16px',
              }}
            />

            <Col flex="auto" style={{ padding: '24px 28px' }}>
              {/* Header row */}
              <Row align="middle" justify="space-between" style={{ marginBottom: 20 }}>
                <Col>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                    <div
                      className="ms-model-icon"
                      style={{
                        background: `linear-gradient(135deg, ${DS.primary}, ${DS.secondary})`,
                      }}
                    >
                      <AppstoreOutlined style={{ fontSize: 20, color: '#fff' }} />
                    </div>
                    <div>
                      <Title level={5} style={{ margin: 0, fontSize: 18, fontWeight: 700, color: DS.textPrimary }}>
                        {selectedModel.model_name}
                      </Title>
                      {selectedModel.manufacturer && (
                        <Text style={{ fontSize: 13, color: DS.textSecondary, marginTop: 3, display: 'block' }}>
                          {selectedModel.manufacturer}
                        </Text>
                      )}
                    </div>
                  </div>
                </Col>
                <Col>
                  <div
                    className="ms-status-pill"
                    style={{ background: statusCfg.bg, color: statusCfg.color }}
                  >
                    <span
                      className="ms-status-dot"
                      style={{ background: statusCfg.color }}
                    />
                    {t(`remoteSettings.status${(selectedModel.lifecycle_status ?? 'active').charAt(0).toUpperCase() + (selectedModel.lifecycle_status ?? 'active').slice(1)}`)}
                  </div>
                </Col>
              </Row>

              {/* Stats chips row */}
              <Row gutter={[12, 10]}>
                <Col>
                  <div className="ms-stat-chip" style={{ background: DS.primaryLight, color: DS.primary }}>
                    <FieldNumberOutlined style={{ fontSize: 15 }} />
                    <span>{t('remoteSettings.fieldCount')}: <strong>{fieldCount ?? '-'}</strong></span>
                  </div>
                </Col>
                <Col>
                  <div className="ms-stat-chip" style={{ background: '#ecfdf5', color: DS.success }}>
                    <ThunderboltOutlined style={{ fontSize: 15 }} />
                    <span>{t('remoteSettings.ratedPower')}: <strong>
                      {selectedModel.rated_power_kw != null ? `${selectedModel.rated_power_kw} kW` : '-'}
                    </strong></span>
                  </div>
                </Col>
                {selectedModel.category && (
                  <Col>
                    <div className="ms-stat-chip" style={{ background: '#fef3c7', color: '#92400e' }}>
                      <CrownOutlined style={{ fontSize: 15 }} />
                      <span>{selectedModel.category}</span>
                    </div>
                  </Col>
                )}
              </Row>

              {/* Description */}
              {selectedModel.description && (
                <div className="ms-desc-block" style={{ marginTop: 16 }}>
                  <Text style={{ fontSize: 13, color: DS.textSecondary, lineHeight: 1.7 }}>
                    {selectedModel.description}
                  </Text>
                </div>
              )}
            </Col>
          </Row>
        </Card>
      )}
    </div>
  )
}

export default ModelSelector
