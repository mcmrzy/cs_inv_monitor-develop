import React, { useState, useEffect, useMemo } from 'react'
import { Modal, Radio, Slider, Select, Table, Tag, Input, Space, Button, App, Typography, Divider, Switch, Form } from 'antd'
import type { ColumnsType } from 'antd/es/table'
import { useQueryClient } from '@tanstack/react-query'
import { otaApi } from '@/services/otaApi'
import { deviceApi } from '@/services/deviceApi'
import { modelApi } from '@/services/modelApi'
import { queryKeys } from '@/utils/queryKeys'
import type { UpgradePackage, Device, PublishPackageRequest } from '@/types'
import QueryErrorAlert from '@/components/QueryErrorAlert'
import useTranslation from '@/hooks/useTranslation'

const { TextArea } = Input
const { Text } = Typography

interface PublishModalProps {
  open: boolean
  packageData: UpgradePackage | null
  onClose: () => void
  onSuccess: () => void
}

type RolloutMode = 'all' | 'gray' | 'model' | 'device'

const PublishModal: React.FC<PublishModalProps> = ({ open, packageData, onClose, onSuccess }) => {
  const queryClient = useQueryClient()
  const { message } = App.useApp()
  const { t } = useTranslation()
  const [form] = Form.useForm()

  const [rolloutMode, setRolloutMode] = useState<RolloutMode>('all')
  const [rolloutPercent, setRolloutPercent] = useState<number>(10)
  const [selectedModel, setSelectedModel] = useState<string>()
  const [snInput, setSnInput] = useState('')
  const [deviceList, setDeviceList] = useState<Device[]>([])
  const [deviceLoading, setDeviceLoading] = useState(false)
  const [publishing, setPublishing] = useState(false)
  const [modelList, setModelList] = useState<string[]>([])
  const [modelError, setModelError] = useState<unknown>(null)
  const [deviceError, setDeviceError] = useState<unknown>(null)
  const [reloadKey, setReloadKey] = useState(0)

  // 加载型号列表
  useEffect(() => {
    if (!open) return
    setModelError(null)
    modelApi.listModels().then((res) => {
      const items = res.data?.data ?? res.data ?? []
      setModelList(Array.isArray(items) ? items.map((m: any) => m.model_code || m.model) : [])
    }).catch((error) => {
      setModelList([])
      setModelError(error)
    })
  }, [open, reloadKey])

  // 加载设备列表
  useEffect(() => {
    if (!open) return
    setDeviceError(null)
    if (rolloutMode === 'device') {
      const sns = snInput.split(/[,，\s]+/).map(s => s.trim()).filter(Boolean)
      if (sns.length === 0) { setDeviceList([]); return }
      setDeviceLoading(true)
      deviceApi.getDevices({ sns: sns.join(','), pageSize: 100 }).then((res) => {
        const d = res.data?.data ?? res.data ?? {}
        setDeviceList(Array.isArray(d) ? d : (d?.items ?? []))
      }).catch((error) => {
        setDeviceList([])
        setDeviceError(error)
      }).finally(() => setDeviceLoading(false))
      return
    }
    if (rolloutMode === 'model' && !selectedModel) { setDeviceList([]); return }
    setDeviceLoading(true)
    const params: Record<string, any> = { pageSize: 100 }
    if (rolloutMode === 'model') params.model = selectedModel
    deviceApi.getDevices(params).then((res) => {
      const d = res.data?.data ?? res.data ?? {}
      setDeviceList(Array.isArray(d) ? d : (d?.items ?? []))
    }).catch((error) => {
      setDeviceList([])
      setDeviceError(error)
    }).finally(() => setDeviceLoading(false))
  }, [open, rolloutMode, selectedModel, snInput, reloadKey])

  // 重置状态
  useEffect(() => {
    if (open && packageData) {
      setRolloutMode('all')
      setRolloutPercent(10)
      setSelectedModel(undefined)
      setSnInput('')
      setDeviceList([])
      // 填充表单
      form.setFieldsValue({
        user_version: packageData.user_version || '',
        user_changelog: packageData.user_changelog || '',
        is_force: packageData.is_force || false,
      })
    }
  }, [open, packageData, form])

  const invalidate = () => queryClient.invalidateQueries({ queryKey: queryKeys.ota.all })

  const handlePublish = async () => {
    if (!packageData) return
    
    try {
      const values = await form.validateFields()
      setPublishing(true)
      
      // 1. 先更新升级包的用户可见信息
      await otaApi.updatePackage(Number(packageData.id), {
        user_version: values.user_version || undefined,
        user_changelog: values.user_changelog || undefined,
        is_force: values.is_force || false,
      })
      
      // 2. 构建发布请求
      const reqData: PublishPackageRequest = {
        is_published: true,
        rollout_type: rolloutMode === 'gray' ? 'all' : rolloutMode,
        auto_push: false, // 只发布，不自动推送升级
      }
      if (rolloutMode === 'gray') reqData.rollout_percent = rolloutPercent
      if (rolloutMode === 'model') reqData.rollout_targets = selectedModel
      if (rolloutMode === 'device') reqData.rollout_targets = snInput
      
      // 3. 发布并推送
      await otaApi.publishPackage(Number(packageData.id), reqData)
      message.success(t('ota.publishSuccessMsg'))
      invalidate()
      onSuccess()
    } catch (err: any) {
      if (err?.errorFields) return // 表单验证失败
      message.error(`${t('ota.publishFailPrefix')}: ` + (err?.response?.data?.message || err?.message || ''))
    } finally {
      setPublishing(false)
    }
  }

  const estimatedCount = useMemo(() => {
    if (rolloutMode !== 'gray') return 0
    return Math.round(deviceList.length * rolloutPercent / 100)
  }, [rolloutMode, deviceList.length, rolloutPercent])

  const previewColumns: ColumnsType<Device> = [
    { title: t('ota.sn'), dataIndex: 'sn', width: 180 },
    {
      title: t('ota.currentVersion'), dataIndex: 'firmwareVersion', width: 160,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : <Tag>{t('ota.unknown')}</Tag>,
    },
    {
      title: t('common.status'), dataIndex: 'status', width: 100,
      render: (status: string) => {
        const colorMap: Record<string, string> = { online: 'green', offline: 'default', fault: 'red' }
        const labelMap: Record<string, string> = { online: t('common.online'), offline: t('common.offline'), fault: t('common.fault') }
        return <Tag color={colorMap[status] ?? 'default'}>{labelMap[status] ?? status}</Tag>
      },
    },
  ]

  const grayPreviewDevices = useMemo(() => {
    if (rolloutMode !== 'gray') return deviceList
    const count = Math.max(1, estimatedCount)
    return deviceList.slice(0, count)
  }, [rolloutMode, deviceList, estimatedCount])

  const showPreview = rolloutMode === 'all' || rolloutMode === 'model' || rolloutMode === 'gray' ||
    (rolloutMode === 'device' && deviceList.length > 0)

  return (
    <Modal
      title={`${t('ota.pushPackage')} - ${packageData?.main_version ?? ''}`}
      open={open}
      onCancel={onClose}
      width={800}
      destroyOnClose
      footer={
        <Space style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <Button onClick={onClose}>{t('common.cancel')}</Button>
          <Button
            type="primary"
            onClick={handlePublish}
            loading={publishing}
            disabled={!!deviceError || (rolloutMode === 'model' && !!modelError)}
          >{t('ota.pushPackage')}</Button>
        </Space>
      }
    >
      {(!!deviceError || (rolloutMode === 'model' && !!modelError)) && (
        <QueryErrorAlert
          error={deviceError || modelError}
          onRetry={() => setReloadKey((value) => value + 1)}
          style={{ marginBottom: 16 }}
        />
      )}
      {/* 用户可见信息 */}
      <div style={{ marginBottom: 16 }}>
        <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('ota.userVisibleInfo')}</Text>
        <Form form={form} layout="vertical">
          <Form.Item 
            name="user_version" 
            label={t('ota.userVersion')}
            help={t('ota.userVersionHelp')}
          >
            <Input placeholder={t('ota.versionExample')} />
          </Form.Item>
          <Form.Item 
            name="user_changelog" 
            label={t('ota.updateNotes')}
            help={t('ota.updateNotesHelp')}
          >
            <TextArea rows={3} placeholder={t('ota.changelogExample')} />
          </Form.Item>
          <Form.Item name="is_force" label={t('ota.forceUpdate')} valuePropName="checked" help={t('ota.forceUpdateHelp')}>
            <Switch />
          </Form.Item>
        </Form>
      </div>

      <Divider />

      {/* 推送策略 */}
      <div style={{ marginBottom: 16 }}>
        <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('ota.pushStrategy')}</Text>
        <Radio.Group value={rolloutMode} onChange={e => setRolloutMode(e.target.value)}>
          <Radio.Button value="all">{t('ota.rolloutAll')}</Radio.Button>
          <Radio.Button value="gray">{t('ota.rolloutGray')}</Radio.Button>
          <Radio.Button value="model">{t('ota.rolloutByModel')}</Radio.Button>
          <Radio.Button value="device">{t('ota.rolloutByDevice')}</Radio.Button>
        </Radio.Group>
      </div>

      {/* 灰度百分比 */}
      {rolloutMode === 'gray' && (
        <div style={{ marginBottom: 16 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('ota.rolloutPercentLabel')}: {rolloutPercent}%</Text>
          <Slider min={1} max={99} value={rolloutPercent} onChange={v => setRolloutPercent(v)} />
          <Text type="secondary">
            {t('ota.rolloutEstimate', { estimated: estimatedCount, total: deviceList.length })}
          </Text>
        </div>
      )}

      {/* 型号选择 */}
      {rolloutMode === 'model' && (
        <div style={{ marginBottom: 16 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('ota.selectModelLabel')}</Text>
          <Select
            style={{ width: 300 }}
            placeholder={t('ota.selectModel')}
            value={selectedModel}
            onChange={v => setSelectedModel(v)}
            allowClear
            options={modelList.map(m => ({ label: m, value: m }))}
          />
        </div>
      )}

      {/* SN 输入 */}
      {rolloutMode === 'device' && (
        <div style={{ marginBottom: 16 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>{t('ota.deviceSnInput')}</Text>
          <TextArea
            rows={3}
            value={snInput}
            onChange={e => setSnInput(e.target.value)}
            placeholder={t('ota.deviceSnExample')}
          />
        </div>
      )}

      {/* 设备预览 */}
      {showPreview && (
        <>
          <Divider orientation="left">{t('ota.devicePreview')}</Divider>
          <Table
            size="small"
            rowKey="sn"
            columns={previewColumns}
            dataSource={rolloutMode === 'gray' ? grayPreviewDevices : deviceList}
            loading={deviceLoading}
            pagination={rolloutMode === 'gray' ? false : { pageSize: 5 }}
            scroll={{ y: 240 }}
          />
        </>
      )}
    </Modal>
  )
}

export default PublishModal
