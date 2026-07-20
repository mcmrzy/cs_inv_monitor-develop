import { describe, expect, it } from 'vitest'
import locales from './index'

const productionSources = import.meta.glob(
  [
    '../**/*.ts',
    '../**/*.tsx',
    '!../**/*.test.ts',
    '!../**/*.test.tsx',
    '!./**/*',
  ],
  { eager: true, import: 'default', query: '?raw' },
) as Record<string, string>

describe('locale catalogs', () => {
  it('keeps Chinese and English key sets identical', () => {
    expect(Object.keys(locales.en).sort()).toEqual(Object.keys(locales.zh).sort())
  })

  it('keeps interpolation parameters identical across languages', () => {
    const parameters = (text: string) =>
      [...text.matchAll(/{{\s*([\w.]+)\s*}}/g)].map((match) => match[1]).sort()

    for (const key of Object.keys(locales.zh)) {
      expect(parameters(locales.en[key]), `interpolation mismatch: ${key}`).toEqual(
        parameters(locales.zh[key]),
      )
    }
  })

  it('does not leak Chinese copy into the English catalog', () => {
    const allowedChineseLabels = new Set(['common.chinese'])

    for (const [key, value] of Object.entries(locales.en)) {
      if (!allowedChineseLabels.has(key)) {
        expect(value, `Chinese text in English translation: ${key}`).not.toMatch(/[\u3400-\u9fff]/u)
      }
    }
  })

  it('defines every literal translation key used by production code', () => {
    const missing = new Set<string>()

    for (const source of Object.values(productionSources)) {
      for (const match of source.matchAll(/\bt\(\s*(['"])([^'"]+)\1/g)) {
        const key = match[2]
        if (!Object.prototype.hasOwnProperty.call(locales.zh, key)) missing.add(key)
      }
    }

    expect([...missing].sort()).toEqual([])
  })

  it.each(['zh', 'en'] as const)('contains valid non-empty %s entries', (language) => {
    const intentionallyEmpty = new Set([
      'en.ota.rollbackThresholdSuffix',
      'en.batch.targetDevicesUnit',
      'en.batch.changeParamsUnit',
    ])
    for (const [key, value] of Object.entries(locales[language])) {
      expect(key, `invalid translation key: ${key}`).toBe(key.trim())
      expect(key, `translation key contains whitespace: ${key}`).not.toMatch(/\s/)
      if (!intentionallyEmpty.has(`${language}.${key}`)) {
        expect(value, `empty translation: ${language}.${key}`).not.toBe('')
      }
    }
  })
})
