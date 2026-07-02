import React, { useEffect, useRef } from 'react'
import { MapContainer, TileLayer, Marker, Tooltip, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import useTranslation from '@/hooks/useTranslation'

interface Station {
  id: number
  name: string
  latitude: number
  longitude: number
  capacity: number
  status: number // 0=离线, 1=在线, 2=故障
}

interface MapPanelProps {
  stations: Station[]
  summary?: {
    totalStations: number
    totalDevices: number
    onlineDevices: number
  }
}

const getMarkerClass = (status: number) => {
  if (status === 2) return 'bs-map-marker bs-map-marker-fault'
  if (status === 0) return 'bs-map-marker bs-map-marker-offline'
  return 'bs-map-marker'
}

const createMarkerIcon = (status: number) =>
  L.divIcon({
    className: getMarkerClass(status),
    iconSize: [12, 12],
    iconAnchor: [6, 6],
  })

// 自动轮转组件
const MapAutoRotate: React.FC<{ stations: Station[] }> = ({ stations }) => {
  const map = useMap()
  const indexRef = useRef(0)

  useEffect(() => {
    if (!stations || stations.length === 0) return

    const timer = setInterval(() => {
      indexRef.current = (indexRef.current + 1) % stations.length
      const station = stations[indexRef.current]
      if (station?.latitude && station?.longitude) {
        map.flyTo([station.latitude, station.longitude], 10, { duration: 2 })
      }
    }, 30000)

    return () => clearInterval(timer)
  }, [map, stations])

  return null
}

const MapPanel: React.FC<MapPanelProps> = ({
  stations = [],
  summary = { totalStations: 0, totalDevices: 0, onlineDevices: 0 },
}) => {
  const { t } = useTranslation()

  return (
    <div className="bs-center">
      <div className="bs-panel bs-map-panel">
        <div className="bs-corner-tr"></div>
        <div className="bs-corner-bl"></div>
        <div className="bs-map-stats">
          <span className="bs-map-stat">
            <strong>{summary.totalStations}</strong> {t('bigScreen.stations')}
          </span>
          <span className="bs-map-stat">
            <strong>{summary.totalDevices}</strong> {t('bigScreen.devices')}
          </span>
          <span className="bs-map-stat">
            <strong>{summary.onlineDevices}</strong> {t('bigScreen.online')}
          </span>
        </div>
        <MapContainer
          center={[35.5, 105]}
          zoom={4}
          style={{ width: '100%', height: '100%' }}
          zoomControl={false}
          attributionControl={false}
        >
          <TileLayer url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png" />
          {stations.map((s) => (
            <Marker
              key={s.id}
              position={[s.latitude, s.longitude]}
              icon={createMarkerIcon(s.status)}
            >
              <Tooltip direction="top" offset={[0, -8]}>
                <span>{s.name} ({s.capacity} kW)</span>
              </Tooltip>
            </Marker>
          ))}
          <MapAutoRotate stations={stations} />
        </MapContainer>
      </div>
    </div>
  )
}

export default React.memo(MapPanel)
