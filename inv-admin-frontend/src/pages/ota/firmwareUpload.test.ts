import { describe, expect, it } from 'vitest'
import { buildFirmwareUploadFormData } from './firmwareUpload'

describe('buildFirmwareUploadFormData', () => {
  it('uploads explicit board codes without requiring a legacy hardware range', () => {
    const body = buildFirmwareUploadFormData({ file: new File(['x'], 'x.bin'), model: 'L10', targetChip: 'dsp', hardwareVersions: [], boardCodes: ['dsp-A', 'dsp-A'] } as any)
    expect(JSON.parse(String(body.get('board_codes')))).toEqual(['dsp-A'])
    expect(body.has('hardware_versions')).toBe(false)
  })
  it('leaves version, size and hashes to the backend', () => {
    const body = buildFirmwareUploadFormData({
      file: new File(['firmware'], 'CSL10_6.2K_arm_1.2.3.bin'),
      model: 'CSL10-6K2',
      targetChip: 'arm',
      hardwareVersions: ['HW-1', 'HW-2'],
      changelog: '稳定性优化',
    })

    expect(body.get('file')).toBeInstanceOf(File)
    expect(body.get('model')).toBe('CSL10-6K2')
    expect(body.get('target_chip')).toBe('arm')
    expect(JSON.parse(String(body.get('hardware_versions')))).toEqual(['HW-1', 'HW-2'])
    for (const field of ['version', 'file_size', 'file_sha256', 'file_md5']) {
      expect(body.has(field)).toBe(false)
    }
  })
  it('uploads without any hardware or board range', () => {
    const body = buildFirmwareUploadFormData({
      file: new File(['x'], 'x.bin'), model: 'L10', targetChip: 'esp',
    })
    expect(body.get('model')).toBe('L10')
    expect(body.get('target_chip')).toBe('esp')
    expect(body.has('hardware_versions')).toBe(false)
    expect(body.has('board_codes')).toBe(false)
  })
})
