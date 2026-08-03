import React, { useState } from 'react'
import {
  Row, Col, InputNumber, Select, Switch, Button, Card, Tag, App, Modal,
  Table, Typography, Space, Tooltip, Spin, Empty, Divider,
} from 'antd'
import { SendOutlined, HistoryOutlined, WarningOutlined, ThunderboltOutlined } from '@ant-design/icons'
import type { TableProps } from 'antd'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { modelApi, type ModelCommandCapability } from '@/services/modelApi'
import { deviceApi } from '@/services/deviceApi'
import type { CommandRecord } from '../types'
import useTranslation from '@/hooks/useTranslation'

const { Text } = Typography

// ── parameter_schema.args 结构（与 device_model_commands.parameter_schema 一致）──
interface SchemaArg {
  key: string
  type: 'integer' | 'number' | 'boolean' | 'string'
  min?: number
  max?: number
  enum?: number[] | string[]
  unit?: string
  default?: number | boolean | string
  required?: boolean
  label?: string
  description?: string
}

interface ParameterSchema {
  args: SchemaArg[]
}

// 命令 code → 中文名兜底（display_name_key 未接入翻译时使用）
const COMMAND_LABEL_FALLBACK_ZH: Record<string, string> = {
  set_output_priority: '输出优先级',
  set_max_charge_current: '最大充电电流',
  set_battery_capacity: '电池容量',
  set_battery_type: '电池类型',
  set_output_voltage: '输出电压',
  set_output_frequency: '输出频率',
  set_master_slave: '主从设置',
  set_ac_charge_current: 'AC 充电电流',
  set_ac_output_mode: 'AC 输出模式',
  set_charge_priority: '充电优先级',
  set_low_volt_return_utl: '低压回市电',
  set_high_volt_return_bat: '高压回电池',
  set_soc_cutoff: 'SOC 截止',
  set_charge_cutoff: '充电截止',
  set_equalize_enable: '均衡使能',
  set_equalize_voltage: '均衡电压',
  set_equalize_time: '均衡时间',
  set_gen_start_voltage: '发电机启动电压',
  set_gen_stop_voltage: '发电机停止电压',
  set_soc_back_utl: 'SOC 回市电',
  set_soc_back_bat: 'SOC 回电池',
  set_soc_back_gen: 'SOC 回发电机',
  set_soc_close_gen: 'SOC 关闭发电机',
  set_gen_rate_watt: '发电机额定功率',
  set_alarm_control: '告警控制',
  set_buzzer: '蜂鸣器',
  set_utc_time: 'UTC 时间同步',
}

const COMMAND_LABEL_FALLBACK_EN: Record<string, string> = {
  set_output_priority: 'Output Priority',
  set_max_charge_current: 'Max Charge Current',
  set_battery_capacity: 'Battery Capacity',
  set_battery_type: 'Battery Type',
  set_output_voltage: 'Output Voltage',
  set_output_frequency: 'Output Frequency',
  set_master_slave: 'Master/Slave',
  set_ac_charge_current: 'AC Charge Current',
  set_ac_output_mode: 'AC Output Mode',
  set_charge_priority: 'Charge Priority',
  set_low_volt_return_utl: 'Low Volt Return Utility',
  set_high_volt_return_bat: 'High Volt Return Battery',
  set_soc_cutoff: 'SOC Cutoff',
  set_charge_cutoff: 'Charge Cutoff',
  set_equalize_enable: 'Equalize Enable',
  set_equalize_voltage: 'Equalize Voltage',
  set_equalize_time: 'Equalize Time',
  set_gen_start_voltage: 'Gen Start Voltage',
  set_gen_stop_voltage: 'Gen Stop Voltage',
  set_soc_back_utl: 'SOC Back Utility',
  set_soc_back_bat: 'SOC Back Battery',
  set_soc_back_gen: 'SOC Back Generator',
  set_soc_close_gen: 'SOC Close Generator',
  set_gen_rate_watt: 'Generator Rated Power',
  set_alarm_control: 'Alarm Control',
  set_buzzer: 'Buzzer',
  set_utc_time: 'UTC Time Sync',
}

