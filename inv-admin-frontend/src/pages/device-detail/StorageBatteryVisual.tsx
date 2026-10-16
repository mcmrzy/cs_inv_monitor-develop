import { useId } from 'react'

interface Props { soc: number | null; unavailableLabel: string }

/** A storage cabinet illustration; the meter reports only the current validated BMS SOC. */
export default function StorageBatteryVisual({ soc, unavailableLabel }: Props) {
  const id = `storage-${useId().replace(/:/g, '')}`
  const valid = soc !== null && Number.isFinite(soc) && soc >= 0 && soc <= 100 ? soc : null
  const fillTop = 326 - (valid ?? 0) * 2.22
  const paint = (name: string) => `url(#${id}-${name})`

  return <div className={`cmd08-storage-scene ${valid === null ? 'is-unavailable' : ''}`} role="meter" aria-label="SOC"
    aria-valuemin={0} aria-valuemax={100} aria-valuenow={valid ?? undefined}
    aria-valuetext={valid === null ? unavailableLabel : `${valid}%`}>
    <svg className="cmd08-storage-cabinet" viewBox="0 0 440 410" aria-hidden="true" focusable="false">
      <defs>
        <linearGradient id={`${id}-body`} x1="0" y1="0" x2="1" y2=".4"><stop stopColor="#f4f8f8" /><stop offset=".42" stopColor="#cbd5d9" /><stop offset=".7" stopColor="#eef3f4" /><stop offset="1" stopColor="#9eacb2" /></linearGradient>
        <linearGradient id={`${id}-side`} x1="0" x2="1"><stop stopColor="#b5c2c8" /><stop offset=".48" stopColor="#e0e7e9" /><stop offset="1" stopColor="#a4b2ba" /></linearGradient>
        <linearGradient id={`${id}-top`} x1="0" y1="1" x2=".7" y2="0"><stop stopColor="#a3b2ba" /><stop offset="1" stopColor="#f3f7f8" /></linearGradient>
        <linearGradient id={`${id}-frame`} x1="0" x2="1" y2=".6"><stop stopColor="#6d7f86" /><stop offset=".14" stopColor="#2a3e45" /><stop offset=".8" stopColor="#233239" /><stop offset="1" stopColor="#70838a" /></linearGradient>
        <linearGradient id={`${id}-glass`} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#1b3538" /><stop offset=".6" stopColor="#0b2429" /><stop offset="1" stopColor="#233e43" /></linearGradient>
        <linearGradient id={`${id}-energy`} x1="0" x2="1"><stop stopColor="#84ffc8" /><stop offset=".12" stopColor="#40e9a2" /><stop offset=".6" stopColor="#13ba78" /><stop offset="1" stopColor="#087e56" /></linearGradient>
        <linearGradient id={`${id}-reflection`} x1="0" x2="1" y2=".55"><stop stopColor="#fff" stopOpacity=".23" /><stop offset=".55" stopColor="#fff" stopOpacity=".015" /><stop offset="1" stopColor="#fff" stopOpacity=".1" /></linearGradient>
        <radialGradient id={`${id}-shadow`}><stop stopColor="#244b45" stopOpacity=".26" /><stop offset="1" stopColor="#244b45" stopOpacity="0" /></radialGradient>
        <clipPath id={`${id}-chamber`}><path d="M158 95 Q158 85 169 86 L288 98 Q298 99 298 110 L298 324 Q298 337 286 336 L169 322 Q158 321 158 310Z" /></clipPath>
      </defs>

      <ellipse cx="236" cy="365" rx="165" ry="39" fill={paint('shadow')} />
      <ellipse cx="227" cy="362" rx="126" ry="22" fill="none" stroke="#a9c9bd" strokeOpacity=".35" />
      <ellipse cx="227" cy="362" rx="171" ry="37" fill="none" stroke="#b8ccc5" strokeOpacity=".2" strokeDasharray="4 8" />
      <path d="M147 349 L169 350 L169 362 L147 359Z M290 352 L313 339 L313 349 L290 362Z" fill="#64777b" />
      <path d="M298 66 L349 43 Q358 41 358 55 L358 312 Q358 326 348 333 L299 359Z" fill={paint('side')} stroke="#a4b2b8" />
      <path d="M131 64 L178 35 Q184 31 194 32 L346 43 Q354 43 352 49 L306 76Z" fill={paint('top')} stroke="#bbc6cb" />
      <path d="M144 62 L185 40 L334 49 L300 69Z" fill="#d6dfe2" fillOpacity=".7" />
      {[0, 1, 2, 3, 4, 5].map(index => <path key={index} d={`M${196 + index * 18} 45 l-17 10`} stroke="#899ba4" strokeWidth="2.2" strokeLinecap="round" />)}
      <path d="M129 82 Q127 63 146 64 L296 75 Q315 76 315 96 L315 340 Q315 363 295 360 L149 346 Q130 344 130 325Z" fill={paint('body')} stroke="#b3c0c6" strokeWidth="1.5" />
      <path d="M138 85 Q137 73 151 74 L294 86 Q304 87 304 101 L304 331 Q304 347 291 346 L151 332 Q140 330 140 316Z" fill={paint('frame')} stroke="#e8eff0" strokeOpacity=".65" />
      <path d="M150 94 Q150 81 164 83 L289 95 Q301 96 301 111 L301 322 Q301 340 286 339 L164 326 Q151 325 151 311Z" fill={paint('glass')} stroke="#6e8689" strokeOpacity=".6" />

      <g clipPath={paint('chamber')}>
        <path d="M161 100 L295 113 M161 151 L295 164 M161 202 L295 215 M161 253 L295 266 M161 304 L295 317" stroke="#91bfb2" strokeOpacity=".11" />
        {valid !== null && valid > 0 && <g data-energy-fill="true">
          <path d={`M158 ${fillTop} L183 ${fillTop - 13} L299 ${fillTop - 1} L299 340 L158 326Z`} fill={paint('energy')} fillOpacity=".94" />
          <path d={`M158 ${fillTop} L183 ${fillTop - 13} L299 ${fillTop - 1} L274 ${fillTop + 12}Z`} fill="#8affc9" fillOpacity=".68" />
          <path d={`M158 ${fillTop} L274 ${fillTop + 12} L274 337`} fill="none" stroke="#c2ffe0" strokeOpacity=".7" strokeWidth="1.5" />
          <path d={`M282 ${fillTop + 8} L282 339`} stroke="#002e22" strokeOpacity=".15" strokeWidth="15" />
        </g>}
        <path d="M158 86 L222 91 L193 327 L158 322Z" fill={paint('reflection')} />
        <path d="M165 93 L290 106 L290 329" fill="none" stroke="#fff" strokeOpacity=".14" strokeWidth="2" />
      </g>

      <text x="228" y="203" className="cmd08-storage-soc" textAnchor="middle" transform="rotate(5.5 228 203)">{valid === null ? '--' : valid.toFixed(1)}</text>
      {valid !== null && <text x="226" y="230" className="cmd08-storage-percent" textAnchor="middle" transform="rotate(5.5 226 230)">%</text>}
      <path d="M190 105 l7-4 7 5 v8 l-7 4-7-5Z" fill="none" stroke="#d0f5e5" strokeOpacity=".6" />
      <path d="M194 108 l3-2 3 2 v4 l-3 2-3-2Z" fill="#d0f5e5" fillOpacity=".6" />
      <path d="M327 103 L346 93 M327 109 L346 99 M327 115 L346 105 M327 121 L346 111" stroke="#748a94" strokeOpacity=".5" strokeWidth="1.5" />
      <path d="M322 247 L352 232 M321 250 L352 235" stroke="#8fa1a9" strokeOpacity=".5" />
      <path d="M151 336 L292 350" stroke="#f2f7f7" strokeOpacity=".6" />
      <circle cx="280" cy="346" r="2" fill={valid === null ? '#7b8d93' : '#25d795'} />
      <path d="M172 340 l43 4 M172 343 l43 4" stroke="#6d838a" strokeOpacity=".7" strokeLinecap="round" />
    </svg>
  </div>
}
