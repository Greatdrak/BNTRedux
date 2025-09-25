'use client'

import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './page.module.css'

interface ShipData {
  name: string
  hull: number
  hull_max: number
  hull_lvl: number
  shield: number
  shield_max: number
  shield_lvl: number
  engine_lvl: number
  comp_lvl: number
  sensor_lvl: number
  power_lvl: number
  beam_lvl: number
  torp_launcher_lvl: number
  cloak_lvl: number
  armor: number
  armor_max: number
  cargo: number
  fighters: number
  torpedoes: number
  colonists: number
  energy: number
  energy_max: number
  device_space_beacons: number
  device_warp_editors: number
  device_genesis_torpedoes: number
  device_mine_deflectors: number
  device_emergency_warp: boolean
  device_escape_pod: boolean
  device_fuel_scoop: boolean
  device_last_seen: boolean
  atSpecialPort: boolean
}

interface MeResponse {
  player: {
    handle: string
    credits: number
  }
  ship: {
    credits: number
  }
  inventory: {
    ore: number
    organics: number
    goods: number
    energy: number
    colonists?: number
  }
}

const fetcher = async (url: string) => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('No session')
  
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${session.access_token}`
    }
  })
  
  if (!response.ok) {
    const error = await response.json()
    throw new Error(error.error?.message || 'Failed to fetch')
  }
  
  return response.json()
}

function ShipPageContent() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  const [showCapacity, setShowCapacity] = useState(false)
  
  // Get universe_id from URL params
  const universeId = searchParams.get('universe_id')
  
  // Build API URLs with universe parameter
  const shipUrl = universeId ? `/api/ship?universe_id=${universeId}` : '/api/ship'
  const meUrl = universeId ? `/api/me?universe_id=${universeId}` : '/api/me'
  const capacityUrl = universeId ? `/api/ship/capacity?universe_id=${universeId}` : '/api/ship/capacity'
  
  const { data: shipData, error: shipError, mutate: mutateShip } = useSWR<ShipData>(shipUrl, fetcher)
  const { data: meData, error: meError } = useSWR<MeResponse>(meUrl, fetcher)
  const { data: capacityData, error: capacityError } = useSWR(capacityUrl, fetcher)

  const handleRename = async () => {
    if (!shipData) return
    
    const newName = prompt('Enter new ship name:', shipData.name)
    if (!newName || newName.trim() === shipData.name) return
    
    setLoading(true)
    setStatus('')
    
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')
      
      const response = await fetch('/api/ship/rename', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ 
          name: newName.trim(),
          universe_id: universeId
        })
      })
      
      const result = await response.json()
      
      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus('Ship renamed successfully!')
        mutateShip()
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Rename failed'}`)
    } finally {
      setLoading(false)
    }
  }

  if (shipError || meError) {
    return (
      <div className={styles.container}>
        <div className={styles.error}>
          <h2>Error Loading Ship Data</h2>
          <p>{shipError?.message || meError?.message}</p>
          <button onClick={() => router.push('/game')} className={styles.backBtn}>
            Back to Game
          </button>
        </div>
      </div>
    )
  }

  if (!shipData || !meData) {
    return (
      <div className={styles.container}>
        <div className={styles.loading}>Loading ship data...</div>
      </div>
    )
  }

  const credits = meData.ship?.credits || 0
  const inventory = meData.inventory || { ore: 0, organics: 0, goods: 0, energy: 0, colonists: 0 }

  // Calculate average tech level
  const avgTechLevel = (
    shipData.hull_lvl + shipData.engine_lvl + shipData.power_lvl + 
    shipData.comp_lvl + shipData.sensor_lvl + shipData.shield_lvl + 
    shipData.beam_lvl + shipData.torp_launcher_lvl + shipData.cloak_lvl
  ) / 9

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <h1>Ship Report</h1>
          <p className={styles.playerInfo}>{meData.player?.handle || 'Unknown'}</p>
        </div>
        <div className={styles.headerRight}>
          <button 
            onClick={handleRename} 
            disabled={loading}
            className={styles.renameBtn}
          >
            Rename Ship
          </button>
          <button onClick={() => router.push('/game')} className={styles.backBtn}>
            Back to Game
          </button>
        </div>
      </div>

      {/* Main Content */}
      <div className={styles.mainContent}>
        {/* Left Panel - Ship Info & Tech Levels */}
        <div className={styles.leftPanel}>
          <div className={styles.shipInfo}>
            <h2>{shipData.name}</h2>
            <div className={styles.shipImage}>
              <img 
                src="/images/ShipLevel1.png" 
                alt="Ship" 
                className={styles.shipImg}
              />
            </div>
            <div className={styles.credits}>
              <span className={styles.creditsLabel}>Credits:</span>
              <span className={styles.creditsValue}>{credits.toLocaleString()}</span>
            </div>
          </div>

          <div className={styles.techLevels}>
            <h3>Component Levels</h3>
            <div className={styles.techGrid}>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Hull</span>
                <span className={styles.techValue}>Lv {shipData.hull_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Engines</span>
                <span className={styles.techValue}>Lv {shipData.engine_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Power</span>
                <span className={styles.techValue}>Lv {shipData.power_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Computer</span>
                <span className={styles.techValue}>Lv {shipData.comp_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Sensors</span>
                <span className={styles.techValue}>Lv {shipData.sensor_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Armor</span>
                <span className={styles.techValue}>Lv {Math.max(0, shipData.armor_max)}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Shields</span>
                <span className={styles.techValue}>Lv {shipData.shield_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Beam Weapons</span>
                <span className={styles.techValue}>Lv {shipData.beam_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Torpedo Launchers</span>
                <span className={styles.techValue}>Lv {shipData.torp_launcher_lvl}</span>
              </div>
              <div className={styles.techItem}>
                <span className={styles.techLabel}>Cloak</span>
                <span className={styles.techValue}>Lv {shipData.cloak_lvl}</span>
              </div>
            </div>
            <div className={styles.avgTech}>
              <span className={styles.avgTechLabel}>Average Tech Level:</span>
              <span className={styles.avgTechValue}>{avgTechLevel.toFixed(2)}</span>
            </div>
          </div>
        </div>

        {/* Right Panel - Holds, Armor & Weapons */}
        <div className={styles.rightPanel}>
          <div className={styles.holdsSection}>
            <h3>Holds</h3>
            <div className={styles.holdsGrid}>
              <div className={styles.holdItem}>
                <span className={styles.holdIcon}>🪨</span>
                <span className={styles.holdLabel}>Ore</span>
                <span className={styles.holdValue}>{(inventory.ore || 0).toLocaleString()}</span>
              </div>
              <div className={styles.holdItem}>
                <span className={styles.holdIcon}>🌿</span>
                <span className={styles.holdLabel}>Organics</span>
                <span className={styles.holdValue}>{(inventory.organics || 0).toLocaleString()}</span>
              </div>
              <div className={styles.holdItem}>
                <span className={styles.holdIcon}>📦</span>
                <span className={styles.holdLabel}>Goods</span>
                <span className={styles.holdValue}>{(inventory.goods || 0).toLocaleString()}</span>
              </div>
              <div className={styles.holdItem}>
                <span className={styles.holdIcon}>👤</span>
                <span className={styles.holdLabel}>Colonists</span>
                <span className={styles.holdValue}>
                  {shipData.colonists || 0} / {capacityData?.colonists?.max || Math.round(100 * Math.pow(1.5, shipData.hull_lvl || 1))}
                </span>
              </div>
              <div className={styles.holdItem}>
                <span className={styles.holdIcon}>⚡</span>
                <span className={styles.holdLabel}>Energy</span>
                <span className={styles.holdValue}>{shipData.energy || 0} / {shipData.energy_max || 0}</span>
              </div>
            </div>
          </div>

          <div className={styles.weaponsSection}>
            <h3>Armor & Weapons</h3>
            <div className={styles.weaponsGrid}>
              <div className={styles.weaponItem}>
                <span className={styles.weaponIcon}>🛡️</span>
                <span className={styles.weaponLabel}>Armor Points</span>
                <span className={styles.weaponValue}>{shipData.armor} / {shipData.armor_max}</span>
              </div>
              <div className={styles.weaponItem}>
                <span className={styles.weaponIcon}>✈️</span>
                <span className={styles.weaponLabel}>Fighters</span>
                <span className={styles.weaponValue}>
                  {shipData.fighters} / {capacityData?.computer?.capacity || Math.round(100 * Math.pow(1.5, (shipData.comp_lvl || 1) - 1))}
                </span>
              </div>
              <div className={styles.weaponItem}>
                <span className={styles.weaponIcon}>🚀</span>
                <span className={styles.weaponLabel}>Torpedoes</span>
                <span className={styles.weaponValue}>
                  {shipData.torpedoes} / {capacityData?.torp_launcher?.capacity || Math.round(100 * Math.pow(1.5, (shipData.torp_launcher_lvl || 1) - 1))}
                </span>
              </div>
            </div>
          </div>

          <div className={styles.devicesSection}>
            <h3>Devices</h3>
            <div className={styles.devicesGrid}>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>📡</span>
                <span className={styles.deviceLabel}>Space Beacons</span>
                <span className={styles.deviceValue}>{shipData.device_space_beacons}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>🔧</span>
                <span className={styles.deviceLabel}>Warp Editors</span>
                <span className={styles.deviceValue}>{shipData.device_warp_editors}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>💥</span>
                <span className={styles.deviceLabel}>Genesis Torpedoes</span>
                <span className={styles.deviceValue}>{shipData.device_genesis_torpedoes}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>🛡️</span>
                <span className={styles.deviceLabel}>Mine Deflectors</span>
                <span className={styles.deviceValue}>{shipData.device_mine_deflectors}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>⚡</span>
                <span className={styles.deviceLabel}>Emergency Warp</span>
                <span className={styles.deviceValue}>{shipData.device_emergency_warp ? 'Yes' : 'No'}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>🛟</span>
                <span className={styles.deviceLabel}>Escape Pod</span>
                <span className={styles.deviceValue}>{shipData.device_escape_pod ? 'Yes' : 'No'}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>⛽</span>
                <span className={styles.deviceLabel}>Fuel Scoop</span>
                <span className={styles.deviceValue}>{shipData.device_fuel_scoop ? 'Yes' : 'No'}</span>
              </div>
              <div className={styles.deviceItem}>
                <span className={styles.deviceIcon}>👁️</span>
                <span className={styles.deviceLabel}>Last Ship Seen</span>
                <span className={styles.deviceValue}>{shipData.device_last_seen ? 'Yes' : 'No'}</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Capacity Information - Collapsible */}
      <div className={styles.capacitySection}>
        <button 
          className={styles.capacityToggle}
          onClick={() => setShowCapacity(!showCapacity)}
        >
          <span>Capacity Information</span>
          <span className={styles.toggleIcon}>{showCapacity ? '▼' : '▶'}</span>
        </button>
        
        {showCapacity && capacityData && (
          <div className={styles.capacityContent}>
            <div className={styles.capacityGrid}>
              <div className={styles.capacityItem}>
                <strong>Fighters:</strong> Limited by Computer Level ({shipData.comp_lvl}) = {capacityData.computer?.capacity?.toLocaleString() || 'N/A'} max
              </div>
              <div className={styles.capacityItem}>
                <strong>Torpedoes:</strong> Limited by Torpedo Launcher Level ({shipData.torp_launcher_lvl}) = {capacityData.torp_launcher?.capacity?.toLocaleString() || 'N/A'} max
              </div>
              <div className={styles.capacityItem}>
                <strong>Armor:</strong> Limited by Armor Level = {capacityData.armor?.capacity?.toLocaleString() || 'N/A'} max
              </div>
              <div className={styles.capacityItem}>
                <strong>Colonists:</strong> Limited by Hull Level ({shipData.hull_lvl}) = {capacityData.hull?.capacity?.toLocaleString() || 'N/A'} max
              </div>
              <div className={styles.capacityItem}>
                <strong>Energy:</strong> Limited by Power Level ({shipData.power_lvl}) = {capacityData.power?.capacity?.toLocaleString() || 'N/A'} max
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Status Message */}
      {status && (
        <div className={styles.status}>
          {status}
        </div>
      )}
    </div>
  )
}

export default function ShipPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ShipPageContent />
    </Suspense>
  )
}