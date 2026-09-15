import { describe, expect, it } from 'vitest'
import { buildFirmwareUploadFormData } from './firmwareUpload'

describe('buildFirmwareUploadFormData', () => {
  it('leaves version, size and hashes to the backend', () => {
    const body = buildFirmwareUploadFormData({
      file: new File(['firmware'], 'CSL10_6.2K_arm_1.2.3.bin'),
      model: 'CSL10-6K2',
      targetChip: 'arm',
      changelog: '稳定性优化',
    })

    expect(body.get('file')).toBeInstanceOf(File)
    expect(body.get('model')).toBe('CSL10-6K2')
    expect(body.get('target_chip')).toBe('arm')
    for (const field of ['version', 'file_size', 'file_sha256', 'file_md5']) {
      expect(body.has(field)).toBe(false)
    }
  })
})
