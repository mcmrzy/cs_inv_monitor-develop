import React, { useEffect, useRef } from 'react'

/**
 * RotatingGlobe — 自绘 Canvas 滚动地球
 *
 * 纯 2D Canvas 正交投影实现，无需 echarts-gl / WebGL：
 * - 深蓝球体径向渐变 + 左上高光
 * - 纬线椭圆 + 经线随自转角度移动（正面亮、背面暗）
 * - 电站光点按球面坐标投影，仅正面可见（背面淡出）
 * - requestAnimationFrame 持续自转
 */

export interface GlobeStation {
  id: number | string
  latitude: number
  longitude: number
  status: number // 0=离线 1=在线 2=故障
}

interface RotatingGlobeProps {
  stations?: GlobeStation[]
  className?: string
  style?: React.CSSProperties
}

// 球面点经绕 Y 轴旋转后的正交投影坐标（返回 [x, y, z]，z>0 朝向观察者）
function projectPoint(latDeg: number, lonDeg: number, rotDeg: number, radius: number): [number, number, number] {
  const lat = (latDeg * Math.PI) / 180
  const lon = ((lonDeg + rotDeg) * Math.PI) / 180
  const x = radius * Math.cos(lat) * Math.sin(lon)
  const y = -radius * Math.sin(lat)
  const z = radius * Math.cos(lat) * Math.cos(lon)
  return [x, y, z]
}

const STATUS_COLORS: Record<number, string> = {
  0: 'rgba(148,163,184,0.85)',
  1: 'rgba(0,255,136,0.95)',
  2: 'rgba(255,77,109,0.95)',
}

const RotatingGlobe: React.FC<RotatingGlobeProps> = ({ stations = [], className, style }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const rotRef = useRef(0)
  const stationsRef = useRef<GlobeStation[]>(stations)

  useEffect(() => {
    stationsRef.current = stations
  }, [stations])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return

    let raf = 0
    let width = 0
    let height = 0

    const resize = () => {
      const parent = canvas.parentElement
      if (!parent) return
      const dpr = window.devicePixelRatio || 1
      width = parent.clientWidth
      height = parent.clientHeight
      canvas.width = width * dpr
      canvas.height = height * dpr
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }
    resize()
    const observer = new ResizeObserver(resize)
    if (canvas.parentElement) observer.observe(canvas.parentElement)

    const draw = () => {
      const cx = width / 2
      const cy = height / 2
      const R = Math.min(width, height) * 0.38
      if (R < 10) return
      const rot = rotRef.current

      ctx.clearRect(0, 0, width, height)

      // ── 球体 ──
      const sphereGrad = ctx.createRadialGradient(cx - R * 0.35, cy - R * 0.42, R * 0.08, cx, cy, R)
      sphereGrad.addColorStop(0, 'rgba(59,130,246,0.85)')
      sphereGrad.addColorStop(0.35, 'rgba(13,50,92,0.92)')
      sphereGrad.addColorStop(0.75, 'rgba(5,20,45,0.96)')
      sphereGrad.addColorStop(1, 'rgba(2,10,28,0.98)')
      ctx.beginPath()
      ctx.arc(cx, cy, R, 0, Math.PI * 2)
      ctx.fillStyle = sphereGrad
      ctx.fill()

      // 球体边缘描光
      ctx.beginPath()
      ctx.arc(cx, cy, R, 0, Math.PI * 2)
      ctx.strokeStyle = 'rgba(0,212,255,0.25)'
      ctx.lineWidth = 1
      ctx.stroke()

      // ── 纬线（绕 X 轴的水平圆，正交投影为椭圆）──
      for (let lat = -60; lat <= 60; lat += 30) {
        const latRad = (lat * Math.PI) / 180
        const rx = R * Math.cos(latRad)
        const ry = R * Math.abs(Math.sin(latRad)) * 0.55 + R * 0.06
        ctx.beginPath()
        ctx.ellipse(cx, cy, Math.max(rx, 1), Math.max(ry, 1), 0, 0, Math.PI * 2)
        ctx.strokeStyle = 'rgba(0,212,255,0.16)'
        ctx.lineWidth = 1
        ctx.stroke()
      }

      // ── 经线（随自转移动，正面亮背面暗）──
      for (let L = -120; L <= 240; L += 30) {
        const a = ((L + rot) * Math.PI) / 180
        const sinA = Math.sin(a)
        const cosA = Math.cos(a)
        const front = cosA > 0
        ctx.beginPath()
        for (let lat = -90; lat <= 90; lat += 4) {
          const latRad = (lat * Math.PI) / 180
          const sx = cx + R * Math.cos(latRad) * sinA
          const sy = cy - R * Math.sin(latRad)
          if (lat === -90) ctx.moveTo(sx, sy)
          else ctx.lineTo(sx, sy)
        }
        ctx.strokeStyle = front ? 'rgba(0,212,255,0.28)' : 'rgba(0,212,255,0.08)'
        ctx.lineWidth = 1
        ctx.stroke()
      }

      // ── 电站光点（球面投影，仅正面可见）──
      for (const s of stationsRef.current) {
        if (!s.latitude || !s.longitude) continue
        const [x, y, z] = projectPoint(s.latitude, s.longitude, rot, R)
        if (z <= 0) continue
        const sx = cx + x
        const sy = cy + y
        const depth = z / R // 0~1，越靠近中心越亮
        const color = STATUS_COLORS[s.status] ?? STATUS_COLORS[1]
        const alpha = 0.35 + 0.65 * depth

        // 光晕
        const glow = ctx.createRadialGradient(sx, sy, 0, sx, sy, 7)
        glow.addColorStop(0, color.replace(/[\d.]+\)$/, `${(0.45 * alpha).toFixed(2)})`))
        glow.addColorStop(1, 'rgba(0,0,0,0)')
        ctx.beginPath()
        ctx.arc(sx, sy, 7, 0, Math.PI * 2)
        ctx.fillStyle = glow
        ctx.fill()

        // 核心点
        ctx.beginPath()
        ctx.arc(sx, sy, 2.2, 0, Math.PI * 2)
        ctx.fillStyle = color
        ctx.fill()
        ctx.strokeStyle = 'rgba(255,255,255,0.85)'
        ctx.lineWidth = 0.8
        ctx.stroke()
      }

      // ── 顶部扫光（模拟大气层反光）──
      const sheen = ctx.createRadialGradient(cx - R * 0.45, cy - R * 0.5, 0, cx - R * 0.45, cy - R * 0.5, R * 0.9)
      sheen.addColorStop(0, 'rgba(180,225,255,0.10)')
      sheen.addColorStop(1, 'rgba(180,225,255,0)')
      ctx.beginPath()
      ctx.arc(cx, cy, R, 0, Math.PI * 2)
      ctx.fillStyle = sheen
      ctx.fill()

      rotRef.current = (rot + 0.25) % 360
      raf = requestAnimationFrame(draw)
    }

    raf = requestAnimationFrame(draw)
    return () => {
      cancelAnimationFrame(raf)
      observer.disconnect()
    }
  }, [])

  return <canvas ref={canvasRef} className={className} style={{ width: '100%', height: '100%', ...style }} />
}

export default React.memo(RotatingGlobe)
