'use client'

import { useState, useEffect } from 'react'
import useSWR from 'swr'
import { createClient } from '@supabase/supabase-js'
import styles from './page.module.css'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

interface Universe {
  id: string
  name: string
  created_at: string
  sector_count: number
  port_count: number
  planet_count: number
  player_count: number
}

interface UniverseSettings {
  name: string
  portDensity: number
  planetDensity: number
  sectorCount: number
  aiPlayerCount: number
}

const fetcher = async (url: string) => {
  const { data: { session } } = await supabase.auth.getSession()
  
  if (!session?.access_token) {
    throw new Error('No authentication token')
  }
  
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${session.access_token}`
    }
  })
  
  if (!response.ok) {
    throw new Error('Failed to fetch')
  }
  
  return response.json()
}

export default function AdminPage() {
  const [universes, setUniverses] = useState<Universe[]>([])
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [settings, setSettings] = useState<UniverseSettings>({
    name: 'Alpha',
    portDensity: 0.30,
    planetDensity: 0.25,
    sectorCount: 500,
    aiPlayerCount: 0
  })

  const { data: universesData, error, mutate } = useSWR('/api/admin/universes', fetcher)

  useEffect(() => {
    if (universesData?.universes) {
      setUniverses(universesData.universes)
    }
  }, [universesData])

  const handleCreateUniverse = async () => {
    setLoading(true)
    setStatus('')

    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setStatus('Error: No authentication token')
        return
      }
      
      const response = await fetch('/api/admin/universes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify(settings)
      })

      const result = await response.json()

      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus(`Universe "${result.name}" created successfully!`)
        setShowCreateForm(false)
        mutate() // Refresh the list
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Failed to create universe'}`)
    } finally {
      setLoading(false)
    }
  }

  const handleDestroyUniverse = async (universeId: string, universeName: string) => {
    if (!confirm(`Are you sure you want to destroy universe "${universeName}"? This action cannot be undone!`)) {
      return
    }

    setLoading(true)
    setStatus('')

    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setStatus('Error: No authentication token')
        return
      }
      
      const response = await fetch(`/api/admin/universes/${universeId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      const result = await response.json()

      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus(`Universe "${result.universe_name}" destroyed successfully!`)
        mutate() // Refresh the list
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Failed to destroy universe'}`)
    } finally {
      setLoading(false)
    }
  }

  if (error) {
    return (
      <div className={styles.container}>
        <h1>Admin Panel</h1>
        <div className={styles.error}>Error loading universes: {error.message}</div>
      </div>
    )
  }

  return (
    <div className={styles.container}>
      <h1>Universe Admin Panel</h1>
      
      {status && (
        <div className={styles.status}>{status}</div>
      )}

      <div className={styles.controls}>
        <button 
          className={styles.createButton}
          onClick={() => setShowCreateForm(!showCreateForm)}
          disabled={loading}
        >
          {showCreateForm ? '✕ Cancel' : '✨ Create Universe'}
        </button>
      </div>

      {showCreateForm && (
        <div className={styles.createForm}>
          <h2>Create New Universe</h2>
          
          <div className={styles.formGroup}>
            <label htmlFor="name">Universe Name:</label>
            <input
              id="name"
              type="text"
              value={settings.name}
              onChange={(e) => setSettings({ ...settings, name: e.target.value })}
              placeholder="Alpha"
            />
          </div>

          <div className={styles.formGroup}>
            <label htmlFor="portDensity">Port Density (0-1):</label>
            <input
              id="portDensity"
              type="number"
              min="0"
              max="1"
              step="0.01"
              value={settings.portDensity}
              onChange={(e) => setSettings({ ...settings, portDensity: parseFloat(e.target.value) })}
            />
            <span className={styles.hint}>{(settings.portDensity * 100).toFixed(1)}% of sectors will have ports</span>
          </div>

          <div className={styles.formGroup}>
            <label htmlFor="planetDensity">Planet Density (0-1):</label>
            <input
              id="planetDensity"
              type="number"
              min="0"
              max="1"
              step="0.01"
              value={settings.planetDensity}
              onChange={(e) => setSettings({ ...settings, planetDensity: parseFloat(e.target.value) })}
            />
            <span className={styles.hint}>{(settings.planetDensity * 100).toFixed(1)}% of sectors will have planets</span>
          </div>

          <div className={styles.formGroup}>
            <label htmlFor="sectorCount">Sector Count:</label>
            <input
              id="sectorCount"
              type="number"
              min="1"
              max="1000"
              value={settings.sectorCount}
              onChange={(e) => setSettings({ ...settings, sectorCount: parseInt(e.target.value) })}
            />
            <span className={styles.hint}>Creates sectors 0 through {settings.sectorCount}</span>
          </div>

          <div className={styles.formGroup}>
            <label htmlFor="aiPlayerCount">AI Player Count:</label>
            <input
              id="aiPlayerCount"
              type="number"
              min="0"
              max="100"
              value={settings.aiPlayerCount}
              onChange={(e) => setSettings({ ...settings, aiPlayerCount: parseInt(e.target.value) })}
            />
            <span className={styles.hint}>
              {settings.aiPlayerCount === 0 
                ? 'No AI players will be created' 
                : `Creates ${settings.aiPlayerCount} AI players (${Math.ceil(settings.aiPlayerCount/4)} of each type)`
              }
            </span>
          </div>

          <button 
            className={styles.submitButton}
            onClick={handleCreateUniverse}
            disabled={loading}
          >
            {loading ? '🚀 Creating...' : '🚀 Create Universe'}
          </button>
        </div>
      )}

      <div className={styles.universesList}>
        <h2>Existing Universes</h2>
        
        {universes.length === 0 ? (
          <div className={styles.empty}>No universes found</div>
        ) : (
          <div className={styles.universeGrid}>
            {universes.map((universe) => (
              <div key={universe.id} className={styles.universeCard}>
                <div className={styles.universeHeader}>
                  <h3>{universe.name}</h3>
                  <button
                    className={styles.destroyButton}
                    onClick={() => handleDestroyUniverse(universe.id, universe.name)}
                    disabled={loading}
                  >
                    💥 Destroy
                  </button>
                </div>
                
                <div className={styles.universeStats}>
                  <div className={styles.stat}>
                    <span className={styles.statLabel}>🌌 Sectors:</span>
                    <span className={styles.statValue}>{universe.sector_count.toLocaleString()}</span>
                  </div>
                  <div className={styles.stat}>
                    <span className={styles.statLabel}>🏭 Ports:</span>
                    <span className={styles.statValue}>{universe.port_count.toLocaleString()}</span>
                  </div>
                  <div className={styles.stat}>
                    <span className={styles.statLabel}>🪐 Planets:</span>
                    <span className={styles.statValue}>{universe.planet_count.toLocaleString()}</span>
                  </div>
                  <div className={styles.stat}>
                    <span className={styles.statLabel}>👥 Players:</span>
                    <span className={styles.statValue}>{universe.player_count.toLocaleString()}</span>
                  </div>
                </div>
                
                <div className={styles.universeMeta}>
                  <span className={styles.createdAt}>
                    Created: {new Date(universe.created_at).toLocaleString()}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className={styles.footer}>
        <a href="/game" className={styles.backLink}>← Back to Game</a>
      </div>
    </div>
  )
}
