'use client'

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase-client'
import useSWR from 'swr'
import styles from '../page.module.css'

interface Universe {
  id: string
  name: string
  created_at: string
  sector_count: number
  port_count: number
  planet_count: number
  player_count: number
}

interface AIPlayer {
  player_id: string
  player_name: string
  ship_id: string
  sector_number: number
  credits: number
  ship_levels: {
    hull: number
    engine: number
    power: number
    computer: number
    sensors: number
    beamWeapon: number
    armor: number
    cloak: number
    torpLauncher: number
    shield: number
  }
}

// Fetcher function for SWR
const fetcher = async (url: string) => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('No session')
  
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${session.access_token}`
    }
  })
  
  if (!response.ok) {
    throw new Error('Failed to fetch data')
  }
  
  return response.json()
}

export default function AIPlayersPage() {
  const [aiPlayers, setAiPlayers] = useState<AIPlayer[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)
  const [selectedUniverseId, setSelectedUniverseId] = useState<string>('')
  const [aiCount, setAiCount] = useState(5)

  // Fetch universes list
  const { data: universesData, error: universesError } = useSWR<{ universes: Universe[] }>('/api/admin/universes', fetcher)

  const fetchAIPlayers = async () => {
    if (!selectedUniverseId) return

    try {
      setLoading(true)
      setError(null)

      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/admin/ai-players?universe_id=${selectedUniverseId}`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch AI players')
      }

      const data = await response.json()
      setAiPlayers(data.aiPlayers || [])
    } catch (err) {
      console.error('Error fetching AI players:', err)
      setError(err instanceof Error ? err.message : 'Failed to fetch AI players')
    } finally {
      setLoading(false)
    }
  }

  const createAIPlayers = async () => {
    if (!selectedUniverseId) return

    try {
      setLoading(true)
      setError(null)

      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch('/api/admin/ai-players', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          universeId: selectedUniverseId,
          count: aiCount
        })
      })

      if (!response.ok) {
        throw new Error('Failed to create AI players')
      }

      const data = await response.json()
      if (data.success) {
        setSuccess(`Created ${data.count} AI players successfully!`)
        await fetchAIPlayers()
      } else {
        throw new Error(data.error || 'Failed to create AI players')
      }
    } catch (err) {
      console.error('Error creating AI players:', err)
      setError(err instanceof Error ? err.message : 'Failed to create AI players')
    } finally {
      setLoading(false)
    }
  }

  const removeAIPlayers = async () => {
    if (!selectedUniverseId) return

    try {
      setLoading(true)
      setError(null)

      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/admin/ai-players?universe_id=${selectedUniverseId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to remove AI players')
      }

      const data = await response.json()
      if (data.success) {
        setSuccess('AI players removed successfully!')
        await fetchAIPlayers()
      } else {
        throw new Error(data.error || 'Failed to remove AI players')
      }
    } catch (err) {
      console.error('Error removing AI players:', err)
      setError(err instanceof Error ? err.message : 'Failed to remove AI players')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (selectedUniverseId) {
      fetchAIPlayers()
    }
  }, [selectedUniverseId])

  const formatCredits = (credits: number) => {
    return new Intl.NumberFormat('en-US').format(credits)
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1>🤖 AI Players Management</h1>
        <a href="/admin" className={styles.backLink}>← Back to Admin</a>
      </div>

      <div className={styles.section}>
        <div className={styles.universeSelector}>
          <label htmlFor="universe-select">Select Universe:</label>
          <select
            id="universe-select"
            value={selectedUniverseId}
            onChange={(e) => setSelectedUniverseId(e.target.value)}
            className={styles.select}
          >
            <option value="">Choose a universe...</option>
            {universesData?.universes?.map((universe) => (
              <option key={universe.id} value={universe.id}>
                {universe.name}
              </option>
            ))}
          </select>
        </div>
        
        {selectedUniverseId && (
          <>
            <h2>Universe: {universesData?.universes?.find(u => u.id === selectedUniverseId)?.name}</h2>
            
            <div className={styles.controls}>
          <div className={styles.inputGroup}>
            <label htmlFor="aiCount">Number of AI Players:</label>
            <input
              id="aiCount"
              type="number"
              min="1"
              max="20"
              value={aiCount}
              onChange={(e) => setAiCount(parseInt(e.target.value) || 5)}
              className={styles.input}
            />
          </div>
          
          <div className={styles.buttonGroup}>
            <button
              onClick={createAIPlayers}
              disabled={loading}
              className={styles.createBtn}
            >
              {loading ? 'Creating...' : 'Create AI Players'}
            </button>
            
            <button
              onClick={removeAIPlayers}
              disabled={loading || aiPlayers.length === 0}
              className={styles.removeBtn}
            >
              {loading ? 'Removing...' : 'Remove All AI Players'}
            </button>
            
            <button
              onClick={fetchAIPlayers}
              disabled={loading}
              className={styles.refreshBtn}
            >
              Refresh
            </button>
          </div>
        </div>
        
        {error && (
          <div className={styles.error}>
            {error}
          </div>
        )}

        {success && (
          <div className={styles.success}>
            {success}
          </div>
        )}

        <div className={styles.section}>
        <h2>Current AI Players ({aiPlayers.length})</h2>
        
        {loading && (
          <div className={styles.loading}>Loading AI players...</div>
        )}

        {!loading && aiPlayers.length === 0 && (
          <div className={styles.empty}>
            No AI players found. Create some to get started!
          </div>
        )}

        {!loading && aiPlayers.length > 0 && (
          <div className={styles.table}>
            <div className={styles.tableHeader}>
              <div className={styles.nameCol}>Name</div>
              <div className={styles.sectorCol}>Sector</div>
              <div className={styles.creditsCol}>Credits</div>
              <div className={styles.levelsCol}>Ship Levels</div>
            </div>
            
            {aiPlayers.map((player) => (
              <div key={player.player_id} className={styles.tableRow}>
                <div className={styles.nameCol}>
                  <span className={styles.aiName}>🤖 {player.player_name}</span>
                </div>
                <div className={styles.sectorCol}>
                  {player.sector_number}
                </div>
                <div className={styles.creditsCol}>
                  {formatCredits(player.credits)}
                </div>
                <div className={styles.levelsCol}>
                  <div className={styles.levelGrid}>
                    <span>Hull: {player.ship_levels.hull}</span>
                    <span>Engine: {player.ship_levels.engine}</span>
                    <span>Power: {player.ship_levels.power}</span>
                    <span>Computer: {player.ship_levels.computer}</span>
                    <span>Sensors: {player.ship_levels.sensors}</span>
                    <span>Beam: {player.ship_levels.beamWeapon}</span>
                    <span>Armor: {player.ship_levels.armor}</span>
                    <span>Cloak: {player.ship_levels.cloak}</span>
                    <span>Torps: {player.ship_levels.torpLauncher}</span>
                    <span>Shield: {player.ship_levels.shield}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
        </div>
      </>
        )}
      </div>
    </div>
  )
}

