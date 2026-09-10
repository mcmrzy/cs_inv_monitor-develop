import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  AndroidOutlined,
  CloudSyncOutlined,
  DownloadOutlined,
  LineChartOutlined,
  NotificationOutlined,
  SafetyCertificateOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import api from '@/services/api'
import useTranslation from '@/hooks/useTranslation'

/**
 * App 安装包下载页（download.jiuxiaoyw.online）
 *
 * 版本信息来自公开接口 /ota/app/latest，不需要登录：上传新安装包后
 * 页面自动展示最新版本、体积与摘要，无需手工维护页面内容。
 */

interface LatestRelease {
  available: boolean
  platform?: string
  version_code?: number
  version_name?: string
  download_url?: string
  file_name?: string
  file_size?: number
  file_sha256?: string
  package_name?: string
  min_sdk?: number
  target_sdk?: number
  changelog?: string
  is_force?: boolean
  published_at?: string
}

/** Android SDK 级别 → 对外展示的系统版本名 */
const ANDROID_VERSION_NAMES: Record<number, string> = {
  21: '5.0',
  22: '5.1',
  23: '6.0',
  24: '7.0',
  25: '7.1',
  26: '8.0',
  27: '8.1',
  28: '9',
  29: '10',
  30: '11',
  31: '12',
  32: '12L',
  33: '13',
  34: '14',
  35: '15',
  36: '16',
}

function androidVersionName(sdk?: number): string {
  if (!sdk || sdk <= 0) return ''
  return ANDROID_VERSION_NAMES[sdk] ?? `SDK ${sdk}`
}

function formatFileSize(bytes?: number): string {
  if (!bytes || bytes <= 0) return ''
  const mb = bytes / (1024 * 1024)
  if (mb >= 100) return `${mb.toFixed(0)} MB`
  return `${mb.toFixed(1)} MB`
}

function formatDate(value: string | undefined, lang: string): string {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return date.toLocaleDateString(lang === 'en' ? 'en-US' : 'zh-CN', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })
}

/** 只保留用户真正关心的更新条目，避免把内部说明原样搬上公开页面。 */
function changelogLines(changelog?: string): string[] {
  if (!changelog) return []
  return changelog
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*[-*·•]\s*/, '').trim())
    .filter((line) => line.length > 0)
    .slice(0, 8)
}

