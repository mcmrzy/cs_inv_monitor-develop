import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import StorageBatteryVisual from './StorageBatteryVisual'

afterEach(cleanup)

describe('Storage battery state presentation', () => {
  it('preserves a real empty battery as a readable zero, with no energy surface', () => {
    const { container } = render(<StorageBatteryVisual soc={0} unavailableLabel="Unavailable" />)
    expect(screen.getByRole('meter', { name: 'SOC' })).toHaveAttribute('aria-valuenow', '0')
    expect(screen.getByRole('meter')).toHaveAttribute('aria-valuetext', '0%')
    expect(screen.getByText('0.0')).toBeInTheDocument()
    expect(container.querySelector('[data-energy-fill]')).toBeNull()
  })

  it.each([null, -1, 101, Number.NaN])('renders unavailable SOC %s without a percentage or active fill', soc => {
    const { container } = render(<StorageBatteryVisual soc={soc} unavailableLabel="Unavailable" />)
    expect(screen.getByRole('meter')).not.toHaveAttribute('aria-valuenow')
    expect(screen.getByRole('meter')).toHaveAttribute('aria-valuetext', 'Unavailable')
    expect(screen.getByText('--')).toBeInTheDocument()
    expect(screen.queryByText('%')).not.toBeInTheDocument()
    expect(container.querySelector('[data-energy-fill]')).toBeNull()
  })

  it('removes energy and numeric semantics as soon as the snapshot becomes unavailable', () => {
    const { container, rerender } = render(<StorageBatteryVisual soc={72.6} unavailableLabel="Unavailable" />)
    expect(screen.getByRole('meter')).toHaveAttribute('aria-valuenow', '72.6')
    expect(container.querySelector('[data-energy-fill]')).not.toBeNull()
    rerender(<StorageBatteryVisual soc={null} unavailableLabel="Unavailable" />)
    expect(screen.getByRole('meter')).not.toHaveAttribute('aria-valuenow')
    expect(screen.queryByText('72.6')).not.toBeInTheDocument()
    expect(container.querySelector('[data-energy-fill]')).toBeNull()
  })

  it('keeps cabinet gradient and glass references independent when multiple devices are visible', () => {
    const { container } = render(<><StorageBatteryVisual soc={35} unavailableLabel="Unavailable" /><StorageBatteryVisual soc={80} unavailableLabel="Unavailable" /></>)
    const ids = [...container.querySelectorAll('[id]')].map(element => element.id)
    expect(new Set(ids).size).toBe(ids.length)
    for (const element of container.querySelectorAll('[fill^="url"], [clip-path]')) {
      const reference = element.getAttribute('fill')?.match(/^url\(#(.+)\)$/)?.[1] ?? element.getAttribute('clip-path')?.match(/^url\(#(.+)\)$/)?.[1]
      expect(ids).toContain(reference)
    }
  })
})
