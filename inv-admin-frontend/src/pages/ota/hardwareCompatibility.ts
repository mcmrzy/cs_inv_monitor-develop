import type { TranslateFn } from './firmwarePresentation'

interface HardwareRange { hardware_versions?: string[] }
const normalize = (version?: string) => (version ?? '').trim().toUpperCase()

export function firmwareSupportsDevice(
  firmware: HardwareRange & { model: string },
  device: { model: string; hardware_version?: string },
): boolean {
  const hardware = normalize(device.hardware_version)
  return !!hardware && firmware.model === device.model
    && (firmware.hardware_versions ?? []).some((v) => normalize(v) === hardware)
}

export function rollbackCoversHardware(firmware: HardwareRange, rollback: HardwareRange): boolean {
  const source = (firmware.hardware_versions ?? []).map(normalize).filter(Boolean)
  const destination = new Set((rollback.hardware_versions ?? []).map(normalize).filter(Boolean))
  return source.length > 0 && source.every((v) => destination.has(v))
}

export function hardwareCompatibilityLabel(reason: string | undefined, t: TranslateFn): string {
  if (reason === 'hardware_version_unknown') return t('ota.hardwareUnknown')
  if (reason === 'no_compatible_firmware') return t('ota.noCompatibleFirmware')
  return ''
}
