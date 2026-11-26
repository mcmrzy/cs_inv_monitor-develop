import { render } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import EnergyFlowDiagram from './EnergyFlowDiagram'

vi.mock('@/hooks/useTranslation', () => ({ default: () => ({ t: (key: string) => key }) }))

describe('grid connection', () => {
  const props = { pvPower: 0, loadPower: 0, battPower: 600, battSoc: 50 }
  it('imports for battery charging even with no load', () => {
    const { container } = render(<EnergyFlowDiagram {...props} gridPower={600} />)
    const line = container.querySelector('#grid-inv')!
    expect(line.getAttribute('d')).toBe('M 470 275 L 350 275')
    expect(line.getAttribute('class')).toBe('flow-path-active')
    expect(container.textContent).toContain('station.gridImport')
  })
  it('reverses one connection for export and stops it at zero or unknown', () => {
    const { container, rerender } = render(<EnergyFlowDiagram {...props} gridPower={-600} />)
    expect(container.querySelector('#grid-inv')!.getAttribute('d')).toBe('M 350 275 L 470 275')
    expect(container.textContent).toContain('station.gridExport')
    for (const gridPower of [0, null, 3]) {
      rerender(<EnergyFlowDiagram {...props} gridPower={gridPower} />)
      const line = container.querySelector('#grid-inv')!
      expect(line.getAttribute('class')).toBe('flow-path-inactive')
      expect(line.hasAttribute('marker-end')).toBe(false)
    }
    rerender(<EnergyFlowDiagram {...props} gridPower={null} />)
    expect(container.textContent).toContain('--')
  })
})
