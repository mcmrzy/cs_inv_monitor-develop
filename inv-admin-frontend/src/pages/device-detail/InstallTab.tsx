import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  Card, Form, Select, Button, Row, Col, Spin, App, InputNumber, Descriptions,
} from 'antd'
import { deviceApi } from '@/services/deviceApi'
import { queryKeys } from '@/utils/queryKeys'
import useTranslation from '@/hooks/useTranslation'
import QueryErrorAlert from '@/components/QueryErrorAlert'

interface InstallTabProps {
  sn: string
}

interface BatteryProfile {
  id: number
  name: string
  brand: string
  nominal_voltage: number
  nominal_capacity: number
  chemistry: string
}

/** 后端 upsert 载荷（business-api UpsertBatteryConfigReq 的 JSON tag） */
interface BatteryConfigPayload {
  profile_id: number
  capacity_ah: number
  parallel_strings?: number
  installer_limits?: Record<string, unknown>
}

/** 设备尚未绑定电池模板时后端返回 404：属正常状态，按空配置渲染而非报错 */
const isNotConfiguredError = (err: unknown): boolean => {
  const e = err as { response?: { status?: number; data?: { code?: number } } }
  return e?.response?.status === 404 || e?.response?.data?.code === 404
}

const InstallTab: React.FC<InstallTabProps> = ({ sn }) => {
  const { t } = useTranslation()
  const { message } = App.useApp()
  const queryClient = useQueryClient()
  const [form] = Form.useForm()
  const [acForm] = Form.useForm()

  const { data: profilesRes, isLoading: profilesLoading, error: profilesError, refetch: refetchProfiles } = useQuery({
    queryKey: queryKeys.devices.batteryProfiles(),
    queryFn: () => deviceApi.getBatteryProfiles().then((r) => r.data?.data ?? []),
  })

  const rawProfiles = profilesRes as BatteryProfile[]
  const profiles: BatteryProfile[] = Array.isArray(rawProfiles) ? rawProfiles : []

  const { isLoading: configLoading, error: configError, refetch: refetchConfig } = useQuery({
    queryKey: queryKeys.devices.batteryConfig(sn),
    queryFn: () => deviceApi.getBatteryConfig(sn).then((r) => {
      const d = r.data?.data ?? {}
      form.setFieldsValue({
        profile_id: d.profile_id ?? null,
        capacity_ah: d.capacity_ah ?? undefined,
        parallel_strings: d.parallel_strings ?? undefined,
      })
      const limits = (d.installer_limits ?? {}) as Record<string, unknown>
      acForm.setFieldsValue({
        ac_input_type: limits.ac_input_type ?? 'grid',
        grid_mode: limits.grid_mode ?? 'off_grid',
        max_input_current: limits.max_input_current ?? 32,
        max_output_voltage: limits.max_output_voltage ?? 230,
      })
      return d
    }).catch((err: unknown) => {
      if (isNotConfiguredError(err)) {
        // 未绑定电池模板：填默认值后按空配置渲染
        acForm.setFieldsValue({
          ac_input_type: 'grid', grid_mode: 'off_grid', max_input_current: 32, max_output_voltage: 230,
        })
        return {}
      }
      throw err
    }),
  })

  const bindMutation = useMutation({
    mutationFn: (values: BatteryConfigPayload) => deviceApi.updateBatteryConfig(sn, values),
    onSuccess: () => {
      message.success(t('deviceDetail.install.bindSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.batteryConfig(sn) })
    },
    onError: () => { message.error(t('deviceDetail.install.bindFailed')) },
  })

  /** 组装 upsert 载荷：电池字段 + installer_limits（AC 字段并入 installer_limits 透传） */
  const buildPayload = (batteryValues: { profile_id: number; capacity_ah: number; parallel_strings?: number }, acValues: Record<string, unknown>): BatteryConfigPayload => {
    const limits: Record<string, unknown> = {}
    Object.entries(acValues).forEach(([k, v]) => { if (v != null) limits[k] = v })
    return {
      profile_id: batteryValues.profile_id,
      capacity_ah: batteryValues.capacity_ah,
      ...(batteryValues.parallel_strings != null ? { parallel_strings: batteryValues.parallel_strings } : {}),
      installer_limits: limits,
    }
  }

  const selectedProfile = profiles.find((p) => p.id === form.getFieldValue('profile_id'))

  return (
    <Spin spinning={profilesLoading || configLoading}>
      {(profilesError || configError) && (
        <QueryErrorAlert
          error={profilesError || configError}
          onRetry={() => { void (profilesError ? refetchProfiles() : refetchConfig()) }}
          style={{ marginBottom: 16 }}
        />
      )}
      <Card
        title={t('deviceDetail.install.batteryConfig')}
        bordered={false}
        style={{ marginBottom: 16, borderRadius: 12 }}
      >
        <Form form={form} layout="vertical" style={{ maxWidth: 600 }}>
          <Form.Item name="profile_id" label={t('deviceDetail.install.batteryProfile')} rules={[{ required: true, message: t('deviceDetail.install.selectProfile') }]}>
            <Select
              placeholder={t('deviceDetail.install.selectProfile')}
              allowClear
              onChange={(id) => {
                const p = profiles.find((item) => item.id === id)
                if (p?.nominal_capacity) {
                  form.setFieldValue('capacity_ah', p.nominal_capacity)
                }
              }}
              options={profiles.map((p) => ({
                label: `${p.name} (${p.brand || '-'}) — ${p.nominal_voltage ?? '-'}V / ${p.nominal_capacity ?? '-'}Ah`,
                value: p.id,
              }))}
            />
          </Form.Item>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item
                name="capacity_ah"
                label={t('deviceDetail.install.capacityAh')}
                rules={[
                  { required: true, message: t('deviceDetail.install.capacityRequired') },
                  { type: 'number', min: 1, message: t('deviceDetail.install.capacityPositive') },
                ]}
              >
                <InputNumber min={1} style={{ width: '100%' }} placeholder="100" />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item
                name="parallel_strings"
                label={t('deviceDetail.install.parallelStrings')}
                rules={[{ type: 'number', min: 1, message: t('deviceDetail.install.parallelPositive') }]}
              >
                <InputNumber min={1} style={{ width: '100%' }} placeholder="1" />
              </Form.Item>
            </Col>
          </Row>
          {selectedProfile && (
            <Descriptions size="small" bordered column={1} style={{ marginBottom: 16 }}>
              <Descriptions.Item label={t('deviceDetail.install.brand')}>{selectedProfile.brand || '-'}</Descriptions.Item>
              <Descriptions.Item label={t('deviceDetail.install.chemistry')}>{selectedProfile.chemistry || '-'}</Descriptions.Item>
              <Descriptions.Item label={t('deviceDetail.install.nominalVoltage')}>{selectedProfile.nominal_voltage ?? '-'} V</Descriptions.Item>
              <Descriptions.Item label={t('deviceDetail.install.nominalCapacity')}>{selectedProfile.nominal_capacity ?? '-'} Ah</Descriptions.Item>
            </Descriptions>
          )}
          <Button type="primary" loading={bindMutation.isPending} onClick={async () => {
            try {
              const batteryValues = await form.validateFields()
              bindMutation.mutate(buildPayload(batteryValues, acForm.getFieldsValue()))
            } catch {}
          }}>
            {t('deviceDetail.install.bindProfile')}
          </Button>
        </Form>
      </Card>

      <Card
        title={t('deviceDetail.install.acInputConfig')}
        bordered={false}
        style={{ borderRadius: 12 }}
      >
        <Form form={acForm} layout="vertical" style={{ maxWidth: 600 }}>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="ac_input_type" label={t('deviceDetail.install.acInputType')}>
                <Select options={[
                  { label: t('deviceDetail.install.inputGrid'), value: 'grid' },
                  { label: t('deviceDetail.install.inputGenerator'), value: 'generator' },
                  { label: t('deviceDetail.install.inputHybrid'), value: 'hybrid' },
                ]} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="grid_mode" label={t('deviceDetail.install.gridMode')}>
                <Select options={[
                  { label: t('deviceDetail.install.modeOffGrid'), value: 'off_grid' },
                  { label: t('deviceDetail.install.modeOnGrid'), value: 'on_grid' },
                  { label: t('deviceDetail.install.modeHybrid'), value: 'hybrid' },
                ]} />
              </Form.Item>
            </Col>
          </Row>
          <Row gutter={16}>
            <Col span={12}>
              <Form.Item name="max_input_current" label={t('deviceDetail.install.maxInputCurrent')}>
                <InputNumber min={1} max={100} style={{ width: '100%' }} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="max_output_voltage" label={t('deviceDetail.install.maxOutputVoltage')}>
                <InputNumber min={100} max={400} style={{ width: '100%' }} />
              </Form.Item>
            </Col>
          </Row>
          <Button type="primary" loading={bindMutation.isPending} onClick={async () => {
            try {
              const acValues = await acForm.validateFields()
              // 后端 upsert 硬校验 profile_id>0 与 capacity_ah>0：AC 保存前先校验电池表单
              const batteryValues = await form.validateFields()
              bindMutation.mutate(buildPayload(batteryValues, acValues))
            } catch {}
          }}>
            {t('deviceDetail.install.saveAcConfig')}
          </Button>
        </Form>
      </Card>
    </Spin>
  )
}

export default InstallTab
