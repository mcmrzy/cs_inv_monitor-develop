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

  const profiles: BatteryProfile[] = (profilesRes as BatteryProfile[]) ?? []

  const { isLoading: configLoading, error: configError, refetch: refetchConfig } = useQuery({
    queryKey: queryKeys.devices.batteryConfig(sn),
    queryFn: () => deviceApi.getBatteryConfig(sn).then((r) => {
      const d = r.data?.data ?? {}
      form.setFieldsValue({
        profile_id: d.profile_id ?? null,
      })
      acForm.setFieldsValue({
        ac_input_type: d.ac_input_type ?? 'grid',
        grid_mode: d.grid_mode ?? 'off_grid',
        max_input_current: d.max_input_current ?? 32,
        max_output_voltage: d.max_output_voltage ?? 230,
      })
      return d
    }),
  })

  const bindMutation = useMutation({
    mutationFn: (values: any) => deviceApi.updateBatteryConfig(sn, values),
    onSuccess: () => {
      message.success(t('deviceDetail.install.bindSuccess'))
      queryClient.invalidateQueries({ queryKey: queryKeys.devices.batteryConfig(sn) })
    },
    onError: () => { message.error(t('deviceDetail.install.bindFailed')) },
  })

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
          <Form.Item name="profile_id" label={t('deviceDetail.install.batteryProfile')}>
            <Select
              placeholder={t('deviceDetail.install.selectProfile')}
              allowClear
              options={profiles.map((p) => ({
                label: `${p.name} (${p.brand || '-'}) — ${p.nominal_voltage ?? '-'}V / ${p.nominal_capacity ?? '-'}Ah`,
                value: p.id,
              }))}
            />
          </Form.Item>
          {selectedProfile && (
            <Descriptions size="small" bordered column={1} style={{ marginBottom: 16 }}>
              <Descriptions.Item label="Brand">{selectedProfile.brand || '-'}</Descriptions.Item>
              <Descriptions.Item label="Chemistry">{selectedProfile.chemistry || '-'}</Descriptions.Item>
              <Descriptions.Item label="Nominal Voltage">{selectedProfile.nominal_voltage ?? '-'} V</Descriptions.Item>
              <Descriptions.Item label="Nominal Capacity">{selectedProfile.nominal_capacity ?? '-'} Ah</Descriptions.Item>
            </Descriptions>
          )}
          <Button type="primary" loading={bindMutation.isPending} onClick={async () => {
            try { bindMutation.mutate(await form.validateFields()) } catch {}
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
                  { label: 'Grid', value: 'grid' },
                  { label: 'Generator', value: 'generator' },
                  { label: 'Hybrid', value: 'hybrid' },
                ]} />
              </Form.Item>
            </Col>
            <Col span={12}>
              <Form.Item name="grid_mode" label={t('deviceDetail.install.gridMode')}>
                <Select options={[
                  { label: 'Off-Grid', value: 'off_grid' },
                  { label: 'On-Grid', value: 'on_grid' },
                  { label: 'Hybrid', value: 'hybrid' },
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
              bindMutation.mutate(acValues)
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
