import { fireEvent, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderWithProviders } from '@/test/test-utils'
import { resolveFieldMeta } from '../config/conversion'
import type { DeviceConfigApi } from '../hooks/useDeviceConfig'
import { FieldRow } from './FieldControl'

function config(values: Record<string, number> = {}, reportedAt = '2026-10-20T01:00:00Z') {
  return {
    getEditValue: (key: string) => values[key],
    getMeta: (key: string) => resolveFieldMeta(new Map(), key),
    fieldLabel: (key: string) => key,
    enumLabel: (key: string) => key,
    isSynced: () => 'none', canEdit: () => true,
    controlState: { reported_at: reportedAt },
  } as unknown as DeviceConfigApi
}

describe('未回报与重新读取的参数控件', () => {
  it('未回报的开关显示未知状态', () => {
    renderWithProviders(<FieldRow cfg={config()} paramKey="set_buzzer" />)
    expect(screen.getByText('未回报')).toBeInTheDocument()
    expect(screen.queryByRole('switch')).not.toBeInTheDocument()
  })

  it('未回报的枚举不默认选中第一项', () => {
    const { container } = renderWithProviders(<FieldRow cfg={config()} paramKey="set_output_priority" />)
    expect(container.querySelector('input:checked')).toBeNull()
  })

  it('未回报的充电优先级不显示默认排序', () => {
    const { container } = renderWithProviders(<FieldRow cfg={config()} paramKey="set_charge_priority" />)
    expect(container.querySelector('input:checked')).toBeNull()
    expect(screen.queryByText('电池')).not.toBeInTheDocument()
  })

  it('新回报到达时，即使设备值没变也恢复设备实际值', () => {
    const { rerender } = renderWithProviders(<FieldRow cfg={config({ set_output_voltage: 230 })} paramKey="set_output_voltage" />)
    fireEvent.change(screen.getByRole('spinbutton'), { target: { value: '240' } })
    expect(screen.getByRole('spinbutton')).toHaveValue('240.0')
    rerender(<FieldRow cfg={config({ set_output_voltage: 230 }, '2026-10-20T01:00:01Z')} paramKey="set_output_voltage" />)
    expect(screen.getByRole('spinbutton')).toHaveValue('230.0')
  })
})
