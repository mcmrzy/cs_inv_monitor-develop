import { ESLint } from 'eslint'
import { describe, expect, it } from 'vitest'

describe('BMS verification script lint configuration', () => {
  it.each(['bms-design.verify.mjs', 'bms-production.verify.mjs'])(
    '%s recognizes both Node and browser callback globals',
    async (script) => {
      const results = await new ESLint().lintFiles([script])

      expect(results).toHaveLength(1)
      expect(results[0].messages.filter(message => message.severity === 2)).toEqual([])
    },
  )
})
