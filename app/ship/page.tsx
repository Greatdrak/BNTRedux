'use client'

import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './page.module.css'
import StatRing from './components/StatRing'

interface ShipData {
  name: string
  hull: number
  hull_max: number
  hull_lvl: number
  shield: number
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
  armor_lvl: number
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
      <div className={styles.hangar}>
        {/* Center Stage */}
        <div className={styles.centerStage}>
          <div className={styles.shipPad}>
            <div className={styles.padRing} />
            <div className={styles.shipImgWrap}>
              <img src="/images/ShipLevel1.png" alt="Ship" className={styles.shipImg} />
            </div>
          </div>
          {/* Radial HUD */}
          <div className={styles.radialHud}>
            {/* Hull */}
            <StatRing label="Hull" value={Math.min(shipData.hull, shipData.hull_max || shipData.hull)} max={shipData.hull_max || shipData.hull || 1} color="#63e6be" title={`Hull ${shipData.hull}/${shipData.hull_max} (Lv ${shipData.hull_lvl})`} />
            {/* Armor */}
            <StatRing label="Armor" value={shipData.armor} max={shipData.armor_max} color="#7ad4ff" title={`Armor ${shipData.armor}/${shipData.armor_max} (Lv ${shipData.armor_lvl || 0})`} />
            {/* Energy (not a hold) */}
            <StatRing label="Energy" value={shipData.energy} max={shipData.energy_max} color="#ffe066" title={`Energy ${shipData.energy}/${shipData.energy_max}`} />
            {/* Fighters */}
            <StatRing label="Fighters" value={shipData.fighters} max={capacityData?.computer?.capacity || Math.round(100 * Math.pow(1.5, (shipData.comp_lvl || 1) - 1))} color="#a78bfa" title={`Fighters ${shipData.fighters}/${capacityData?.computer?.capacity || Math.round(100 * Math.pow(1.5, (shipData.comp_lvl || 1) - 1))}`} />
            {/* Torpedoes */}
            <StatRing label="Torpedoes" value={shipData.torpedoes} max={capacityData?.torp_launcher?.capacity || Math.round(100 * Math.pow(1.5, (shipData.torp_launcher_lvl || 1) - 1))} color="#ff9e9e" title={`Torpedoes ${shipData.torpedoes}/${capacityData?.torp_launcher?.capacity || Math.round(100 * Math.pow(1.5, (shipData.torp_launcher_lvl || 1) - 1))}`} />
          </div>
        </div>

        {/* Quadrant Cards */}
        <div className={styles.cardGrid}>
          {/* Components */}
          <div className={styles.card}>
            <h3>Tech Levels</h3>
            <div className={styles.cardBody}>
              <div>Hull — Lv {shipData.hull_lvl}</div>
              <div>Engines — Lv {shipData.engine_lvl}</div>
              <div>Power — Lv {shipData.power_lvl}</div>
              <div>Computer — Lv {shipData.comp_lvl}</div>
              <div>Sensors — Lv {shipData.sensor_lvl}</div>
              <div>Armor — Lv {shipData.armor_lvl || 0}</div>
              <div>Shields — Lv {shipData.shield_lvl}</div>
              <div>Beam Weapons — Lv {shipData.beam_lvl}</div>
              <div>Torpedo Launchers — Lv {shipData.torp_launcher_lvl}</div>
              <div>Cloak — Lv {shipData.cloak_lvl}</div>
              <div style={{ marginTop:8, opacity:.8 }}>Avg Tech: {avgTechLevel.toFixed(2)}</div>
            </div>
          </div>

          {/* Holds */}
          <div className={styles.card}>
            <h3>
              Holds
              <span style={{ marginLeft:8, opacity:.75 }}>
                Capacity: { (capacityData?.hull?.capacity || Math.round(100 * Math.pow(1.5, (shipData.hull_lvl||1) - 1))).toLocaleString() }
              </span>
            </h3>
            <div className={styles.cardBody}>
              <div>Ore — {inventory.ore?.toLocaleString() || 0}</div>
              <div>Organics — {inventory.organics?.toLocaleString() || 0}</div>
              <div>Goods — {inventory.goods?.toLocaleString() || 0}</div>
              <div>Colonists — {shipData.colonists || 0}</div>
              <div style={{ height:8 }} />
              <div style={{ opacity:.85 }}><strong>Energy Capacity</strong> — {shipData.energy_max || 0}</div>
              <div>Energy — {shipData.energy || 0}</div>
            </div>
          </div>

          {/* Armor & Weapons */}
          <div className={styles.card}>
            <h3>Armor & Weapons</h3>
            <div className={styles.cardBody}>
              <div>Armor Points — {shipData.armor} / {shipData.armor_max}</div>
              <div>Fighters — {shipData.fighters} / {capacityData?.computer?.capacity || Math.round(100 * Math.pow(1.5, (shipData.comp_lvl || 1) - 1))}</div>
              <div>Torpedoes — {shipData.torpedoes} / {capacityData?.torp_launcher?.capacity || Math.round(100 * Math.pow(1.5, (shipData.torp_launcher_lvl || 1) - 1))}</div>
            </div>
          </div>

          {/* Devices */}
          <div className={styles.card}>
            <h3>Devices</h3>
            <div className={styles.cardBody}>
              <div>Space Beacons — {shipData.device_space_beacons}</div>
              <div>Warp Editors — {shipData.device_warp_editors}</div>
              <div>Genesis Torpedoes — {shipData.device_genesis_torpedoes}</div>
              <div>Mine Deflectors — {shipData.device_mine_deflectors}</div>
              <div>Emergency Warp — {shipData.device_emergency_warp ? 'Yes' : 'No'}</div>
              <div>Escape Pod — {shipData.device_escape_pod ? 'Yes' : 'No'}</div>
              <div>Fuel Scoop — {shipData.device_fuel_scoop ? 'Yes' : 'No'}</div>
              <div>Last Ship Seen — {shipData.device_last_seen ? 'Yes' : 'No'}</div>
            </div>
          </div>
        </div>

        {/* Action Bar */}
        <div className={styles.actionBar}>
          <button className={styles.actionBtn} onClick={handleRename} disabled={loading}>Rename</button>
          <button className={styles.actionBtn} onClick={() => router.push('/game')}>Back to Game</button>
        </div>
      </div>

      {/* Capacity Information */}
      <div className={styles.capacitySection}>
        <button 
          className={styles.capacityToggle}
          onClick={() => setShowCapacity(!showCapacity)}
        >
          <span>Capacity Information</span>
          <span className={styles.toggleIcon}>{showCapacity ? '▼' : '▶'}</span>
        </button>
        {showCapacity && (
          <div className={styles.capacityContent}>
            <div className={styles.capacityGrid}>
              <div className={styles.capacityItem}>
                <strong>Formula (BNT classic):</strong> capacity = 100 × (1.5^(tech_level − 1))
              </div>
              <div className={styles.capacityItem} style={{opacity:.85}}>
                Energy is <em>separate</em> from cargo. Holds include commodities and colonists only. Energy capacity is dictated by <strong>Power</strong> tech level.
              </div>
            </div>
          </div>
        )}
      </div>

      {status && <div className={styles.status}>{status}</div>}
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