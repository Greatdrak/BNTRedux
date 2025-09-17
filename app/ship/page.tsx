'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
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
  cargo: number
  fighters: number
  torpedoes: number
  atSpecialPort: boolean
}

interface PlayerData {
  credits: number
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
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  
  const { data: shipData, error: shipError, mutate: mutateShip } = useSWR<ShipData>('/api/ship', fetcher)
  const { data: playerData, error: playerError, mutate: mutatePlayer } = useSWR<PlayerData>('/api/me', fetcher)

  const upgradeCosts = {
    engine: 500 * ((shipData?.engine_lvl || 0) + 1),
    computer: 400 * ((shipData?.comp_lvl || 0) + 1),
    sensors: 400 * ((shipData?.sensor_lvl || 0) + 1),
    shields: 300 * ((shipData?.shield_lvl || 0) + 1),
    hull: 2000 * ((shipData?.hull_lvl || 0) + 1)
  }

  const handleUpgrade = async (attr: keyof typeof upgradeCosts) => {
    if (!shipData || !playerData) return
    
    setLoading(true)
    setStatus('')
    
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')
      
      const response = await fetch('/api/ship/upgrade', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ attr })
      })
      
      const result = await response.json()
      
      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus(`${attr.charAt(0).toUpperCase() + attr.slice(1)} upgraded successfully!`)
        mutateShip()
        mutatePlayer()
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Upgrade failed'}`)
    } finally {
      setLoading(false)
    }
  }

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
        body: JSON.stringify({ name: newName.trim() })
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

  if (shipError || playerError) {
    return (
      <div className={styles.container}>
        <div className={styles.error}>
          <h2>Error Loading Ship Data</h2>
          <p>{shipError?.message || playerError?.message}</p>
          <button onClick={() => router.push('/game')} className={styles.backBtn}>
            Back to Sector
          </button>
        </div>
      </div>
    )
  }

  if (!shipData || !playerData) {
    return (
      <div className={styles.container}>
        <div className={styles.loading}>Loading ship data...</div>
      </div>
    )
  }

  const canAfford = (attr: keyof typeof upgradeCosts) => playerData.credits >= upgradeCosts[attr]
  const canUpgrade = shipData.atSpecialPort

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1>Your Ship: {shipData.name}</h1>
        <button 
          onClick={handleRename} 
          disabled={loading}
          className={styles.renameBtn}
        >
          [Rename]
        </button>
      </div>

      <div className={styles.shipArt}>
        <ShipArt />
      </div>

      <div className={styles.statsGrid}>
        <div className={styles.statRow}>
          <span className={styles.label}>Hull:</span>
          <span className={styles.value}>Level {shipData.hull_lvl}</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Shields:</span>
          <div className={styles.meterContainer}>
            <div className={styles.meter}>
              <div 
                className={styles.meterFill} 
                style={{ width: `${(shipData.shield / shipData.shield_max) * 100}%` }}
              />
            </div>
            <span className={styles.value}>{shipData.shield} / {shipData.shield_max} (Lv.{shipData.shield_lvl})</span>
          </div>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Engines:</span>
          <span className={styles.value}>Level {shipData.engine_lvl}</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Computer:</span>
          <span className={styles.value}>Level {shipData.comp_lvl}</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Sensors:</span>
          <span className={styles.value}>Level {shipData.sensor_lvl}</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Cargo Capacity:</span>
          <span className={styles.value}>{shipData.cargo.toLocaleString()} units (Hull Lv.{shipData.hull_lvl})</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Fighters:</span>
          <span className={styles.value}>{shipData.fighters}</span>
        </div>

        <div className={styles.statRow}>
          <span className={styles.label}>Torpedoes:</span>
          <span className={styles.value}>{shipData.torpedoes}</span>
        </div>
      </div>

      <div className={styles.upgradePanel}>
        <h3>Ship Upgrades</h3>
        {!canUpgrade && (
          <p className={styles.warning}>
            ⚠️ Upgrades are only available at Special ports
          </p>
        )}
        
        <div className={styles.upgradeGrid}>
          {Object.entries(upgradeCosts).map(([attr, cost]) => (
            <div key={attr} className={styles.upgradeItem}>
              <div className={styles.upgradeInfo}>
                <span className={styles.upgradeName}>
                  {attr.charAt(0).toUpperCase() + attr.slice(1)}
                  {attr === 'hull' && (
                    <span className={styles.upgradeDesc}>
                      (Cargo: {shipData ? Math.floor(1000 * Math.pow((shipData.hull_lvl || 1) + 1, 1.8)).toLocaleString() : '0'} units)
                    </span>
                  )}
                </span>
                <span className={styles.upgradeCost}>
                  {cost.toLocaleString()} cr
                </span>
              </div>
              <button
                onClick={() => handleUpgrade(attr as keyof typeof upgradeCosts)}
                disabled={loading || !canUpgrade || !canAfford(attr as keyof typeof upgradeCosts)}
                className={styles.upgradeBtn}
              >
                {loading ? 'Upgrading...' : 'Upgrade'}
              </button>
            </div>
          ))}
        </div>
      </div>

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