// 解析 parameter_schema（兼容字符串与对象两种存储形态）
function parseSchema(raw: unknown): ParameterSchema | null {
  if (!raw) return null
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw)
      return parsed && Array.isArray(parsed.args) ? parsed as ParameterSchema : null
    } catch {
      return null
    }
  }
  if (typeof raw === 'object' && raw !== null && Array.isArray((raw as ParameterSchema).args)) {
    return raw as ParameterSchema
  }
  return null
}

const STAGE_COLORS: Record<string, string> = {
  pending: 'default',
  acknowledged: 'processing',
  executing: 'warning',
  completed: 'success',
  failed: 'error',
}

const STAGE_LABELS: Record<string, Record<string, string>> = {
  zh: {
    pending: '等待中', acknowledged: '已确认', executing: '执行中', completed: '已完成', failed: '失败',
  },
  en: {
    pending: 'Pending', acknowledged: 'Acked', executing: 'Executing', completed: 'Completed', failed: 'Failed',
  },
}

interface ModelCommandsSectionProps {
  sn: string
  modelId: number
}

const ModelCommandsSection: React.FC<ModelCommandsSectionProps> = ({ sn, modelId }) => {
  const { message, modal } = App.useApp()
  const { t, lang } = useTranslation()
  const queryClient = useQueryClient()
  const [sendingCode, setSendingCode] = useState<string | null>(null)
  const [paramsMap, setParamsMap] = useState<Record<string, Record<string, unknown>>>({})

  const { data: commands, isLoading } = useQuery({
    queryKey: ['model-commands-v2', modelId],
    queryFn: () =>
      modelApi.getCommandCapabilities(modelId).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (Array.isArray(d) ? d : d?.items ?? []) as ModelCommandCapability[]
      }),
    enabled: modelId > 0,
    staleTime: 60_000,
  })

  const { data: history, refetch: refetchHistory } = useQuery({
    queryKey: ['device-commands', sn],
    queryFn: () =>
      deviceApi.getCommands(sn, { page: 1, page_size: 10 }).then((r) => {
        const d = (r as any).data?.data ?? (r as any).data
        return (d?.items ?? (Array.isArray(d) ? d : [])) as CommandRecord[]
      }),
    refetchInterval: 10000,
  })

  const commandLabel = (code: string): string => {
    const key = `commands.${code}`
    if (t(key) !== key) return t(key)
    return lang === 'en' ? COMMAND_LABEL_FALLBACK_EN[code] ?? code : COMMAND_LABEL_FALLBACK_ZH[code] ?? code
  }

  const riskTag = (level: number) => {
    if (level >= 3) return <Tag color="red">{t('remote.riskHigh')}</Tag>
    if (level === 2) return <Tag color="orange">{t('remote.riskMedium')}</Tag>
    return <Tag color="green">{t('remote.riskLow')}</Tag>
  }

  const updateParam = (code: string, key: string, value: unknown) => {
    setParamsMap((prev) => ({ ...prev, [code]: { ...(prev[code] ?? {}), [key]: value } }))
  }

  const handleSend = (cmd: ModelCommandCapability) => {
    const schema = parseSchema(cmd.parameter_schema)
    const args = schema?.args ?? []
    const rawParams = paramsMap[cmd.command_code] ?? {}
    const params: Record<string, unknown> = {}
    for (const arg of args) {
      const v = rawParams[arg.key]
      if (v === undefined) {
        if (arg.default !== undefined) {
          params[arg.key] = arg.default
        } else if (arg.required) {
          message.warning(`${commandLabel(cmd.command_code)}: ${arg.key} ${t('remote.paramRequired')}`)
          return
        } else {
          params[arg.key] = arg.type === 'boolean' ? false : (arg.type === 'integer' ? 0 : '')
        }
      } else {
        params[arg.key] = v
      }
    }

    const doSend = () => {
      setSendingCode(cmd.command_code)
      deviceApi
        .sendCommand(sn, { command: cmd.command_code, params })
        .then((res: any) => {
          const taskId = res?.data?.data?.task_id ?? res?.data?.task_id ?? ''
          message.success(t('remote.commandSent', { taskId }))
          setParamsMap((prev) => ({ ...prev, [cmd.command_code]: {} }))
          void queryClient.invalidateQueries({ queryKey: ['device-commands', sn] })
          void refetchHistory()
        })
        .catch((err: any) => {
          const detail = err?.response?.data?.data?.reject_detail ?? err?.response?.data?.message ?? err?.message ?? ''
          message.error(`${t('remote.commandSendFailed')}${detail ? `: ${detail}` : ''}`)
        })
        .finally(() => setSendingCode(null))
    }

    if (cmd.risk_level >= 3) {
      modal.confirm({
        title: t('remote.confirmSendTitle'),
        content: t('remote.confirmSendContent', { sn, cmd: commandLabel(cmd.command_code) }),
        okText: t('remote.confirmExecute'),
        cancelText: t('remote.cancel'),
        okButtonProps: { danger: true },
        onOk: doSend,
      })
    } else {
      doSend()
    }
  }

  const historyColumns: TableProps<CommandRecord>['columns'] = [
    {
      title: t('remote.commandCode'), dataIndex: 'command_code', key: 'command_code', width: 200,
      render: (_, r) => <Space size={6}><Text code>{r.command_code}</Text></Space>,
    },
    {
      title: t('remote.stage'), dataIndex: 'stage', key: 'stage', width: 110,
      render: (_, r) => {
        const color = r.stage === 'completed' ? (r.success === false ? 'error' : 'success') : STAGE_COLORS[r.stage] ?? 'default'
        const label = r.stage === 'completed' && r.success === false
          ? t('remote.stageFailed')
          : STAGE_LABELS[lang][r.stage] ?? r.stage
        return <Tag color={color}>{label}</Tag>
      },
    },
    {
      title: t('remote.commandParams'), dataIndex: 'params', key: 'params', ellipsis: true,
      render: (_, r) => r.params ? <Text type="secondary" style={{ fontSize: 12 }}>{JSON.stringify(r.params)}</Text> : '-',
    },
    {
      title: t('remote.sentAt'), dataIndex: 'created_at', key: 'created_at', width: 170,
      render: (v: string) => v ? <Text type="secondary" style={{ fontSize: 12 }}>{v}</Text> : '-',
    },
    {
      title: t('remote.result'), dataIndex: 'result', key: 'result', ellipsis: true,
      render: (_, r) => r.result && r.result.length ? <Text type="secondary" style={{ fontSize: 12 }}>{JSON.stringify(r.result)}</Text> : '-',
    },
  ]

  return (
    <div>
      <Card
        size="small"
        title={
          <Space size={8}>
            <ThunderboltOutlined style={{ color: '#4f6ef7' }} />
            <span>{t('remote.dynamicCommands')}</span>
            <Tag color="blue" style={{ marginLeft: 4 }}>CS-L10-6K2</Tag>
          </Space>
        }
        style={{ borderRadius: 12, marginBottom: 16, boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
      >
        <Text type="secondary" style={{ fontSize: 13, display: 'block', marginBottom: 12 }}>
          {t('remote.dynamicCommandsDesc')}
        </Text>

        <Spin spinning={isLoading}>
          {commands && commands.length > 0 ? (
            <Row gutter={[16, 16]}>
              {commands.map((cmd) => {
                const schema = parseSchema(cmd.parameter_schema)
                const args = schema?.args ?? []
                const values = paramsMap[cmd.command_code] ?? {}
                const sending = sendingCode === cmd.command_code
                return (
                  <Col xs={24} md={12} xl={8} key={cmd.command_code}>
                    <Card
                      size="small"
                      style={{ borderRadius: 10, borderLeft: '3px solid #4f6ef7', height: '100%' }}
                      title={
                        <Space size={6} wrap>
                          <span style={{ fontSize: 13, fontWeight: 600 }}>{commandLabel(cmd.command_code)}</span>
                          {riskTag(cmd.risk_level)}
                        </Space>
                      }
                      extra={<Text code style={{ fontSize: 11 }}>{cmd.command_code}</Text>}
                    >
                      {args.length === 0 ? (
                        <Text type="secondary" style={{ fontSize: 12 }}>{t('remote.noParams')}</Text>
                      ) : (
                        <Space direction="vertical" style={{ width: '100%' }} size={10}>
                          {args.map((arg) => {
                            const label = arg.label ?? arg.key
                            const unit = arg.unit ? `(${arg.unit})` : ''
                            const hasEnum = Array.isArray(arg.enum) && arg.enum.length > 0
                            if (arg.type === 'boolean') {
                              return (
                                <div key={arg.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                  <Text style={{ fontSize: 13, color: '#888' }}>{label}</Text>
                                  <Switch
                                    size="small"
                                    checked={Boolean(values[arg.key] ?? arg.default ?? false)}
                                    onChange={(v) => updateParam(cmd.command_code, arg.key, v)}
                                  />
                                </div>
                              )
                            }
                            const input = hasEnum ? (
                              <Select
                                style={{ width: 150 }}
                                size="small"
                                placeholder={label}
                                value={values[arg.key] as number | undefined}
                                options={(arg.enum as number[]).map((v) => ({ label: `${v}${arg.unit ? ` ${arg.unit}` : ''}`, value: v }))}
                                onChange={(v) => updateParam(cmd.command_code, arg.key, v)}
                              />
                            ) : (
                              <InputNumber
                                style={{ width: 150 }}
                                size="small"
                                min={arg.min}
                                max={arg.max}
                                step={arg.type === 'number' ? 0.1 : 1}
                                placeholder={label}
                                value={values[arg.key] as number | undefined}
                                onChange={(v) => updateParam(cmd.command_code, arg.key, v)}
                              />
                            )
                            return (
                              <div key={arg.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
                                <Text style={{ fontSize: 13, color: '#888' }}>{label}{unit}</Text>
                                {input}
                              </div>
                            )
                          })}
                        </Space>
                      )}
                      <Divider style={{ margin: '10px 0 8px' }} />
                      <Button
                        type="primary"
                        size="small"
                        block
                        icon={<SendOutlined />}
                        loading={sending}
                        disabled={cmd.is_enabled === false}
                        onClick={() => handleSend(cmd)}
                      >
                        {cmd.is_enabled === false ? t('remote.disabled') : t('remote.send')}
                      </Button>
                    </Card>
                  </Col>
                )
              })}
            </Row>
          ) : (
            !isLoading && <Empty description={t('remote.noCommands')} image={Empty.PRESENTED_IMAGE_SIMPLE} />
          )}
        </Spin>
      </Card>

      <Card
        size="small"
        title={<Space size={8}><HistoryOutlined style={{ color: '#4f6ef7' }} /><span>{t('remote.commandHistory')}</span></Space>}
        style={{ borderRadius: 12, boxShadow: '0 1px 4px rgba(0,0,0,0.06)' }}
      >
        <Table<CommandRecord>
          rowKey="task_id"
          size="small"
          columns={historyColumns}
          dataSource={history ?? []}
          pagination={false}
          scroll={{ y: 280 }}
          locale={{ emptyText: <Empty description={t('remote.noHistory')} image={Empty.PRESENTED_IMAGE_SIMPLE} /> }}
        />
      </Card>
    </div>
  )
}

export default ModelCommandsSection
