import { describe, it, expect } from 'vitest'
import {
  firmwareModuleLabel,
  sanitizeLegacyFirmwareLabel,
  displayFirmwareModuleLabel,
  normalizeFirmwareTarget,
  canRemoteUpgradeFirmwareModule,
} from './firmwarePresentation'
import otaLocales from '@/locales/ota'

const t = (key: string) => key

describe('firmwarePresentation', () => {
  describe('firmwareModuleLabel', () => {
    it('maps known targets to user-facing keys without chip suffix', () => {
      expect(firmwareModuleLabel('arm', t)).toBe('ota.moduleArm')
      expect(firmwareModuleLabel('ESP', t)).toBe('ota.moduleEsp')
      expect(firmwareModuleLabel(' dsp ', t)).toBe('ota.moduleDsp')
      expect(firmwareModuleLabel('BMS', t)).toBe('ota.moduleBms')
    })

    it('uses a generic customer-facing label for unknown values', () => {
      expect(firmwareModuleLabel('wifi', t)).toBe('ota.moduleUnknown')
      expect(firmwareModuleLabel('', t)).toBe('ota.moduleUnknown')
      expect(firmwareModuleLabel(null, t)).toBe('ota.moduleUnknown')
    })

    it('uses the approved functional responsibility names in both locales', () => {
      expect(otaLocales.zh['ota.moduleArm']).toBe('系统主控')
      expect(otaLocales.zh['ota.moduleDsp']).toBe('功率控制')
      expect(otaLocales.zh['ota.moduleUnknown']).toBe('设备组件')
      expect(otaLocales.en['ota.moduleDsp']).toBe('Power Control')
      expect(otaLocales.en['ota.moduleUnknown']).toBe('Device Component')
    })
  })

  describe('sanitizeLegacyFirmwareLabel', () => {
    it('strips half-width parenthesized chip suffixes', () => {
      expect(sanitizeLegacyFirmwareLabel('System Control (ARM)')).toBe('System Control')
      expect(sanitizeLegacyFirmwareLabel('Communication (esp)')).toBe('Communication')
    })

    it('strips full-width parenthesized chip suffixes', () => {
      expect(sanitizeLegacyFirmwareLabel('系统中控（ARM）')).toBe('系统中控')
      expect(sanitizeLegacyFirmwareLabel('通信采集（ESP）')).toBe('通信采集')
    })

    it('normalizes full-width brackets to half-width and strips suffix', () => {
      expect(sanitizeLegacyFirmwareLabel('计算控制［DSP］')).toBe('计算控制')
      expect(sanitizeLegacyFirmwareLabel('电池管理【BMS】')).toBe('电池管理')
    })

    it('strips separator-attached chip tokens (case-insensitive)', () => {
      expect(sanitizeLegacyFirmwareLabel('计算控制-dsp')).toBe('计算控制')
      expect(sanitizeLegacyFirmwareLabel('电池管理_bms')).toBe('电池管理')
      expect(sanitizeLegacyFirmwareLabel('系统中控/ARM')).toBe('系统中控')
      expect(sanitizeLegacyFirmwareLabel('Communication |ESP')).toBe('Communication')
    })

    it('strips chip prefix tokens', () => {
      expect(sanitizeLegacyFirmwareLabel('ARM-System Control')).toBe('System Control')
    })

    it('returns empty string when only a chip token remains', () => {
      expect(sanitizeLegacyFirmwareLabel('(ARM)')).toBe('')
      expect(sanitizeLegacyFirmwareLabel('  esp  ')).toBe('esp')
      expect(sanitizeLegacyFirmwareLabel('')).toBe('')
      expect(sanitizeLegacyFirmwareLabel(null)).toBe('')
    })
  })

  describe('displayFirmwareModuleLabel', () => {
    it('prefers cleaned legacy label over module mapping', () => {
      expect(displayFirmwareModuleLabel('arm', '系统中控（ARM）', t)).toBe('系统中控')
      expect(displayFirmwareModuleLabel('esp', '', t)).toBe('ota.moduleEsp')
    })
  })

  describe('normalizeFirmwareTarget', () => {
    it('lowercases and trims', () => {
      expect(normalizeFirmwareTarget(' ARM ')).toBe('arm')
      expect(normalizeFirmwareTarget(undefined)).toBe('')
    })
  })

  describe('canRemoteUpgradeFirmwareModule', () => {
    const eligible = {
      supported: true,
      connected: true,
      eligible: true,
      supported_channels: ['remote', 'ble', 'wifi_ap'],
    }

    it('allows only eligible connected modules with the remote channel', () => {
      expect(canRemoteUpgradeFirmwareModule(eligible)).toBe(true)
      expect(canRemoteUpgradeFirmwareModule({ ...eligible, eligible: false })).toBe(false)
      expect(canRemoteUpgradeFirmwareModule({ ...eligible, connected: false })).toBe(false)
      expect(canRemoteUpgradeFirmwareModule({ ...eligible, supported: false })).toBe(false)
      expect(canRemoteUpgradeFirmwareModule({ ...eligible, supported_channels: ['ble'] })).toBe(false)
    })

    it('fails closed when canonical eligibility fields are missing', () => {
      expect(canRemoteUpgradeFirmwareModule({})).toBe(false)
    })
  })
})
