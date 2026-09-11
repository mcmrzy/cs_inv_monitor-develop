import { useCallback, useEffect, useMemo, useState } from 'react'
import { QRCode } from 'antd'
import {
  AndroidOutlined,
  CloudSyncOutlined,
  DownloadOutlined,
  LineChartOutlined,
  NotificationOutlined,
  SafetyCertificateOutlined,
  ThunderboltOutlined,
} from '@ant-design/icons'
import useTranslation from '@/hooks/useTranslation'

/**
 * App 安装包下载页（download.jiuxiaoyw.online）
 *
 * 版本信息来自公开接口 /ota/app/latest，不需要登录：上传新安装包后
 * 页面自动展示最新版本、体积与摘要，无需手工维护页面内容。
 * 手机端第一屏即下载按钮；桌面端右侧展示机型预览与扫码下载卡片。
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
      // 优先走下载域同源别名路径；失败时回退 API 域（网关 CORS 已放行
      // download 来源）。两者都绕开 ESA 曾缓存过的 /api/v1/ota/app/latest。
      const endpoints = [
        '/app-release-info?platform=android',
        'https://api.jiuxiaoyw.online/api/v1/ota/app/latest?platform=android',
      ]
      for (const endpoint of endpoints) {
        try {
          const res = await fetch(endpoint)
          if (!res.ok) continue
          const payload = (await res.json()) as { code?: number; data?: LatestRelease }
          if (payload?.data?.available !== undefined) {
            if (alive) {
              setRelease(payload.data)
              setLoading(false)
            }
            return
          }
        } catch {
          // 尝试下一个端点
        }
      }
      if (alive) {
        setRelease(null)
        setLoading(false)
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
    { icon: <ThunderboltOutlined />, title: t('dl.featureAnalytics'), desc: t('dl.featureAnalyticsDesc'), tone: 'cyan' },
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

      <div className="dlp-bg" aria-hidden="true">
        <span className="dlp-blob dlp-blob--a" />
        <span className="dlp-blob dlp-blob--b" />
        <span className="dlp-blob dlp-blob--c" />
      </div>

      {/* ---------- 主视觉：手机端第一屏即标题 + 下载按钮 ---------- */}
      <header className="dlp-hero dlp-shell">
        <div className="dlp-hero-copy">
          <div className="dlp-badge">
            <span className="dlp-badge-dot" />
            {t('dl.badge')}
            {release?.version_name ? <em>v{release.version_name}</em> : null}
          </div>

          <h1 className="dlp-title">{t('dl.appTitle')}</h1>
          <span className="dlp-title-accent" aria-hidden="true" />
          <p className="dlp-subtitle">{t('dl.subtitle')}</p>

          <div className="dlp-actions">
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

        {/* 桌面端：机型预览 + 扫码下载卡片（手机端隐藏——用户本来就在手机上） */}
        <div className="dlp-hero-visual">
          <span className="dlp-phone-backdrop" aria-hidden="true" />
          <div className="dlp-phone" aria-hidden="true">
            <div className="dlp-phone-screen">
              <div className="dlp-statusbar">
                <span>9:41</span>
                <span className="dlp-statusbar-pill" />
                <span className="dlp-statusbar-icons">
                  <i />
                  <i />
                </span>
              </div>
              <div className="dlp-app-bar">
                <b>{t('dl.previewSite')}</b>
                <span className="dlp-app-dot" />
              </div>
              <div className="dlp-app-power">
                <small>{t('dl.previewPower')}</small>
                <strong>
                  12.64<em>kW</em>
                </strong>
                <svg viewBox="0 0 160 40" className="dlp-spark" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="dlpSparkFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="currentColor" stopOpacity="0.34" />
                      <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
                    </linearGradient>
                  </defs>
                  <path
                    d="M0 30 L16 24 L32 27 L48 16 L64 20 L80 11 L96 15 L112 8 L128 12 L144 5 L160 9 L160 40 L0 40 Z"
                    fill="url(#dlpSparkFill)"
                    stroke="none"
                  />
                  <polyline
                    points="0,30 16,24 32,27 48,16 64,20 80,11 96,15 112,8 128,12 144,5 160,9"
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

          {hasRelease && release?.download_url ? (
            <div className="dlp-qr-card">
              <QRCode value={release.download_url} size={116} />
              <span>{t('dl.qrCaption')}</span>
            </div>
          ) : null}
        </div>
      </header>

      <main>
        {/* ---------- 版本信息 / 完整性校验 ---------- */}
        <section className="dlp-shell" id="dlp-release">
          <div className="dlp-card dlp-spec-card">
            <div className="dlp-spec-head">
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
              <div>
                <dt>{t('dl.versionCode')}</dt>
                <dd>{release?.version_code || '—'}</dd>
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
          <div className="dlp-card dlp-notes-card">
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
          </div>
        </section>
      </main>

      {copied ? <div className="dlp-toast">{t('dl.copied')}</div> : null}

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
  --brand: #2563eb;
  --brand-2: #0891b2;
  --ink: #101828;
  --muted: #5d6b82;
  --line: #e7ecf3;
  --card: #ffffff;
  position: relative;
  min-height: 100vh;
  background: #f8fafd;
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", Roboto, Arial, sans-serif;
  overflow-x: hidden;
}
.dlp * { box-sizing: border-box; }
.dlp-shell { width: 100%; max-width: 1080px; margin: 0 auto; padding: 0 24px; position: relative; }

