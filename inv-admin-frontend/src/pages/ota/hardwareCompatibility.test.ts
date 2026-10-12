import { describe, expect, it } from 'vitest'
import { firmwareSupportsDevice, rollbackCoversHardware, hardwareCompatibilityLabel } from './hardwareCompatibility'

describe('explicit hardware compatibility', () => {
  const firmware = { model: 'L10', hardware_versions: ['HW-1', 'HW-2'] }
  it('filters same-model devices by explicit versions with trim and uppercase only', () => {
    expect(firmwareSupportsDevice(firmware, { model: 'L10', hardware_version: ' hw-1 ' })).toBe(true)
    expect(firmwareSupportsDevice(firmware, { model: 'L10', hardware_version: 'HW-3' })).toBe(false)
    expect(firmwareSupportsDevice(firmware, { model: 'L10', hardware_version: '1' })).toBe(false)
    expect(firmwareSupportsDevice(firmware, { model: 'OTHER', hardware_version: 'HW-1' })).toBe(false)
  })
  it('rejects unknown device hardware and legacy empty firmware ranges', () => {
    expect(firmwareSupportsDevice(firmware, { model: 'L10' })).toBe(false)
    expect(firmwareSupportsDevice({ model: 'L10' }, { model: 'L10', hardware_version: 'HW-1' })).toBe(false)
  })
  it('offers rollback only when its hardware range covers every published target', () => {
    expect(rollbackCoversHardware(firmware, { hardware_versions: ['HW-1'] })).toBe(false)
    expect(rollbackCoversHardware(firmware, { hardware_versions: ['HW-2', 'HW-1', 'HW-3'] })).toBe(true)
    expect(rollbackCoversHardware({ hardware_versions: [] }, firmware)).toBe(false)
  })
  it('shows distinct reasons for unknown hardware and no compatible firmware', () => {
    expect(hardwareCompatibilityLabel('hardware_version_unknown', (k) => k)).toBe('ota.hardwareUnknown')
    expect(hardwareCompatibilityLabel('no_compatible_firmware', (k) => k)).toBe('ota.noCompatibleFirmware')
    expect(hardwareCompatibilityLabel('', (k) => k)).toBe('')
  })
})
