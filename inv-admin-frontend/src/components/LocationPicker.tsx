import React, { useRef, useCallback, useImperativeHandle, forwardRef, useEffect, useState, useMemo } from 'react'
import { MapContainer, TileLayer, Marker, useMapEvents, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { Input, Space, Typography } from 'antd'
import { AimOutlined } from '@ant-design/icons'

const { Text } = Typography

export interface LatLng {
  lat: number
  lng: number
}

export interface LocationPickerRef {
  flyTo: (center: [number, number], zoom?: number) => void
  setPosition: (pos: LatLng) => void
}

interface LocationPickerProps {
  value?: LatLng
  onChange?: (pos: LatLng) => void
  initialCenter?: [number, number]
  initialZoom?: number
  height?: number | string
}

/* Marker icon - fix default leaflet icon issue */
const defaultIcon = L.icon({
  iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
  iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
  shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
  iconSize: [25, 41],
  iconAnchor: [12, 41],
  shadowSize: [41, 41],
})

/* Helper: validate coordinates */
function isValidLatLng(pos: { lat: number; lng: number } | null | undefined): pos is LatLng {
  return !!pos && typeof pos.lat === 'number' && typeof pos.lng === 'number' && !isNaN(pos.lat) && !isNaN(pos.lng)
}

// ============================================================
// GCJ-02 coordinate conversion (for AMap tiles in China)
// ============================================================
const PI = Math.PI
const A = 6378245.0
const EE = 0.00669342162296594323

function inChina(lat: number, lng: number) {
  return lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271
}

function transformLat(x: number, y: number) {
  let ret = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x))
  ret += (20 * Math.sin(6 * x * PI) + 20 * Math.sin(2 * x * PI)) * 2 / 3
  ret += (20 * Math.sin(y * PI) + 40 * Math.sin(y / 3 * PI)) * 2 / 3
  ret += (160 * Math.sin(y / 12 * PI) + 320 * Math.sin(y * PI / 30)) * 2 / 3
  return ret
}

function transformLng(x: number, y: number) {
  let ret = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x))
  ret += (20 * Math.sin(6 * x * PI) + 20 * Math.sin(2 * x * PI)) * 2 / 3
  ret += (20 * Math.sin(x * PI) + 40 * Math.sin(x / 3 * PI)) * 2 / 3
  ret += (150 * Math.sin(x / 12 * PI) + 300 * Math.sin(x / 30 * PI)) * 2 / 3
  return ret
}

function wgs84ToGcj02(lat: number, lng: number): [number, number] {
  if (!inChina(lat, lng)) return [lat, lng]
  let dLat = transformLat(lng - 105, lat - 35)
  let dLng = transformLng(lng - 105, lat - 35)
  const radLat = lat / 180 * PI
  let magic = Math.sin(radLat)
  magic = 1 - EE * magic * magic
  const sqrtMagic = Math.sqrt(magic)
  dLat = (dLat * 180) / ((A * (1 - EE)) / (magic * sqrtMagic) * PI)
  dLng = (dLng * 180) / ((A / sqrtMagic) * Math.cos(radLat) * PI)
  return [lat + dLat, lng + dLng]
}

function gcj02ToWgs84(lat: number, lng: number): [number, number] {
  if (!inChina(lat, lng)) return [lat, lng]
  const [gcjLat, gcjLng] = wgs84ToGcj02(lat, lng)
  const dLat = gcjLat - lat
  const dLng = gcjLng - lng
  return [lat - dLat, lng - dLng]
}

// Module-level cache for region detection
let cachedRegion: string | null = null
let regionPromise: Promise<string> | null = null

/**
 * Detect client region via ip-api.com (client-side, reflects user's actual network location).
 * Falls back to CN if ip-api.com is blocked (likely means user is in China).
 */
function detectRegion(): Promise<string> {
  // Check localStorage first (survives page refresh)
  const stored = localStorage.getItem('map_region')
  if (stored) {
    cachedRegion = stored
    return Promise.resolve(stored)
  }
  if (cachedRegion) return Promise.resolve(cachedRegion)
  if (!regionPromise) {
    regionPromise = fetch('https://ip-api.com/json/?fields=status,countryCode')
      .then(res => res.json())
      .then(data => {
        cachedRegion = data?.countryCode || 'CN'
        localStorage.setItem('map_region', cachedRegion!)
        return cachedRegion!
      })
      .catch(() => {
        cachedRegion = 'CN'
        localStorage.setItem('map_region', cachedRegion!)
        return cachedRegion!
      })
  }
  return regionPromise
}

/* Click handler component */
function MapClickHandler({ onPositionChange }: { onPositionChange: (pos: LatLng) => void }) {
  useMapEvents({
    click(e) {
      onPositionChange({ lat: e.latlng.lat, lng: e.latlng.lng })
    },
  })
  return null
}

/* Fix map size when container is inside a modal/dialog with animation */
function MapSizeFixer() {
  const map = useMap()
  useEffect(() => {
    const fixSize = () => map.invalidateSize({ animate: false })

    // Modal animation may not be complete yet; try multiple times
    const timers = [50, 150, 300, 600, 1200].map(ms => setTimeout(fixSize, ms))

    // Watch for container resize
    const container = map.getContainer()
    const observer = new ResizeObserver(fixSize)
    observer.observe(container)

    // Also fix size when any ancestor modal finishes transitioning
    const onTransitionEnd = (e: TransitionEvent) => {
      if (e.target instanceof HTMLElement && container.closest('.ant-modal')) {
        fixSize()
      }
    }
    document.addEventListener('transitionend', onTransitionEnd)

    return () => {
      timers.forEach(clearTimeout)
      observer.disconnect()
      document.removeEventListener('transitionend', onTransitionEnd)
    }
  }, [map])
  return null
}

