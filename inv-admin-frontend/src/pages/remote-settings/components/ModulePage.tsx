// 第二层：功能分类页 —— 面包屑返回设置首页 + 模块参数列表（visibility 联动过滤）

import React from 'react'
import { Breadcrumb, Typography, Empty, Spin } from 'antd'
import { LeftOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import type { SettingsModule } from '../config/fields'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import FieldControl from './FieldControl'

const { Text } = Typography

interface ModulePageProps {
  module: SettingsModule
  cfg: DeviceConfigApi
  onBack: () => void
}

const ModulePage: React.FC<ModulePageProps> = ({ module, cfg, onBack }) => {
  const { t } = useTranslation()

  const visibleKeys = module.paramKeys.filter((key) => cfg.isVisible(cfg.getMeta(key)))
  // 字段完全不在 schema 且无上报值时隐藏（扩展参数固件未实现），避免整页全是无法读取的项
  const availableKeys = visibleKeys.filter(
    (key) => cfg.schemaMap.has(key) || cfg.getSummaryValue(key) !== undefined,
  )

  return (
    <div>
      <Breadcrumb
        style={{ marginBottom: 16 }}
        items={[
          {
            title: (
              <a onClick={onBack} style={{ cursor: 'pointer' }}>
                <LeftOutlined style={{ fontSize: 11, marginRight: 4 }} />
                {t('remote3.homeTitle')}
              </a>
            ),
          },
          { title: t(module.nameKey) },
        ]}
      />

      <div
        style={{
          background: '#fff', borderRadius: 16, border: '1px solid #edf0f5',
          boxShadow: '0 1px 4px rgba(17,24,39,0.05)', overflow: 'hidden',
        }}
      >
        <div
          style={{
            padding: '18px 24px',
            background: `linear-gradient(90deg, ${module.accent}14, transparent)`,
            borderBottom: '1px solid #f0f3f8',
          }}
        >
          <Text strong style={{ fontSize: 17, color: '#111827' }}>{t(module.nameKey)}</Text>
          <Text type="secondary" style={{ display: 'block', fontSize: 13, marginTop: 2 }}>
            {t(module.descKey)}
          </Text>
        </div>

        {(cfg.schemaError || cfg.stateError) && (
          <div style={{ padding: '16px 24px 0' }}>
            <QueryErrorAlert error={cfg.schemaError ?? cfg.stateError} onRetry={cfg.refetchAll} />
          </div>
        )}

        <Spin spinning={cfg.schemaLoading}>
          <div style={{ padding: '4px 24px 12px' }}>
            {availableKeys.length > 0 ? (
              availableKeys.map((key) => <FieldControl key={key} cfg={cfg} paramKey={key} />)
            ) : (
              !cfg.schemaLoading && (
                <Empty
                  description={t('remote3.moduleEmpty')}
                  image={Empty.PRESENTED_IMAGE_SIMPLE}
                  style={{ padding: '32px 0' }}
                />
              )
            )}
          </div>
        </Spin>
      </div>
    </div>
  )
}

export default ModulePage
