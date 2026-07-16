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
    { title: 'SN', dataIndex: 'sn', width: 180 },
    {
      title: '当前固件版本', dataIndex: 'firmwareVersion', width: 160,
      render: (v: string) => v ? <Tag color="blue">{v}</Tag> : <Tag>未知</Tag>,
    },
    {
      title: '在线状态', dataIndex: 'status', width: 100,
      render: (status: string) => {
        const colorMap: Record<string, string> = { online: 'green', offline: 'default', fault: 'red' }
        const labelMap: Record<string, string> = { online: '在线', offline: '离线', fault: '故障' }
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
      title={`推送升级包 - ${packageData?.main_version ?? ''}`}
      open={open}
      onCancel={onClose}
      width={800}
      destroyOnClose
      footer={
        <Space style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <Button onClick={onClose}>取消</Button>
          <Button
            type="primary"
            onClick={handlePublish}
            loading={publishing}
            disabled={!!deviceError || (rolloutMode === 'model' && !!modelError)}
          >推送</Button>
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
        <Text strong style={{ display: 'block', marginBottom: 8 }}>用户可见信息</Text>
        <Form form={form} layout="vertical">
          <Form.Item 
            name="user_version" 
            label="版本号"
            help="用户看到的版本号，留空自动生成（如 V1.0.0）"
          >
            <Input placeholder="例如：V1.0.2" />
          </Form.Item>
          <Form.Item 
            name="user_changelog" 
            label="更新说明"
            help="用户看到的更新说明，留空自动汇总各固件说明"
          >
            <TextArea rows={3} placeholder="例如：修复了XX问题，优化了XX功能" />
          </Form.Item>
          <Form.Item name="is_force" label="强制更新" valuePropName="checked" help="开启后用户必须更新才能使用App">
            <Switch />
          </Form.Item>
        </Form>
      </div>

      <Divider />

      {/* 推送策略 */}
      <div style={{ marginBottom: 16 }}>
        <Text strong style={{ display: 'block', marginBottom: 8 }}>推送策略</Text>
        <Radio.Group value={rolloutMode} onChange={e => setRolloutMode(e.target.value)}>
          <Radio.Button value="all">全量推送</Radio.Button>
          <Radio.Button value="gray">灰度推送</Radio.Button>
          <Radio.Button value="model">按型号</Radio.Button>
          <Radio.Button value="device">按设备SN</Radio.Button>
        </Radio.Group>
      </div>

      {/* 灰度百分比 */}
      {rolloutMode === 'gray' && (
        <div style={{ marginBottom: 16 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>灰度比例: {rolloutPercent}%</Text>
          <Slider min={1} max={99} value={rolloutPercent} onChange={v => setRolloutPercent(v)} />
          <Text type="secondary">
            预计推送 {estimatedCount} 台（共 {deviceList.length} 台）
          </Text>
        </div>
      )}

      {/* 型号选择 */}
      {rolloutMode === 'model' && (
        <div style={{ marginBottom: 16 }}>
          <Text strong style={{ display: 'block', marginBottom: 8 }}>选择型号</Text>
          <Select
            style={{ width: 300 }}
            placeholder="请选择型号"
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
          <Text strong style={{ display: 'block', marginBottom: 8 }}>输入设备 SN（逗号分隔）</Text>
          <TextArea
            rows={3}
            value={snInput}
            onChange={e => setSnInput(e.target.value)}
            placeholder="例如: SN001,SN002,SN003"
          />
        </div>
      )}

      {/* 设备预览 */}
      {showPreview && (
        <>
          <Divider orientation="left">设备预览</Divider>
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