/* FlyTo controller */
function FlyToController({ target, zoom }: { target: [number, number] | null; zoom: number }) {
  const map = useMap()
  useEffect(() => {
    if (target) {
      const lat = Number(target[0])
      const lng = Number(target[1])
      const z = Number(zoom)
      if (!isNaN(lat) && !isNaN(lng) && !isNaN(z) && isFinite(lat) && isFinite(lng)) {
        try {
          map.invalidateSize({ animate: false })
          map.flyTo([lat, lng], z, { duration: 1.5 })
        } catch { /* ignore leaflet internal errors */ }
      }
    }
  }, [map, target, zoom])
  return null
}

const LocationPicker = forwardRef<LocationPickerRef, LocationPickerProps>(
  ({ value, onChange, initialCenter = [30, 110], initialZoom = 4, height = 300 }, ref) => {
    const mapRef = useRef<L.Map | null>(null)
    const [flyTarget, setFlyTarget] = useState<[number, number] | null>(null)
    const [flyZoom, setFlyZoom] = useState(initialZoom)
    const [position, setPosition] = useState<LatLng | null>(null)
    const [useAmap, setUseAmap] = useState(false)

    // Detect region on mount
    useEffect(() => {
      detectRegion().then(region => setUseAmap(region === 'CN'))
    }, [])

    // Convert WGS-84 to display coords (GCJ-02 for AMap, WGS-84 for OSM)
    const toDisplay = useCallback((lat: number, lng: number): [number, number] => {
      return useAmap ? wgs84ToGcj02(lat, lng) : [lat, lng]
    }, [useAmap])

    // Convert display coords to WGS-84
    const toWgs84 = useCallback((lat: number, lng: number): [number, number] => {
      return useAmap ? gcj02ToWgs84(lat, lng) : [lat, lng]
    }, [useAmap])

    // Sync external value
    useEffect(() => {
      if (isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0)) {
        setPosition(value)
      }
    }, [value])

    useImperativeHandle(ref, () => ({
      flyTo: (center: [number, number], zoom = 12) => {
        if (!center || isNaN(center[0]) || isNaN(center[1])) return
        const display = toDisplay(center[0], center[1])
        setFlyTarget(display)
        setFlyZoom(zoom)
        setTimeout(() => setFlyTarget(null), 2000)
      },
      setPosition: (pos: LatLng) => {
        if (!isValidLatLng(pos)) return
        setPosition(pos)
        onChange?.(pos)
      },
    }), [toDisplay, onChange])

    const handlePositionChange = useCallback(
      (pos: LatLng) => {
        // Convert from display coords (GCJ-02) to WGS-84
        const [wgsLat, wgsLng] = toWgs84(pos.lat, pos.lng)
        const newPos = { lat: wgsLat, lng: wgsLng }
        setPosition(newPos)
        onChange?.(newPos)
      },
      [onChange, toWgs84],
    )

    const handleLocate = useCallback(() => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          (geoPos) => {
            const newPos = { lat: geoPos.coords.latitude, lng: geoPos.coords.longitude }
            setPosition(newPos)
            onChange?.(newPos)
            const display = toDisplay(newPos.lat, newPos.lng)
            setFlyTarget(display)
            setFlyZoom(15)
            setTimeout(() => setFlyTarget(null), 2000)
          },
          () => {},
          { timeout: 5000 },
        )
      }
    }, [onChange, toDisplay])

    // Compute display center for MapContainer
    const displayCenter = useMemo(() => {
      if (isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0)) {
        return toDisplay(value.lat, value.lng)
      }
      return initialCenter
    }, [value, toDisplay, initialCenter])

    const displayZoom = useMemo(() => {
      return isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0) ? 14 : initialZoom
    }, [value, initialZoom])

    // Marker position in display coords
    const markerPosition = useMemo(() => {
      if (isValidLatLng(position) && position.lat !== 0) {
        return toDisplay(position.lat, position.lng)
      }
      return null
    }, [position, toDisplay])

    return (
      <div style={{ border: '1px solid #d9d9d9', borderRadius: 8, overflow: 'hidden' }}>
        <div
          style={{
            padding: '6px 12px',
            background: '#fafafa',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            borderBottom: '1px solid #f0f0f0',
          }}
        >
          <Space size={4}>
            <Text type="secondary" style={{ fontSize: 12 }}>
              {position && position.lat !== 0
                ? `${position.lat.toFixed(6)}, ${position.lng.toFixed(6)}`
                : 'Click on the map to select location'}
            </Text>
          </Space>
          <a onClick={handleLocate} style={{ cursor: 'pointer', fontSize: 16 }} title="Use my location">
            <AimOutlined />
          </a>
        </div>
        <MapContainer
          center={displayCenter}
          zoom={displayZoom}
          style={{ width: '100%', height: typeof height === 'number' ? `${height}px` : height }}
          fadeAnimation={false}
          ref={(instance) => {
            mapRef.current = instance
          }}
        >
          <TileLayer
            attribution={useAmap
              ? '&copy; <a href="https://www.amap.com">高德地图</a>'
              : '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}
            url={useAmap
              ? 'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}'
              : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'}
          />
          <MapSizeFixer />
          <MapClickHandler onPositionChange={handlePositionChange} />
          <FlyToController target={flyTarget} zoom={flyZoom} />
          {markerPosition && (
            <Marker position={markerPosition} icon={defaultIcon} />
          )}
        </MapContainer>
      </div>
    )
  },
)

LocationPicker.displayName = 'LocationPicker'

export default LocationPicker
