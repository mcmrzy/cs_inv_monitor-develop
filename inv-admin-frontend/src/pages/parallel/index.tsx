import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Alert, Card, Col, DatePicker, Descriptions, Empty, Row, Select, Space,
  Statistic, Table, Tag, Typography,
} from 'antd'
import type { ColumnsType } from 'antd/es/table'
import dayjs, { type Dayjs } from 'dayjs'
import ReactECharts from 'echarts-for-react'
import { ClusterOutlined } from '@ant-design/icons'
import { deviceApi } from '@/services/deviceApi'
import {
  getApiErrorMessage,
  protocolApi,
  type ParallelMachine,
  type ThreePhaseSample,
} from '@/services/protocolApi'
import { formatInTimezone } from '@/utils/timezone'
import useTimezoneStore from '@/stores/timezoneStore'
import useTranslation from '@/hooks/useTranslation'

const { Title, Text } = Typography
const { RangePicker } = DatePicker

interface DeviceOption {
  sn: string
  model?: string
}

function unpackDevices(response: Awaited<ReturnType<typeof deviceApi.getAll>>): DeviceOption[] {
  const data = response.data?.data ?? response.data
  const items = Array.isArray(data) ? data : (data as any)?.items ?? (data as any)?.list ?? []
  return items.filter((item: any) => typeof item?.sn === 'string')
}

const number = (value: unknown, digits = 1) => {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed.toFixed(digits) : '-'
}