const DownloadPage: React.FC = () => {
  const { t, lang } = useTranslation()
  const [loading, setLoading] = useState(true)
  const [release, setRelease] = useState<LatestRelease | null>(null)
  const [copied, setCopied] = useState(false)
  const [copiedField, setCopiedField] = useState<'sha256' | 'url' | null>(null)

  // 该页面托管在下载子域，浏览器标签页需要显示下载相关标题而不是后台标题。
  useEffect(() => {
    const previous = document.title
    document.title = `${t('dl.appTitle')} · ${t('dl.downloadBtn')}`
    return () => {
      document.title = previous
    }
  }, [t])

  useEffect(() => {
    let alive = true
    const load = async () => {
      try {
        const res = await api.get('/ota/app/latest', {
          params: { platform: 'android' },
          expectedDataShape: 'object',
        })
        const payload = (res.data as { data?: LatestRelease } | undefined)?.data
        if (alive && payload) setRelease(payload)
      } catch {
        // 接口不可用时页面仍需完整渲染，下载按钮退化为提示态。
        if (alive) setRelease(null)
      } finally {
        if (alive) setLoading(false)
      }
    }
    void load()
    return () => {
      alive = false
    }
  }, [])

  const hasRelease = Boolean(release?.available && release.download_url)
  const sizeText = formatFileSize(release?.file_size)
  const minAndroid = androidVersionName(release?.min_sdk)
  const releaseDate = formatDate(release?.published_at, lang)
  const notes = useMemo(() => changelogLines(release?.changelog), [release?.changelog])

  const copyValue = useCallback(async (value: string | undefined, field: 'sha256' | 'url') => {
    if (!value) return
    try {
      await navigator.clipboard.writeText(value)
      setCopiedField(field)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 2000)
    } catch {
      // 非安全上下文或权限被拒时不阻断页面，用户可手动选中复制。
      setCopied(false)
    }
  }, [])

  const handleDownload = useCallback(() => {
    if (!release?.download_url) return
    const link = document.createElement('a')
    link.href = release.download_url
    link.download = release.file_name || `csergy-solar-v${release.version_name ?? ''}.apk`
    link.rel = 'noopener'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }, [release])

  const features = [
    { icon: <LineChartOutlined />, title: t('dl.featureMonitor'), desc: t('dl.featureMonitorDesc'), tone: 'blue' },
    { icon: <ThunderboltOutlined />, title: t('dl.featureAnalytics'), desc: t('dl.featureAnalyticsDesc'), tone: 'amber' },
    { icon: <NotificationOutlined />, title: t('dl.featureAlerts'), desc: t('dl.featureAlertsDesc'), tone: 'rose' },
    { icon: <CloudSyncOutlined />, title: t('dl.featureOta'), desc: t('dl.featureOtaDesc'), tone: 'green' },
  ]

  const installSteps = [
    { title: t('dl.installStep1'), desc: sizeText ? t('dl.installStep1Desc', { size: sizeText }) : t('dl.installStep2Desc') },
    { title: t('dl.installStep2'), desc: t('dl.installStep2Desc') },
    { title: t('dl.installStep3'), desc: t('dl.installStep3Desc') },
  ]

  return (
    <div className="dlp">
      <style>{dlpStyles}</style>

      {/* ---------- 主视觉 ---------- */}
      <header className="dlp-hero">
        <div className="dlp-backdrop" aria-hidden="true">
          <span className="dlp-glow dlp-glow--a" />
          <span className="dlp-glow dlp-glow--b" />
          <span className="dlp-grid" />
        </div>

        <div className="dlp-shell dlp-hero-inner">
          <div className="dlp-hero-copy">
            <div className="dlp-badge">
              <span className="dlp-badge-dot" />
              {t('dl.badge')}
              {release?.version_name ? <em>v{release.version_name}</em> : null}
            </div>

            <h1 className="dlp-title">{t('dl.appTitle')}</h1>
            <p className="dlp-subtitle">{t('dl.subtitle')}</p>

            <div className="dlp-actions">
              {/* 文案固定为下载动作：版本未就绪时置灰并由下方提示说明原因，
                  避免主按钮文字随加载状态变化导致入口不可预期。 */}
              <button
                type="button"
                className="dlp-cta"
                onClick={handleDownload}
                disabled={!hasRelease || loading}
              >
                <DownloadOutlined />
                {t('dl.downloadBtn')}
              </button>

              <a className="dlp-cta dlp-cta--ghost" href="#dlp-notes">
                {t('dl.releaseNotes')}
              </a>
            </div>

            <div className="dlp-meta">
              <span className="dlp-chip">
                <AndroidOutlined /> {t('dl.androidOnly')}
              </span>
              {minAndroid ? <span className="dlp-chip">Android {minAndroid}+</span> : null}
              {sizeText ? <span className="dlp-chip">{sizeText}</span> : null}
              {release?.version_code ? (
                <span className="dlp-chip">
                  {t('dl.versionCode')} {release.version_code}
                </span>
              ) : null}
            </div>

            <p className="dlp-security">
              <SafetyCertificateOutlined /> {t('dl.securityTip')}
            </p>

            {release && !release.available && !loading ? (
              <p className="dlp-empty">
                <strong>{t('dl.noRelease')}</strong>
                <span>{t('dl.noReleaseDesc')}</span>
              </p>
            ) : null}
          </div>

          {/* 手机预览：用 CSS/SVG 绘制，不依赖外部截图资源 */}
          <div className="dlp-hero-visual" aria-hidden="true">
            <div className="dlp-phone">
              <div className="dlp-phone-notch" />
              <div className="dlp-phone-screen">
                <div className="dlp-app-bar">
                  <span>{t('dl.previewSite')}</span>
                  <span className="dlp-app-dot" />
                </div>
                <div className="dlp-app-power">
                  <small>{t('dl.previewPower')}</small>
                  <strong>12.64<em>kW</em></strong>
                  <svg viewBox="0 0 160 36" className="dlp-spark" preserveAspectRatio="none">
                    <polyline
                      points="0,28 16,22 32,25 48,14 64,18 80,9 96,13 112,6 128,11 144,4 160,8"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </div>
                <div className="dlp-app-list">
                  {[
                    { name: 'CS-INV-6K2', state: t('dl.previewOnline'), power: '6.32 kW', ok: true },
                    { name: 'CS-INV-5K1', state: t('dl.previewOnline'), power: '4.18 kW', ok: true },
                    { name: 'CS-INV-3K6', state: t('dl.previewWarning'), power: '2.14 kW', ok: false },
                  ].map((row) => (
                    <div className="dlp-app-row" key={row.name}>
                      <span className={row.ok ? 'dlp-app-flag' : 'dlp-app-flag dlp-app-flag--warn'} />
                      <div className="dlp-app-name">
                        <b>{row.name}</b>
                        <small>{row.state}</small>
                      </div>
                      <span className="dlp-app-power-value">{row.power}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* ---------- 版本信息 / 完整性校验 ---------- */}
      <section className="dlp-shell dlp-panel" id="dlp-release">
        <div className="dlp-panel-grid">
          <div>
            <h2 className="dlp-h2">{t('dl.verifyTitle')}</h2>
            <p className="dlp-muted">{t('dl.verifyDesc')}</p>
            {releaseDate ? (
              <p className="dlp-muted">
                {t('dl.publishedAt')}: {releaseDate}
              </p>
            ) : null}
          </div>

          <dl className="dlp-spec">
            <div>
              <dt>{t('dl.latestVersion')}</dt>
              <dd>{release?.version_name ? `v${release.version_name}` : '—'}</dd>
            </div>
            <div>
              <dt>{t('dl.fileSize')}</dt>
              <dd>{sizeText || '—'}</dd>
            </div>
            <div>
              <dt>{t('dl.pkgName')}</dt>
              <dd className="dlp-mono">{release?.package_name || '—'}</dd>
            </div>
            <div className="dlp-spec-wide">
              <dt>{t('dl.sha256')}</dt>
              <dd className="dlp-mono dlp-hash">
                <span>{release?.file_sha256 || '—'}</span>
                {release?.file_sha256 ? (
                  <button
                    type="button"
                    className="dlp-copy"
                    onClick={() => void copyValue(release.file_sha256, 'sha256')}
                  >
                    {copiedField === 'sha256' ? t('dl.copiedShort') : t('dl.copy')}
                  </button>
                ) : null}
              </dd>
            </div>
            {release?.download_url ? (
              <div className="dlp-spec-wide">
                <dt>{t('dl.downloadUrl')}</dt>
                <dd className="dlp-mono dlp-hash">
                  <span>{release.download_url}</span>
                  <button
                    type="button"
                    className="dlp-copy"
                    onClick={() => void copyValue(release.download_url, 'url')}
                  >
                    {copiedField === 'url' ? t('dl.copiedShort') : t('dl.copy')}
                  </button>
                </dd>
              </div>
            ) : null}
          </dl>
        </div>
        {copied ? <div className="dlp-toast">{t('dl.copied')}</div> : null}
      </section>

      {/* ---------- 功能特性 ---------- */}
      <section className="dlp-shell dlp-section">
        <h2 className="dlp-h2 dlp-h2--center">{t('dl.featuresTitle')}</h2>
        <p className="dlp-muted dlp-muted--center">{t('dl.featuresSubtitle')}</p>

        <div className="dlp-features">
          {features.map((feature) => (
            <article className={`dlp-feature dlp-feature--${feature.tone}`} key={feature.title}>
              <span className="dlp-feature-icon">{feature.icon}</span>
              <h3>{feature.title}</h3>
              <p>{feature.desc}</p>
            </article>
          ))}
        </div>
      </section>

      {/* ---------- 安装步骤 ---------- */}
      <section className="dlp-shell dlp-section">
        <h2 className="dlp-h2 dlp-h2--center">{t('dl.installTitle')}</h2>
        <ol className="dlp-steps">
          {installSteps.map((step, index) => (
            <li key={step.title}>
              <span className="dlp-step-index">{index + 1}</span>
              <div>
                <b>{step.title}</b>
                <p>{step.desc}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>

      {/* ---------- 更新日志 ---------- */}
      <section className="dlp-shell dlp-section" id="dlp-notes">
        <h2 className="dlp-h2">{t('dl.changelog')}</h2>
        {notes.length > 0 ? (
          <ul className="dlp-notes">
            {notes.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
        ) : (
          <p className="dlp-muted">{t('dl.changelogEmpty')}</p>
        )}
      </section>

      <footer className="dlp-footer">
        <div className="dlp-shell dlp-footer-inner">
          <span>
            {t('dl.footerCopyright')} · {t('dl.footerDesc')}
          </span>
          <a href="https://csergy.com" target="_blank" rel="noopener noreferrer">
            csergy.com
          </a>
        </div>
      </footer>
    </div>
  )
}

const dlpStyles = `
.dlp {
  --dlp-brand: #1a73e8;
  --dlp-brand-deep: #0b3d91;
  --dlp-ink: #0f172a;
  --dlp-muted: #5b6b83;
  --dlp-line: rgba(15, 23, 42, 0.08);
  position: relative;
  min-height: 100vh;
  background: #f6f8fc;
  color: var(--dlp-ink);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", Roboto, Arial, sans-serif;
  overflow-x: hidden;
}
.dlp * { box-sizing: border-box; }
.dlp-shell { width: 100%; max-width: 1120px; margin: 0 auto; padding: 0 24px; }

/* 深色主视觉：白色文案必须落在深色底上，否则整屏不可读 */
.dlp-hero {
  position: relative; overflow: hidden;
  padding: 76px 0 108px;
  background:
    radial-gradient(720px 400px at 96% -8%, rgba(34, 197, 94, .16) 0%, transparent 58%),
    radial-gradient(1000px 560px at 4% -20%, rgba(66, 133, 244, .42) 0%, transparent 62%),
    linear-gradient(158deg, #08182f 0%, #10294f 46%, #061530 100%);
}
.dlp-backdrop { position: absolute; inset: 0; overflow: hidden; }
.dlp-glow { position: absolute; border-radius: 50%; filter: blur(90px); opacity: .5; }
.dlp-glow--a { width: 560px; height: 560px; left: -160px; top: -240px; background: #2f7bf0; }
.dlp-glow--b { width: 460px; height: 460px; right: -140px; top: -180px; background: #22c55e; opacity: .3; }
.dlp-grid {
  position: absolute; inset: 0;
  background-image: linear-gradient(rgba(255,255,255,.06) 1px, transparent 1px),
                    linear-gradient(90deg, rgba(255,255,255,.06) 1px, transparent 1px);
  background-size: 44px 44px;
  mask-image: linear-gradient(#000 35%, transparent 92%);
  -webkit-mask-image: linear-gradient(#000 35%, transparent 92%);
}

.dlp-hero-inner {
  position: relative; z-index: 1;
  display: grid; grid-template-columns: 1.08fr .92fr; gap: 48px; align-items: center;
}
.dlp-hero-copy { color: #fff; }

.dlp-badge {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 6px 14px; border-radius: 999px;
  background: rgba(255,255,255,.14);
  border: 1px solid rgba(255,255,255,.22);
  color: #eaf2ff; font-size: 13px; letter-spacing: .3px;
  backdrop-filter: blur(6px);
}
.dlp-badge em { font-style: normal; font-weight: 700; color: #fff; }
.dlp-badge-dot { width: 7px; height: 7px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 0 4px rgba(34,197,94,.22); }

.dlp-title {
  margin: 22px 0 12px; font-size: 54px; line-height: 1.08; font-weight: 800; letter-spacing: -1px;
  background: linear-gradient(120deg, #ffffff 20%, #cfe3ff 90%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
.dlp-subtitle { margin: 0 0 32px; font-size: 18px; color: rgba(255,255,255,.82); line-height: 1.7; max-width: 30em; }

.dlp-actions { display: flex; flex-wrap: wrap; gap: 14px; align-items: center; }
.dlp-cta {
  display: inline-flex; align-items: center; justify-content: center; gap: 10px;
  height: 54px; padding: 0 30px; border-radius: 14px; border: 0;
  font-size: 16px; font-weight: 700; cursor: pointer; text-decoration: none;
  background: linear-gradient(135deg, #ffffff 0%, #e6efff 100%);
  color: var(--dlp-brand-deep);
  box-shadow: 0 16px 34px rgba(4, 26, 70, .34);
  transition: transform .18s ease, box-shadow .18s ease, opacity .18s ease;
}
.dlp-cta:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 20px 40px rgba(4, 26, 70, .42); }
.dlp-cta:disabled { opacity: .55; cursor: not-allowed; box-shadow: none; }
.dlp-cta--ghost {
  background: rgba(255,255,255,.08); color: #eaf2ff;
  border: 1px solid rgba(255,255,255,.28); box-shadow: none;
}
.dlp-cta--ghost:hover { background: rgba(255,255,255,.16); }

.dlp-meta { display: flex; flex-wrap: wrap; gap: 10px; margin: 26px 0 18px; }
.dlp-chip {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 6px 12px; border-radius: 10px; font-size: 13px;
  background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.18); color: #e8f0ff;
}
.dlp-security { display: flex; align-items: center; gap: 8px; margin: 0; font-size: 13px; color: rgba(255,255,255,.72); }
.dlp-empty {
  display: flex; flex-direction: column; gap: 4px; margin: 18px 0 0;
  padding: 14px 16px; border-radius: 12px; font-size: 13px; color: #eaf2ff;
  background: rgba(255,255,255,.1); border: 1px solid rgba(255,255,255,.2);
}

.dlp-hero-visual { display: flex; justify-content: center; }
.dlp-phone {
  position: relative; width: 272px; height: 552px; border-radius: 40px;
  background: linear-gradient(160deg, #101a2e, #060c18);
  padding: 12px; box-shadow: 0 40px 70px rgba(3, 14, 38, .55), inset 0 0 0 1px rgba(255,255,255,.08);
}
.dlp-phone-notch { position: absolute; top: 22px; left: 50%; transform: translateX(-50%); width: 84px; height: 8px; border-radius: 999px; background: #0a1426; }
.dlp-phone-screen {
  height: 100%; border-radius: 30px; padding: 34px 16px 16px;
  background: linear-gradient(180deg, #f8fbff 0%, #eef4fd 100%);
  display: flex; flex-direction: column; gap: 14px; overflow: hidden;
}
.dlp-app-bar { display: flex; align-items: center; justify-content: space-between; font-size: 12px; font-weight: 700; color: #274063; }
.dlp-app-dot { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; }
.dlp-app-power {
  border-radius: 16px; padding: 14px; color: #fff;
  background: linear-gradient(135deg, var(--dlp-brand) 0%, var(--dlp-brand-deep) 100%);
  box-shadow: 0 12px 24px rgba(26,115,232,.28);
}
.dlp-app-power small { display: block; font-size: 11px; opacity: .8; }
.dlp-app-power strong { display: block; font-size: 28px; font-weight: 800; letter-spacing: -.5px; }
.dlp-app-power strong em { font-style: normal; font-size: 13px; font-weight: 600; margin-left: 4px; opacity: .85; }
.dlp-spark { width: 100%; height: 34px; margin-top: 8px; color: rgba(255,255,255,.85); }
.dlp-app-list { display: flex; flex-direction: column; gap: 8px; }
.dlp-app-row {
  display: flex; align-items: center; gap: 10px; padding: 11px 12px;
  border-radius: 12px; background: #fff; box-shadow: 0 4px 12px rgba(15,23,42,.06);
}
.dlp-app-flag { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; flex-shrink: 0; }
.dlp-app-flag--warn { background: #f59e0b; }
.dlp-app-name { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.dlp-app-name b { font-size: 12px; color: #16233c; }
.dlp-app-name small { font-size: 10px; color: #7b8aa4; }
.dlp-app-power-value { font-size: 12px; font-weight: 700; color: #16233c; }

/* 规格卡片上浮压住主视觉底边，形成层次 */
.dlp-panel {
  position: relative; z-index: 2; margin-top: -64px;
  padding-top: 28px; padding-bottom: 28px;
  background: #fff; border-radius: 22px;
  box-shadow: 0 24px 60px rgba(8, 24, 47, .16), 0 1px 0 rgba(15,23,42,.04);
}
.dlp-panel-grid { display: grid; grid-template-columns: .9fr 1.1fr; gap: 32px; align-items: start; }
.dlp-h2 { margin: 0 0 10px; font-size: 24px; font-weight: 800; letter-spacing: -.3px; }
.dlp-h2--center { text-align: center; }
.dlp-muted { margin: 0 0 8px; color: var(--dlp-muted); font-size: 14px; line-height: 1.75; }
.dlp-muted--center { text-align: center; max-width: 44em; margin: 0 auto 28px; }

.dlp-spec { margin: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 14px 20px; }
.dlp-spec > div { min-width: 0; }
.dlp-spec-wide { grid-column: 1 / -1; }
.dlp-spec dt { font-size: 12px; color: #8494ac; margin-bottom: 4px; }
.dlp-spec dd { margin: 0; font-size: 14px; font-weight: 600; color: #16233c; word-break: break-all; }
.dlp-mono { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-weight: 500; font-size: 12.5px; }
.dlp-hash { display: flex; align-items: flex-start; gap: 10px; }
.dlp-hash span { flex: 1; min-width: 0; }
.dlp-copy {
  flex-shrink: 0; padding: 3px 10px; border-radius: 8px; cursor: pointer;
  font-size: 12px; color: var(--dlp-brand); background: #eef4ff; border: 1px solid #d9e6ff;
}
.dlp-copy:hover { background: #e2ecff; }
.dlp-toast {
  position: fixed; left: 50%; bottom: 40px; transform: translateX(-50%);
  padding: 10px 20px; border-radius: 12px; font-size: 13px; color: #fff;
  background: rgba(15,23,42,.9); box-shadow: 0 12px 30px rgba(15,23,42,.3); z-index: 20;
}

.dlp-section { padding-top: 68px; padding-bottom: 8px; }
.dlp-features { display: grid; grid-template-columns: repeat(4, 1fr); gap: 18px; }
.dlp-feature {
  padding: 24px 20px; border-radius: 18px; background: #fff;
  border: 1px solid var(--dlp-line); box-shadow: 0 10px 28px rgba(15,23,42,.05);
  transition: transform .2s ease, box-shadow .2s ease;
}
.dlp-feature:hover { transform: translateY(-4px); box-shadow: 0 18px 38px rgba(15,23,42,.1); }
.dlp-feature h3 { margin: 14px 0 6px; font-size: 16px; font-weight: 700; }
.dlp-feature p { margin: 0; font-size: 13px; color: var(--dlp-muted); line-height: 1.7; }
.dlp-feature-icon {
  display: inline-flex; align-items: center; justify-content: center;
  width: 46px; height: 46px; border-radius: 14px; font-size: 22px;
}
.dlp-feature--blue .dlp-feature-icon { background: #e8f0fe; color: #1a73e8; }
.dlp-feature--amber .dlp-feature-icon { background: #fef3e2; color: #f59e0b; }
.dlp-feature--rose .dlp-feature-icon { background: #fdeaea; color: #ef4444; }
.dlp-feature--green .dlp-feature-icon { background: #e6f7ee; color: #22c55e; }

.dlp-steps { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; }
.dlp-steps li {
  display: flex; gap: 14px; padding: 22px; border-radius: 18px;
  background: #fff; border: 1px solid var(--dlp-line);
}
.dlp-steps b { font-size: 15px; }
.dlp-steps p { margin: 6px 0 0; font-size: 13px; color: var(--dlp-muted); line-height: 1.7; }
.dlp-step-index {
  flex-shrink: 0; width: 30px; height: 30px; border-radius: 10px;
  display: inline-flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 14px; color: #fff;
  background: linear-gradient(135deg, var(--dlp-brand) 0%, var(--dlp-brand-deep) 100%);
}

.dlp-notes { margin: 0; padding: 0 0 0 18px; color: #33445f; font-size: 14px; line-height: 2; }
.dlp-notes li::marker { color: var(--dlp-brand); }

.dlp-footer { margin-top: 72px; padding: 26px 0 34px; border-top: 1px solid var(--dlp-line); }
.dlp-footer-inner { display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-between; font-size: 13px; color: var(--dlp-muted); }
.dlp-footer a { color: var(--dlp-brand); text-decoration: none; }
.dlp-footer a:hover { text-decoration: underline; }

@media (max-width: 980px) {
  .dlp-hero { padding: 48px 0 40px; }
  .dlp-hero-inner { grid-template-columns: 1fr; gap: 40px; }
  .dlp-hero-visual { order: -1; }
  .dlp-phone { width: 236px; height: 480px; }
  .dlp-title { font-size: 40px; }
  .dlp-features { grid-template-columns: 1fr 1fr; }
  .dlp-steps { grid-template-columns: 1fr; }
  .dlp-panel-grid { grid-template-columns: 1fr; gap: 22px; }
}
@media (max-width: 620px) {
  .dlp-shell { padding: 0 18px; }
  .dlp-title { font-size: 32px; }
  .dlp-subtitle { font-size: 15px; }
  .dlp-cta { width: 100%; padding: 0 20px; }
  .dlp-features { grid-template-columns: 1fr; }
  .dlp-spec { grid-template-columns: 1fr; }
  .dlp-panel { border-radius: 18px; }
}
`

export default DownloadPage
