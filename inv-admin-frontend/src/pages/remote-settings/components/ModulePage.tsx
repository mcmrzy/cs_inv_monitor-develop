// 第二层：功能分类页 —— 面包屑返回 + 模块页头（accent 渐变）+ 折叠卡片列表（visibility 联动过滤）
// 去双层嵌套：不再用白色大容器包裹，卡片直接铺在页面背景上（与设置首页风格一致）

import React, { useState } from 'react'
import { Breadcrumb, Typography, Empty, Spin, Collapse } from 'antd'
import { LeftOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import type { SettingsModule } from '../config/fields'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { FieldCardHeader, FieldCardBody } from './FieldControl'
import './modulePage.css'

const { Text } = Typography

interface ModulePageProps {
  module: SettingsModule
  cfg: DeviceConfigApi
  onBack: () => void
}

const ModulePage: React.FC<ModulePageProps> = ({ module, cfg, onBack }) => {
  const { t } = useTranslation()
  const [activeKeys, setActiveKeys] = useState<string[]>([])

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

      {/* 模块页头：accent 渐变横幅（替代原白色容器头部） */}
      <div
        style={{
          display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
          padding: '14px 18px', marginBottom: 14,
          background: `linear-gradient(90deg, ${module.accent}1f, ${module.accent}0a)`,
          border: `1px solid ${module.accent}33`,
          borderRadius: 12,
        }}
      >
        <Text strong style={{ fontSize: 17, color: '#111827' }}>{t(module.nameKey)}</Text>
        <Text type="secondary" style={{ fontSize: 13 }}>{t(module.descKey)}</Text>
      </div>

      {(cfg.schemaError || cfg.stateError) && (
        <div style={{ marginBottom: 12 }}>
          <QueryErrorAlert error={cfg.schemaError ?? cfg.stateError} onRetry={cfg.refetchAll} />
        </div>
      )}

      <Spin spinning={cfg.schemaLoading}>
        {availableKeys.length > 0 ? (
          <Collapse
            ghost
            className="rs-module-collapse"
            expandIconPosition="end"
            activeKey={activeKeys}
            onChange={(keys) => setActiveKeys(Array.isArray(keys) ? (keys as string[]) : [keys])}
            items={availableKeys.map((key) => ({
              key,
              label: <FieldCardHeader cfg={cfg} paramKey={key} />,
              children: <FieldCardBody cfg={cfg} paramKey={key} />,
            }))}
          />
        ) : (
          !cfg.schemaLoading && (
            <Empty
              description={t('remote3.moduleEmpty')}
              image={Empty.PRESENTED_IMAGE_SIMPLE}
              style={{ padding: '32px 0', background: '#fff', borderRadius: 12, border: '1px solid #edf0f5' }}
            />
          )
        )}
      </Spin>
    </div>
  )
}

export default ModulePage
