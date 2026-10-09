import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { DeviceUpgrade } from '@/types'
import OTAProgressCell from './OTAProgressCell'

vi.mock('@/hooks/useTranslation', () => ({ default: () => ({ t: (key: string) => key }) }))
const record = { status: 'upgrading', stage: 'receiving', progress: 84 } as DeviceUpgrade

describe('OTAProgressCell', () => {
  it('labels legacy weighted reports as overall, not phase', () => {
    render(<OTAProgressCell record={record} />)
    expect(screen.getByText('ota.stageTransferring')).toBeInTheDocument()
    expect(screen.getByText('--')).toBeInTheDocument()
    expect(screen.getByText('ota.overallProgress 84%')).toBeInTheDocument()
    expect(screen.queryByRole('progressbar')).not.toBeInTheDocument()
  })
  it('preserves phase zero and separates overall', () => {
    render(<OTAProgressCell record={{ ...record, stage_progress: 0, overall_progress: 70 }} />)
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '0')
    expect(screen.getByText('ota.overallProgress 70%')).toBeInTheDocument()
  })
  it('does not show completion when just a phase reaches 100', () => {
    const { container } = render(<OTAProgressCell record={{ ...record, stage_progress: 100 }} />)
    expect(container.querySelector('.ant-progress-status-success')).toBeNull()
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuenow', '100')
  })
  it('does not fabricate zero for absent or malformed percentages', () => {
    render(<OTAProgressCell record={{ ...record, progress: NaN, stage_progress: -1 }} />)
    expect(screen.getByText('ota.overallProgress --')).toBeInTheDocument()
  })
})
