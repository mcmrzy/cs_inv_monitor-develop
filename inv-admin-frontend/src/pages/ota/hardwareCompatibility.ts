import type { TranslateFn } from './firmwarePresentation'

/** Reasons come from the server verdict; unknown codes must stay visible, not blank. */
export function hardwareCompatibilityLabel(reason: string | undefined, t: TranslateFn): string {
  if (!reason) return ''
  const keys: Record<string, string> = {
    hardware_version_unknown: 'ota.hardwareUnknown',
    no_compatible_firmware: 'ota.noCompatibleFirmware',
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
  const key = keys[reason]
  return key ? t(key) : reason
}
