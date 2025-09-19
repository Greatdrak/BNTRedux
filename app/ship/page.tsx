'use client'

import { useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import ShipArt from './components/ShipArt'
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

export default function ShipPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  
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
            Back to Sector
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

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1>Ship Report</h1>
        <button 
          onClick={handleRename} 
          disabled={loading}
          className={styles.renameBtn}
        >
          [Rename]
        </button>
      </div>

      <div className={styles.topBar}>
        <div><strong>Player:</strong> {meData.player?.handle || 'Unknown'}</div>
        <div><strong>Ship:</strong> {shipData.name}</div>
        <div><strong>Credits:</strong> {credits.toLocaleString()}</div>
      </div>

      {/* Classic BNT-style Ship Report layout */}
      <div className={styles.reportGrid}>
        <div className={styles.leftCol}>
          <h3>Ship Component Levels</h3>
          <div className={styles.row}><span>Hull</span><i>Level {shipData.hull_lvl}</i></div>
          <div className={styles.row}><span>Engines</span><i>Level {shipData.engine_lvl}</i></div>
          <div className={styles.row}><span>Power</span><i>Level {shipData.power_lvl}</i></div>
          <div className={styles.row}><span>Computer</span><i>Level {shipData.comp_lvl}</i></div>
          <div className={styles.row}><span>Sensors</span><i>Level {shipData.sensor_lvl}</i></div>
          <div className={styles.row}><span>Armor</span><i>Level {Math.max(0, shipData.armor_max)}</i></div>
          <div className={styles.row}><span>Shields</span><i>Level {shipData.shield_lvl}</i></div>
          <div className={styles.row}><span>Beam Weapons</span><i>Level {shipData.beam_lvl}</i></div>
          <div className={styles.row}><span>Torpedo launchers</span><i>Level {shipData.torp_launcher_lvl}</i></div>
          <div className={styles.row}><span>Cloak</span><i>Level {shipData.cloak_lvl}</i></div>
          {/* Average tech level can be computed simply */}
          <div className={styles.row}><span>Average tech level</span><i>Level {(
            (
              shipData.hull_lvl + shipData.engine_lvl + shipData.power_lvl + shipData.comp_lvl + shipData.sensor_lvl + shipData.shield_lvl + shipData.beam_lvl + shipData.torp_launcher_lvl + shipData.cloak_lvl
            ) / 9
          ).toFixed(2)}</i></div>
        </div>

        <div className={styles.rightCol}>
          <div className={styles.sectionHeader}>
            <div><strong>Holds</strong></div>
            <div><strong>Energy</strong> {shipData.energy || 0} / {shipData.energy_max || 0}</div>
          </div>
          <div className={styles.row}><span>Ore</span><span>{(inventory.ore || 0).toLocaleString()}</span></div>
          <div className={styles.row}><span>Organics</span><span>{(inventory.organics || 0).toLocaleString()}</span></div>
          <div className={styles.row}><span>Goods</span><span>{(inventory.goods || 0).toLocaleString()}</span></div>
          <div className={styles.row}><span>Colonists</span><span>{shipData.colonists || 0} / {capacityData?.colonists?.max || shipData.cargo}</span></div>

          <div className={styles.subHeader}>Armor & Weapons</div>
          <div className={styles.row}><span>Armor points</span><span>{shipData.armor} / {shipData.armor_max}</span></div>
          <div className={styles.row}><span>Fighters</span><span>{shipData.fighters} / {capacityData?.fighters?.max || (shipData.comp_lvl * 10)}</span></div>
          <div className={styles.row}><span>Torpedoes</span><span>{shipData.torpedoes} / {capacityData?.torpedoes?.max || (shipData.torp_launcher_lvl * 10)}</span></div>

          <div className={styles.subHeader}>Devices</div>
          <div className={styles.row}><span>Space Beacons</span><span>{shipData.device_space_beacons}</span></div>
          <div className={styles.row}><span>Warp Editors</span><span>{shipData.device_warp_editors}</span></div>
          <div className={styles.row}><span>Genesis Torpedoes</span><span>{shipData.device_genesis_torpedoes}</span></div>
          <div className={styles.row}><span>Mine Deflectors</span><span>{shipData.device_mine_deflectors}</span></div>
          <div className={styles.row}><span>Emergency Warp Device</span><span>{shipData.device_emergency_warp ? 'Yes' : 'No'}</span></div>
          <div className={styles.row}><span>Escape Pod</span><span>{shipData.device_escape_pod ? 'Yes' : 'No'}</span></div>
          <div className={styles.row}><span>Fuel Scoop</span><span>{shipData.device_fuel_scoop ? 'Yes' : 'No'}</span></div>
          <div className={styles.row}><span>Last ship seen device</span><span>{shipData.device_last_seen ? 'Yes' : 'No'}</span></div>
        </div>
      </div>

      {/* Capacity Information */}
      {capacityData && (
        <div className={styles.capacitySection}>
          <h3>Capacity Information</h3>
          <div className={styles.capacityGrid}>
            <div className={styles.capacityItem}>
              <strong>Fighters:</strong> Limited by Computer Level ({shipData.comp_lvl}) = {capacityData.fighters.max} max
            </div>
            <div className={styles.capacityItem}>
              <strong>Torpedoes:</strong> Limited by Torpedo Launcher Level ({shipData.torp_launcher_lvl}) = {capacityData.torpedoes.max} max
            </div>
            <div className={styles.capacityItem}>
              <strong>Armor:</strong> Limited by Armor Level = {capacityData.armor.max} max
            </div>
            <div className={styles.capacityItem}>
              <strong>Colonists:</strong> Limited by Hull Level ({shipData.hull_lvl}) = {capacityData.colonists.max} max
            </div>
            <div className={styles.capacityItem}>
              <strong>Energy:</strong> Limited by Power Level ({shipData.power_lvl}) = {capacityData.energy.max} max
            </div>
          </div>
        </div>
      )}

      {status && (
        <div className={styles.status}>
          {status}
        </div>
      )}

      <div className={styles.footer}>
        <button onClick={() => router.push('/game')} className={styles.backBtn}>
          [Back to Sector]
        </button>
      </div>
    </div>
  )
}