.dlp-bg { position: absolute; inset: 0 0 auto 0; height: 760px; overflow: hidden; pointer-events: none; }
.dlp-blob { position: absolute; border-radius: 50%; filter: blur(80px); }
.dlp-blob--a { width: 620px; height: 620px; left: -180px; top: -260px; background: rgba(37, 99, 235, .16); }
.dlp-blob--b { width: 520px; height: 520px; right: -160px; top: -220px; background: rgba(8, 145, 178, .12); }
.dlp-blob--c { width: 380px; height: 380px; right: 22%; top: 180px; background: rgba(16, 185, 129, .08); }

/* ---------- 主视觉 ---------- */
.dlp-hero {
  display: grid; grid-template-columns: 1.05fr .95fr; gap: 40px; align-items: center;
  padding-top: 72px; padding-bottom: 40px;
}
.dlp-badge {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 7px 15px; border-radius: 999px;
  background: #eef4ff; border: 1px solid #dbe7ff;
  color: #1d4ed8; font-size: 13px; font-weight: 600; letter-spacing: .3px;
}
.dlp-badge em { font-style: normal; font-weight: 800; color: var(--brand); }
.dlp-badge-dot { width: 7px; height: 7px; border-radius: 50%; background: #10b981; box-shadow: 0 0 0 4px rgba(16,185,129,.15); }

.dlp-title {
  margin: 20px 0 0; font-size: 52px; line-height: 1.1; font-weight: 800; letter-spacing: -.5px; color: var(--ink);
}
.dlp-title-accent {
  display: block; width: 64px; height: 6px; border-radius: 999px; margin-top: 16px;
  background: linear-gradient(90deg, var(--brand), #10b981);
}
.dlp-subtitle { margin: 18px 0 30px; font-size: 17px; color: var(--muted); line-height: 1.75; max-width: 28em; }

.dlp-actions { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
.dlp-cta {
  display: inline-flex; align-items: center; justify-content: center; gap: 9px;
  height: 54px; padding: 0 32px; border-radius: 999px; border: 0;
  font-size: 16px; font-weight: 700; cursor: pointer; text-decoration: none;
  background: linear-gradient(135deg, var(--brand) 0%, var(--brand-2) 100%);
  color: #fff;
  box-shadow: 0 12px 26px rgba(37, 99, 235, .32);
  transition: transform .18s ease, box-shadow .18s ease, opacity .18s ease;
}
.dlp-cta:hover:not(:disabled) { transform: translateY(-2px); box-shadow: 0 16px 32px rgba(37, 99, 235, .4); }
.dlp-cta:disabled { background: #c7d2e3; box-shadow: none; cursor: not-allowed; }
.dlp-cta--ghost {
  background: #fff; color: var(--ink); border: 1px solid var(--line); box-shadow: 0 2px 8px rgba(16,24,40,.05);
}
.dlp-cta--ghost:hover { border-color: #cfd9e6; }

.dlp-meta { display: flex; flex-wrap: wrap; gap: 9px; margin: 24px 0 16px; }
.dlp-chip {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 6px 13px; border-radius: 999px; font-size: 13px;
  background: #fff; border: 1px solid var(--line); color: #43506a;
}
.dlp-security { display: flex; align-items: center; gap: 8px; margin: 0; font-size: 13px; color: var(--muted); }
.dlp-security .anticon { color: #10b981; }
.dlp-empty {
  display: flex; flex-direction: column; gap: 4px; margin: 18px 0 0;
  padding: 14px 16px; border-radius: 14px; font-size: 13px; color: #7a4d00;
  background: #fff8e6; border: 1px solid #f3e3b3;
}
.dlp-empty strong { font-size: 14px; }

/* ---------- 机型预览 + 扫码卡片 ---------- */
.dlp-hero-visual { position: relative; display: flex; justify-content: center; padding: 12px 0 26px; }
.dlp-phone-backdrop {
  position: absolute; inset: 8% -4% 4% 8%;
  background: linear-gradient(135deg, #dbeafe 0%, #d1fae5 100%);
  border-radius: 36px; transform: rotate(5deg);
}
.dlp-phone {
  position: relative; width: 288px; border-radius: 42px;
  background: linear-gradient(160deg, #101a2e, #060c18);
  padding: 11px;
  box-shadow: 0 34px 64px rgba(8, 20, 45, .32), inset 0 0 0 1px rgba(255,255,255,.09);
  animation: dlpFloat 7s ease-in-out infinite;
}
@keyframes dlpFloat {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-8px); }
}
@media (prefers-reduced-motion: reduce) {
  .dlp-phone { animation: none; }
}
.dlp-phone-screen {
  border-radius: 32px; padding: 12px 14px 16px; overflow: hidden;
  background: linear-gradient(180deg, #f8fbff 0%, #eef4fd 100%);
  display: flex; flex-direction: column; gap: 12px;
}
.dlp-statusbar { display: flex; align-items: center; justify-content: space-between; padding: 2px 6px 0; }
.dlp-statusbar span:first-child { font-size: 11px; font-weight: 700; color: #274063; }
.dlp-statusbar-pill { width: 64px; height: 16px; border-radius: 999px; background: #0a1426; }
.dlp-statusbar-icons { display: inline-flex; gap: 4px; }
.dlp-statusbar-icons i { width: 14px; height: 8px; border-radius: 3px; background: #b9c6da; }
.dlp-app-bar { display: flex; align-items: center; justify-content: space-between; padding: 4px 4px 0; }
.dlp-app-bar b { font-size: 14px; color: #16233c; }
.dlp-app-dot { width: 8px; height: 8px; border-radius: 50%; background: #10b981; }
.dlp-app-power {
  border-radius: 18px; padding: 14px; color: #fff;
  background: linear-gradient(135deg, var(--brand) 0%, var(--brand-2) 100%);
  box-shadow: 0 12px 24px rgba(37, 99, 235, .3);
}
.dlp-app-power small { display: block; font-size: 11px; opacity: .85; }
.dlp-app-power strong { display: block; font-size: 28px; font-weight: 800; letter-spacing: -.5px; margin-top: 2px; }
.dlp-app-power strong em { font-style: normal; font-size: 13px; font-weight: 600; margin-left: 4px; opacity: .9; }
.dlp-spark { width: 100%; height: 36px; margin-top: 8px; color: rgba(255,255,255,.95); }
.dlp-app-list { display: flex; flex-direction: column; gap: 8px; }
.dlp-app-row {
  display: flex; align-items: center; gap: 10px; padding: 11px 12px;
  border-radius: 14px; background: #fff; box-shadow: 0 4px 12px rgba(15,23,42,.06);
}
.dlp-app-flag { width: 8px; height: 8px; border-radius: 50%; background: #10b981; flex-shrink: 0; }
.dlp-app-flag--warn { background: #f59e0b; }
.dlp-app-name { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.dlp-app-name b { font-size: 12px; color: #16233c; }
.dlp-app-name small { font-size: 10px; color: #7b8aa4; }
.dlp-app-power-value { font-size: 12px; font-weight: 700; color: #16233c; }

.dlp-qr-card {
  position: absolute; right: 2%; bottom: 0;
  display: flex; flex-direction: column; align-items: center; gap: 8px;
  padding: 14px 16px 12px; border-radius: 18px;
  background: #fff; border: 1px solid var(--line);
  box-shadow: 0 18px 40px rgba(16, 24, 40, .12);
}
.dlp-qr-card .ant-qrcode { border: none; }
.dlp-qr-card span { font-size: 12px; color: var(--muted); font-weight: 600; }

/* ---------- 通用区块 ---------- */
.dlp-card {
  background: var(--card); border: 1px solid var(--line); border-radius: 22px;
  box-shadow: 0 10px 30px rgba(16, 24, 40, .06);
}
.dlp-h2 { margin: 0 0 10px; font-size: 26px; font-weight: 800; letter-spacing: -.3px; color: var(--ink); }
.dlp-h2--center { text-align: center; }
.dlp-muted { margin: 0 0 8px; color: var(--muted); font-size: 14px; line-height: 1.75; }
.dlp-muted--center { text-align: center; max-width: 44em; margin: 0 auto 30px; }

.dlp-spec-card {
  margin-top: 6px; padding: 30px 32px;
  display: grid; grid-template-columns: .82fr 1.18fr; gap: 28px 36px; align-items: start;
}
.dlp-spec { margin: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 16px 22px; align-content: start; }
.dlp-spec > div { min-width: 0; }
.dlp-spec-wide { grid-column: 1 / -1; }
.dlp-spec dt { font-size: 12px; color: #8595ac; margin-bottom: 5px; letter-spacing: .3px; }
.dlp-spec dd { margin: 0; font-size: 15px; font-weight: 700; color: var(--ink); word-break: break-all; }
.dlp-mono { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-weight: 500; font-size: 12.5px; }
.dlp-hash { display: flex; align-items: flex-start; gap: 10px; }
.dlp-hash span { flex: 1; min-width: 0; }
.dlp-copy {
  flex-shrink: 0; padding: 4px 12px; border-radius: 999px; cursor: pointer;
  font-size: 12px; font-weight: 600; color: var(--brand); background: #eef4ff; border: 1px solid #dbe7ff;
}
.dlp-copy:hover { background: #e2ecff; }

.dlp-toast {
  position: fixed; left: 50%; bottom: 40px; transform: translateX(-50%);
  padding: 10px 20px; border-radius: 999px; font-size: 13px; color: #fff;
  background: rgba(16, 24, 40, .92); box-shadow: 0 12px 30px rgba(16, 24, 40, .3); z-index: 20;
}

.dlp-section { padding-top: 64px; padding-bottom: 8px; }
.dlp-features { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
.dlp-feature {
  padding: 26px 22px; border-radius: 20px; background: #fff;
  border: 1px solid var(--line); box-shadow: 0 8px 24px rgba(16, 24, 40, .05);
  transition: transform .2s ease, box-shadow .2s ease;
}
.dlp-feature:hover { transform: translateY(-4px); box-shadow: 0 18px 36px rgba(16, 24, 40, .1); }
.dlp-feature h3 { margin: 16px 0 6px; font-size: 16px; font-weight: 700; color: var(--ink); }
.dlp-feature p { margin: 0; font-size: 13px; color: var(--muted); line-height: 1.7; }
.dlp-feature-icon {
  display: inline-flex; align-items: center; justify-content: center;
  width: 48px; height: 48px; border-radius: 15px; font-size: 22px;
}
.dlp-feature--blue .dlp-feature-icon { background: #e8f0fe; color: #2563eb; }
.dlp-feature--cyan .dlp-feature-icon { background: #e0f7f8; color: #0891b2; }
.dlp-feature--rose .dlp-feature-icon { background: #fdeaea; color: #e11d48; }
.dlp-feature--green .dlp-feature-icon { background: #e6f7ee; color: #10b981; }

.dlp-steps { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
.dlp-steps li {
  display: flex; gap: 14px; padding: 24px 22px; border-radius: 20px;
  background: #fff; border: 1px solid var(--line); box-shadow: 0 8px 24px rgba(16, 24, 40, .05);
}
.dlp-steps b { font-size: 15px; color: var(--ink); }
.dlp-steps p { margin: 6px 0 0; font-size: 13px; color: var(--muted); line-height: 1.7; }
.dlp-step-index {
  flex-shrink: 0; width: 32px; height: 32px; border-radius: 11px;
  display: inline-flex; align-items: center; justify-content: center;
  font-weight: 800; font-size: 14px; color: #fff;
  background: linear-gradient(135deg, var(--brand) 0%, var(--brand-2) 100%);
  box-shadow: 0 6px 14px rgba(37, 99, 235, .3);
}

.dlp-notes-card { padding: 30px 32px; }
.dlp-notes { margin: 4px 0 0; padding: 0; list-style: none; color: #33445f; font-size: 14px; }
.dlp-notes li { position: relative; padding: 7px 0 7px 24px; line-height: 1.7; }
.dlp-notes li::before {
  content: ""; position: absolute; left: 4px; top: 16px;
  width: 7px; height: 7px; border-radius: 50%;
  background: linear-gradient(135deg, var(--brand), var(--brand-2));
}

.dlp-footer { margin-top: 72px; padding: 26px 0 36px; border-top: 1px solid var(--line); }
.dlp-footer-inner { display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-between; font-size: 13px; color: var(--muted); }
.dlp-footer a { color: var(--brand); text-decoration: none; }
.dlp-footer a:hover { text-decoration: underline; }

/* ---------- 响应式 ---------- */
@media (max-width: 980px) {
  .dlp-hero { grid-template-columns: 1fr; gap: 8px; padding-top: 44px; text-align: center; }
  /* 用户已经在手机上：隐藏机型预览与扫码卡片，第一屏留给标题与下载按钮 */
  .dlp-hero-visual { display: none; }
  .dlp-title { font-size: 36px; }
  .dlp-title-accent { margin-left: auto; margin-right: auto; }
  .dlp-subtitle { margin-bottom: 24px; max-width: none; }
  .dlp-actions { justify-content: center; }
  .dlp-meta { justify-content: center; }
  .dlp-security { justify-content: center; }
  .dlp-features { grid-template-columns: 1fr 1fr; }
  .dlp-steps { grid-template-columns: 1fr; }
  .dlp-spec-card { grid-template-columns: 1fr; gap: 20px; padding: 24px 22px; }
}
@media (max-width: 620px) {
  .dlp-shell { padding: 0 18px; }
  .dlp-hero { padding-top: 36px; }
  .dlp-title { font-size: 31px; }
  .dlp-subtitle { font-size: 15px; }
  .dlp-cta { width: 100%; padding: 0 20px; }
  .dlp-features { grid-template-columns: 1fr; }
  .dlp-spec { grid-template-columns: 1fr 1fr; }
  .dlp-card { border-radius: 18px; }
  .dlp-h2 { font-size: 22px; }
  .dlp-section { padding-top: 48px; }
}
`

export default DownloadPage