const ParallelPage: React.FC = () => {
  const { t } = useTranslation()
  const { timezone } = useTimezoneStore()
  const [selectedSN, setSelectedSN] = useState<string>()
  const [range, setRange] = useState<[Dayjs, Dayjs]>([
    dayjs().subtract(24, 'hour'),
    dayjs(),
  ])

  const devicesQuery = useQuery({
    queryKey: ['protocol', 'device-options'],
    queryFn: async () => unpackDevices(await deviceApi.getAll()),
    staleTime: 60_000,
  })

  useEffect(() => {
    if (!selectedSN && devicesQuery.data?.length) setSelectedSN(devicesQuery.data[0].sn)
  }, [devicesQuery.data, selectedSN])

  const stateQuery = useQuery({
    queryKey: ['protocol', 'parallel-state', selectedSN],
    queryFn: () => protocolApi.getParallelState(selectedSN!),
    enabled: Boolean(selectedSN),
    retry: false,
  })

  const historySN = stateQuery.data?.master_sn || selectedSN
  const isThreePhase = stateQuery.data?.enabled && stateQuery.data.mode === 'three_phase'
  const threePhaseQuery = useQuery({
    queryKey: ['protocol', 'three-phase', historySN, range[0].toISOString(), range[1].toISOString()],
    queryFn: () => protocolApi.getThreePhase(historySN!, {
      page: 1,
      page_size: 500,
      start_time: range[0].toISOString(),
      end_time: range[1].toISOString(),
    }),
    enabled: Boolean(historySN && isThreePhase),
    retry: false,
  })

  const machineColumns: ColumnsType<ParallelMachine> = [
    { title: t('parallel.machineId'), dataIndex: 'id', width: 90 },
    { title: t('parallel.deviceSN'), dataIndex: 'sn' },
    {
      title: t('parallel.role'), dataIndex: 'role', width: 100,
      render: (value: string) => <Tag color={value === 'master' ? 'green' : 'blue'}>{value}</Tag>,
    },
    { title: t('parallel.phase'), dataIndex: 'phase', width: 90, render: (value) => value || '-' },
    { title: t('parallel.power'), dataIndex: 'power', align: 'right', render: (value) => `${number(value)} W` },
    {
      title: t('parallel.machineState'), dataIndex: 'state', width: 100,
      render: (value: number) => <Tag color={value === 1 ? 'success' : 'default'}>{value === 1 ? t('common.online') : t('common.offline')}</Tag>,
    },
  ]

  const historyColumns: ColumnsType<ThreePhaseSample> = [
    {
      title: t('parallel.sampleTime'), dataIndex: 'event_time', fixed: 'left', width: 165,
      render: (value: string) => formatInTimezone(value, timezone, 'YYYY-MM-DD HH:mm:ss'),
    },
    { title: 'L1 V', dataIndex: 'voltage_l1', render: (v) => number(v) },
    { title: 'L2 V', dataIndex: 'voltage_l2', render: (v) => number(v) },
    { title: 'L3 V', dataIndex: 'voltage_l3', render: (v) => number(v) },
    { title: 'L1 A', dataIndex: 'current_l1', render: (v) => number(v) },
    { title: 'L2 A', dataIndex: 'current_l2', render: (v) => number(v) },
    { title: 'L3 A', dataIndex: 'current_l3', render: (v) => number(v) },
    { title: 'L1 W', dataIndex: 'active_power_l1', render: (v) => number(v) },
    { title: 'L2 W', dataIndex: 'active_power_l2', render: (v) => number(v) },
    { title: 'L3 W', dataIndex: 'active_power_l3', render: (v) => number(v) },
    { title: 'L1-L2 V', dataIndex: 'line_voltage_l1l2', render: (v) => number(v) },
    { title: 'L2-L3 V', dataIndex: 'line_voltage_l2l3', render: (v) => number(v) },
    { title: 'L3-L1 V', dataIndex: 'line_voltage_l3l1', render: (v) => number(v) },
    { title: 'Hz', dataIndex: 'frequency', render: (v) => number(v, 2) },
    { title: t('parallel.voltageUnbalance'), dataIndex: 'voltage_unbalance', render: (v) => `${number(v, 2)}%` },
    { title: t('parallel.currentUnbalance'), dataIndex: 'current_unbalance', render: (v) => `${number(v, 2)}%` },
  ]

  const chartOption = useMemo(() => {
    const samples = [...(threePhaseQuery.data?.items ?? [])].reverse()
    return {
      tooltip: { trigger: 'axis' },
      legend: { data: ['L1 V', 'L2 V', 'L3 V', 'L1 A', 'L2 A', 'L3 A'] },
      grid: { left: 55, right: 55, bottom: 55 },
      xAxis: {
        type: 'category',
        data: samples.map((sample) => formatInTimezone(sample.event_time, timezone, 'MM-DD HH:mm')),
      },
      yAxis: [
        { type: 'value', name: 'V' },
        { type: 'value', name: 'A' },
      ],
      dataZoom: [{ type: 'inside' }, { type: 'slider', height: 20 }],
      series: [
        ['L1 V', 'voltage_l1', 0], ['L2 V', 'voltage_l2', 0], ['L3 V', 'voltage_l3', 0],
        ['L1 A', 'current_l1', 1], ['L2 A', 'current_l2', 1], ['L3 A', 'current_l3', 1],
      ].map(([name, key, yAxisIndex]) => ({
        name, type: 'line', showSymbol: false, yAxisIndex,
        data: samples.map((sample) => sample[key as keyof ThreePhaseSample]),
      })),
    }
  }, [threePhaseQuery.data, timezone])

  const state = stateQuery.data
  const hasReportedState = Boolean(state?.station_id || state?.master_sn || state?.reported_at)
  const deviceOptions = (devicesQuery.data ?? []).map((device) => ({
    value: device.sn,
    label: `${device.sn}${device.model ? ` (${device.model})` : ''}`,
  }))

  return (
    <div>
      <Title level={4}><ClusterOutlined /> {t('parallel.title')}</Title>
      <Alert
        type="info"
        showIcon
        message={t('parallel.readOnlyTitle')}
        description={t('parallel.readOnlyDescription')}
        style={{ marginBottom: 16 }}
      />

      <Card style={{ marginBottom: 16 }}>
        <Space wrap>
          <Text strong>{t('parallel.selectDevice')}</Text>
          <Select
            showSearch
            value={selectedSN}
            options={deviceOptions}
            loading={devicesQuery.isLoading}
            placeholder={t('parallel.selectDevicePlaceholder')}
            style={{ width: 330 }}
            onChange={setSelectedSN}
            optionFilterProp="label"
          />
        </Space>
        {devicesQuery.isError && <Alert type="error" showIcon message={getApiErrorMessage(devicesQuery.error)} style={{ marginTop: 12 }} />}
      </Card>

      {!selectedSN && !devicesQuery.isLoading && !devicesQuery.isError && (
        <Card><Empty description={t('parallel.noDevices')} /></Card>
      )}
      {selectedSN && stateQuery.isError && (
        <Alert type="error" showIcon message={t('parallel.stateLoadFailed')} description={getApiErrorMessage(stateQuery.error)} />
      )}
      {selectedSN && stateQuery.isSuccess && !hasReportedState && (
        <Card><Empty description={t('parallel.noParallelData')} /></Card>
      )}
      {selectedSN && stateQuery.isSuccess && hasReportedState && !state?.enabled && (
        <Alert type="warning" showIcon message={t('parallel.disabled')} description={t('parallel.disabledDescription')} />
      )}

      {hasReportedState && state && (
        <>
          <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
            <Col xs={24} sm={12} lg={6}><Card><Statistic title={t('parallel.enabled')} value={state.enabled ? t('common.yes') : t('common.no')} /></Card></Col>
            <Col xs={24} sm={12} lg={6}><Card><Statistic title={t('parallel.mode')} value={state.mode || '-'} /></Card></Col>
            <Col xs={24} sm={12} lg={6}><Card><Statistic title={t('parallel.machineCount')} value={state.count ?? 0} /></Card></Col>
            <Col xs={24} sm={12} lg={6}><Card><Statistic title={t('parallel.activePower')} value={state.total_active_power ?? 0} suffix="W" precision={1} /></Card></Col>
          </Row>
          <Card title={t('parallel.currentState')} style={{ marginBottom: 16 }} loading={stateQuery.isLoading}>
            <Descriptions column={{ xs: 1, sm: 2, lg: 4 }} bordered size="small">
              <Descriptions.Item label={t('parallel.masterSN')}>{state.master_sn || '-'}</Descriptions.Item>
              <Descriptions.Item label={t('parallel.syncState')}><Tag color={state.sync_state === 'synced' ? 'success' : 'warning'}>{state.sync_state || '-'}</Tag></Descriptions.Item>
              <Descriptions.Item label={t('parallel.ratedPower')}>{number(state.total_rated_power)} W</Descriptions.Item>
              <Descriptions.Item label={t('parallel.reportedAt')}>{state.reported_at ? formatInTimezone(state.reported_at, timezone, 'YYYY-MM-DD HH:mm:ss') : '-'}</Descriptions.Item>
            </Descriptions>
            <Table
              style={{ marginTop: 16 }} rowKey={(item) => `${item.id}-${item.sn}`}
              columns={machineColumns} dataSource={state.machines ?? []} pagination={false}
              locale={{ emptyText: <Empty description={t('parallel.noMachineData')} /> }}
            />
          </Card>
        </>
      )}

      {state?.enabled && state.mode !== 'three_phase' && (
        <Alert type="info" showIcon message={t('parallel.notThreePhase')} />
      )}
      {isThreePhase && (
        <Card
          title={t('parallel.threePhaseHistory')}
          extra={<RangePicker showTime value={range} onChange={(value) => value?.[0] && value?.[1] && setRange([value[0], value[1]])} />}
        >
          {threePhaseQuery.isError && <Alert type="error" showIcon message={t('parallel.historyLoadFailed')} description={getApiErrorMessage(threePhaseQuery.error)} style={{ marginBottom: 16 }} />}
          {threePhaseQuery.isSuccess && threePhaseQuery.data.items.length === 0 && <Empty description={t('parallel.noThreePhaseData')} />}
          {Boolean(threePhaseQuery.data?.items.length) && <ReactECharts option={chartOption} style={{ height: 360 }} />}
          <Table
            rowKey={(item) => `${item.t}-${item.data_hash}`}
            columns={historyColumns}
            dataSource={threePhaseQuery.data?.items ?? []}
            loading={threePhaseQuery.isLoading}
            pagination={{ pageSize: 20, showSizeChanger: true }}
            scroll={{ x: 1800 }}
            size="small"
          />
        </Card>
      )}
    </div>
  )
}

export default ParallelPage
