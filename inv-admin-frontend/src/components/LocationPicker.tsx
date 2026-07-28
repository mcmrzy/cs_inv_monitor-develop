import React, { useRef, useCallback, useImperativeHandle, forwardRef, useEffect, useState } from 'react'
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

/* Click handler component */
function MapClickHandler({ onPositionChange }: { onPositionChange: (pos: LatLng) => void }) {
  useMapEvents({
    click(e) {
      onPositionChange({ lat: e.latlng.lat, lng: e.latlng.lng })
    },
  })
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

    // Sync external value
    useEffect(() => {
      if (isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0)) {
        setPosition(value)
      }
    }, [value])

    useImperativeHandle(ref, () => ({
      flyTo: (center: [number, number], zoom = 12) => {
        if (!center || isNaN(center[0]) || isNaN(center[1])) return
        setFlyTarget(center)
        setFlyZoom(zoom)
        // Reset target after animation to allow re-flying to same location
        setTimeout(() => setFlyTarget(null), 2000)
      },
      setPosition: (pos: LatLng) => {
        if (!isValidLatLng(pos)) return
        setPosition(pos)
        onChange?.(pos)
      },
    }))

    const handlePositionChange = useCallback(
      (pos: LatLng) => {
        setPosition(pos)
        onChange?.(pos)
      },
      [onChange],
    )

    const handleLocate = useCallback(() => {
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          (geoPos) => {
            const newPos = { lat: geoPos.coords.latitude, lng: geoPos.coords.longitude }
            setPosition(newPos)
            onChange?.(newPos)
            setFlyTarget([newPos.lat, newPos.lng])
            setFlyZoom(15)
            setTimeout(() => setFlyTarget(null), 2000)
          },
          () => {},
          { timeout: 5000 },
        )
      }
    }, [onChange])

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
          center={isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0) ? [value.lat, value.lng] : initialCenter}
          zoom={isValidLatLng(value) && (value.lat !== 0 || value.lng !== 0) ? 14 : initialZoom}
          style={{ width: '100%', height: typeof height === 'number' ? `${height}px` : height }}
          ref={(instance) => {
            mapRef.current = instance
          }}
        >
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <MapClickHandler onPositionChange={handlePositionChange} />
          <FlyToController target={flyTarget} zoom={flyZoom} />
          {isValidLatLng(position) && position.lat !== 0 && (
            <Marker position={[position.lat, position.lng]} icon={defaultIcon} />
          )}
        </MapContainer>
      </div>
    )
  },
)

LocationPicker.displayName = 'LocationPicker'

export default LocationPicker
