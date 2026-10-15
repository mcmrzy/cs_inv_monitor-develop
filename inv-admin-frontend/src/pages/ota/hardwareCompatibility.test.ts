import { describe, expect, it } from 'vitest'
import { rollbackCoversHardware, hardwareCompatibilityLabel } from './hardwareCompatibility'

// Device compatibility verdicts are owned by the server (task-candidates /
// firmware-overview); the client only renders the range and reason codes.
describe('hardware compatibility presentation', () => {
  const firmware = { model: 'L10', board_codes: ['HW-1', 'HW-2'], hardware_versions: ['HW-1', 'HW-2'] }
  it('offers rollback only when its hardware range covers every published target', () => {
    expect(rollbackCoversHardware(firmware, { board_codes: ['HW-1'] })).toBe(false)
    expect(rollbackCoversHardware(firmware, { board_codes: ['HW-2', 'HW-1', 'HW-3'] })).toBe(true)
    expect(rollbackCoversHardware({ board_codes: [] }, firmware)).toBe(false)
  })
  it('shows distinct reasons for unknown hardware and no compatible firmware', () => {
    expect(hardwareCompatibilityLabel('hardware_version_unknown', (k) => k)).toBe('ota.hardwareUnknown')
    expect(hardwareCompatibilityLabel('no_compatible_firmware', (k) => k)).toBe('ota.noCompatibleFirmware')
    expect(hardwareCompatibilityLabel('', (k) => k)).toBe('')
  })
  it('labels every server verdict and keeps unknown codes visible', () => {
    const map: Record<string, string> = {
      identity_unverified: 'hw.reasonIdentityUnverified',
      identity_conflict: 'hw.reasonIdentityConflict',
      module_identity_missing: 'hw.reasonModuleMissing',
      module_absent: 'hw.reasonModuleAbsent',
      firmware_scope_missing: 'hw.reasonScopeMissing',
      firmware_incompatible: 'hw.reasonIncompatible',
      device_protection_required: 'hw.reasonProtectionRequired',
      firmware_not_published: 'hw.reasonNotPublished',
      firmware_outside_rollout: 'hw.reasonOutsideRollout',
      identity_changed: 'hw.reasonIdentityChanged',
      verification_pending: 'hw.reasonVerificationPending',
    }
    for (const [reason, key] of Object.entries(map)) {
      expect(hardwareCompatibilityLabel(reason, (k) => k)).toBe(key)
    }
    // An unmapped verdict must show its raw code, never an empty tag.
    expect(hardwareCompatibilityLabel('brand_new_reason', (k) => k)).toBe('brand_new_reason')
  })
})
