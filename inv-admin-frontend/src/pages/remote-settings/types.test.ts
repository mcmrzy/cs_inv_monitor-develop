import { describe, expect, it } from 'vitest'
import { commandRecordPresentation, STAGE_MAP } from './types'

describe('command execution stages', () => {
  it('submitted stays visibly unconfirmed even with legacy success', () => {
    for (const record of [
      { status: 'submitted' },
      { status: 'submitted', stage: 'completed' },
      { status: 'success', stage: 'submitted' },
      { status: 'success', response_data: { stage: 'submitted' } },
    ]) {
      expect(commandRecordPresentation(record)).toEqual({
        color: 'warning', label_zh: '已保存并提交，设备生效未确认',
      })
    }
    expect(STAGE_MAP.submitted.color).not.toBe('success')
  })
  it('ack cannot display execution success; applied/completed may', () => {
    expect(commandRecordPresentation({ status: 'acknowledged' }).color).toBe('processing')
    expect(commandRecordPresentation({ status: 'executing' }).color).not.toBe('success')
    for (const stage of ['applied', 'completed']) {
      expect(commandRecordPresentation({ stage }).color).toBe('success')
    }
    expect(commandRecordPresentation({ status: 'failed', stage: 'completed' }).color).toBe('error')
    expect(commandRecordPresentation({ status: 'unexpected' }).color).not.toBe('success')
  })
})
