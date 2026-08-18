// 第三层：高级参数（工程师模式）——安装密码门（前端本地校验，会话内记住，不传后端）
// 解锁后列表展示全部原始参数（key + 值 + 编辑），含 schema 未登记但已上报的扩展键

import React, { useMemo, useState } from 'react'
import { Breadcrumb, Typography, Input, Button, Empty, Spin, Tag, Alert } from 'antd'
import { LeftOutlined, LockOutlined, UnlockOutlined, SafetyCertificateOutlined } from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { ADVANCED_PASSWORD, ADVANCED_UNLOCK_KEY } from '../config/fields'
import FieldControl from './FieldControl'

const { Text } = Typography

interface AdvancedPanelProps {
  cfg: DeviceConfigApi
  onBack: () => void
}

const AdvancedPanel: React.FC<AdvancedPanelProps> = ({ cfg, onBack }) => {
  const { t } = useTranslation()
  const [unlocked, setUnlocked] = useState(() => sessionStorage.getItem(ADVANCED_UNLOCK_KEY) === '1')
  const [password, setPassword] = useState('')
  const [failed, setFailed] = useState(false)

  const handleUnlock = () => {
    if (password === ADVANCED_PASSWORD) {
      sessionStorage.setItem(ADVANCED_UNLOCK_KEY, '1')
      setUnlocked(true)
      setFailed(false)
    } else {
      setFailed(true)
    }
  }

  const handleLock = () => {
    sessionStorage.removeItem(ADVANCED_UNLOCK_KEY)
    setUnlocked(false)
    setPassword('')
  }

  // 全部原始参数：schema 登记项（按分组/序号）+ schema 未登记但已上报的扩展键
  const allKeys = useMemo(() => {
    const registered = [...cfg.schemaItems].sort(
      (a, b) => a.group_code.localeCompare(b.group_code) || a.sort_order - b.sort_order,
    ).map((it) => it.param_key)
    const extras = [...new Set([...Object.keys(cfg.reported), ...Object.keys(cfg.desired)])]
      .filter((k) => !cfg.schemaMap.has(k))
      .sort()
    return [...registered, ...extras]
  }, [cfg.schemaItems, cfg.schemaMap, cfg.reported, cfg.desired])

  const breadcrumb = (
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
        { title: t('remote3.advancedTitle') },
      ]}
    />
  )

  if (!unlocked) {
    return (
      <div>
        {breadcrumb}
        <div
          style={{
            maxWidth: 420, margin: '48px auto', background: '#fff', borderRadius: 16,
            border: '1px solid #edf0f5', boxShadow: '0 1px 4px rgba(17,24,39,0.05)',
            padding: 32, textAlign: 'center',
          }}
        >
          <div
            style={{
              width: 56, height: 56, borderRadius: 16, margin: '0 auto 16px',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 24, color: '#00D4FF', background: 'rgba(0,212,255,0.1)',
              border: '1px solid rgba(0,212,255,0.25)',
            }}
          >
            <LockOutlined />
          </div>
          <Text strong style={{ fontSize: 16, color: '#111827', display: 'block' }}>
            {t('remote3.advancedTitle')}
          </Text>
          <Text type="secondary" style={{ display: 'block', fontSize: 13, margin: '8px 0 20px' }}>
            {t('remote3.advancedLockHint')}
          </Text>
          <Input.Password
            placeholder={t('remote3.advancedPasswordPlaceholder')}
            value={password}
            onChange={(e) => {
              setPassword(e.target.value)
              setFailed(false)
            }}
            onPressEnter={handleUnlock}
            style={{ marginBottom: failed ? 8 : 16 }}
            maxLength={16}
          />
          {failed && (
            <Text type="danger" style={{ display: 'block', fontSize: 12, marginBottom: 8 }}>
              {t('remote3.advancedPasswordError')}
            </Text>
          )}
          <Button type="primary" block icon={<UnlockOutlined />} onClick={handleUnlock} disabled={!password}>
            {t('remote3.advancedUnlock')}
          </Button>
          <Text type="secondary" style={{ display: 'block', fontSize: 12, marginTop: 12 }}>
            {t('remote3.advancedLocalOnly')}
          </Text>
        </div>
      </div>
    )
  }

  return (
    <div>
      {breadcrumb}
      <div
        style={{
          background: '#fff', borderRadius: 16, border: '1px solid #edf0f5',
          boxShadow: '0 1px 4px rgba(17,24,39,0.05)', overflow: 'hidden',
        }}
      >
        <div
          style={{
            padding: '16px 24px', borderBottom: '1px solid #f0f3f8',
            display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap',
            background: 'linear-gradient(90deg, rgba(17,24,39,0.04), transparent)',
          }}
        >
          <SafetyCertificateOutlined style={{ color: '#00D4FF', fontSize: 18 }} />
          <Text strong style={{ fontSize: 16, color: '#111827' }}>{t('remote3.advancedTitle')}</Text>
          <Tag color="cyan">{t('remote3.advancedCount', { count: allKeys.length })}</Tag>
          <div style={{ flex: 1 }} />
          <Button size="small" icon={<LockOutlined />} onClick={handleLock}>
            {t('remote3.advancedLock')}
          </Button>
        </div>

        <div style={{ padding: '12px 24px 0' }}>
          <Alert type="warning" showIcon message={t('remote3.advancedWarning')} style={{ borderRadius: 10 }} />
        </div>

        {(cfg.schemaError || cfg.stateError) && (
          <div style={{ padding: '16px 24px 0' }}>
            <QueryErrorAlert error={cfg.schemaError ?? cfg.stateError} onRetry={cfg.refetchAll} />
          </div>
        )}

        <Spin spinning={cfg.schemaLoading}>
          <div style={{ padding: '8px 24px 16px' }}>
            {allKeys.length > 0 ? (
              allKeys.map((key) => {
                const schemaItem = cfg.schemaMap.get(key)
                return (
                  <div key={key}>
                    <div style={{ display: 'flex', gap: 6, alignItems: 'center', marginTop: 6 }}>
                      <Tag style={{ marginInlineEnd: 0, fontSize: 11 }}>
                        {schemaItem ? `${schemaItem.group_code}${schemaItem.sub_group ? `/${schemaItem.sub_group}` : ''}` : 'extra'}
                      </Tag>
                      {schemaItem && schemaItem.scale !== 1 && (
                        <Tag style={{ marginInlineEnd: 0, fontSize: 11 }}>scale {schemaItem.scale}</Tag>
                      )}
                    </div>
                    <FieldControl cfg={cfg} paramKey={key} />
                  </div>
                )
              })
            ) : (
              !cfg.schemaLoading && (
                <Empty
                  description={t('remote.schema.empty')}
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

export default AdvancedPanel
