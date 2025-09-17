'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase-client'
import styles from './page.module.css'

interface Universe {
  id: string
  name: string
  created_at: string
  sector_count: number
  port_count: number
  planet_count: number
  player_count: number
}

interface Player {
  id: string
  handle: string
  universe_id: string
  universe_name: string
}

export default function Home() {
  const [universes, setUniverses] = useState<Universe[]>([])
  const [players, setPlayers] = useState<Player[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [showCreatePlayer, setShowCreatePlayer] = useState(false)
  const [selectedUniverse, setSelectedUniverse] = useState('')
  const [newPlayerHandle, setNewPlayerHandle] = useState('')
  const [creatingPlayer, setCreatingPlayer] = useState(false)
  const router = useRouter()

  useEffect(() => {
    checkAuthAndFetchData()
  }, [])

  const checkAuthAndFetchData = async () => {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) {
      router.push('/login')
      return
    }
    
    await fetchUniverses()
    await fetchPlayers()
  }

  const fetchUniverses = async () => {
    try {
      const response = await fetch('/api/universes')
      if (!response.ok) throw new Error('Failed to fetch universes')
      const data = await response.json()
      setUniverses(data.universes || [])
    } catch (err) {
      setError('Failed to load universes')
      console.error('Error fetching universes:', err)
    }
  }

  const fetchPlayers = async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch('/api/players', {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })
      
      if (!response.ok) throw new Error('Failed to fetch players')
      const data = await response.json()
      setPlayers(data.players || [])
    } catch (err: any) {
      console.error('Error fetching players:', err)
    } finally {
      setLoading(false)
    }
  }

  const handlePlayerSelect = (player: Player) => {
    router.push(`/game?universe_id=${player.universe_id}`)
  }

  const handleCreatePlayer = async () => {
    if (!selectedUniverse || !newPlayerHandle.trim()) return

    setCreatingPlayer(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')

      const response = await fetch('/api/register', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          universe_id: selectedUniverse,
          handle: newPlayerHandle.trim()
        })
      })

      const result = await response.json()
      if (result.error) {
        setError(result.error.message)
      } else {
        // Refresh players list and hide create form
        await fetchPlayers()
        setShowCreatePlayer(false)
        setNewPlayerHandle('')
        setSelectedUniverse('')
      }
    } catch (err: any) {
      setError(err.message || 'Failed to create player')
    } finally {
      setCreatingPlayer(false)
    }
  }

  return (
    <div className={styles.container}>
      <div className={styles.hero}>
        <h1 className={styles.title}>BNT Redux</h1>
        <p className={styles.subtitle}>Space Trading Game</p>
        <p className={styles.description}>
          Explore the cosmos, trade resources, build your empire, and conquer the stars.
          Choose your universe and begin your journey among the stars.
        </p>
      </div>

      <div className={styles.universeSection}>
        <h2 className={styles.sectionTitle}>Choose Your Universe</h2>
        
        {loading && (
          <div className={styles.loading}>Loading universes...</div>
        )}
        
        {error && (
          <div className={styles.error}>{error}</div>
        )}
        
        {!loading && !error && universes.length === 0 && (
          <div className={styles.empty}>
            <p>No universes available.</p>
            <p>Contact an administrator to create a universe.</p>
          </div>
        )}
        
        {!loading && !error && universes.length > 0 && (
          <div className={styles.universeGrid}>
            {universes.map((universe) => {
              const playerInUniverse = players.find(p => p.universe_id === universe.id)
              
              return (
                <div key={universe.id} className={styles.universeCard}>
                  <div className={styles.universeHeader}>
                    <h3 className={styles.universeName}>{universe.name}</h3>
                    <div className={styles.universeStatus}>
                      {universe.player_count > 0 ? 'Active' : 'New'}
                    </div>
                  </div>
                  
                  <div className={styles.universeStats}>
                    <div className={styles.stat}>
                      <span className={styles.statIcon}>🌌</span>
                      <span className={styles.statValue}>{universe.sector_count.toLocaleString()}</span>
                      <span className={styles.statLabel}>Sectors</span>
                    </div>
                    <div className={styles.stat}>
                      <span className={styles.statIcon}>🏭</span>
                      <span className={styles.statValue}>{universe.port_count.toLocaleString()}</span>
                      <span className={styles.statLabel}>Ports</span>
                    </div>
                    <div className={styles.stat}>
                      <span className={styles.statIcon}>🪐</span>
                      <span className={styles.statValue}>{universe.planet_count.toLocaleString()}</span>
                      <span className={styles.statLabel}>Planets</span>
                    </div>
                    <div className={styles.stat}>
                      <span className={styles.statIcon}>👥</span>
                      <span className={styles.statValue}>{universe.player_count.toLocaleString()}</span>
                      <span className={styles.statLabel}>Players</span>
                    </div>
                  </div>
                  
                  <div className={styles.universeMeta}>
                    <span className={styles.createdAt}>
                      Created {new Date(universe.created_at).toLocaleDateString()}
                    </span>
                  </div>

                  {/* Character Section */}
                  <div className={styles.characterSection}>
                    {playerInUniverse ? (
                      <div className={styles.existingCharacter}>
                        <div className={styles.characterInfo}>
                          <h4 className={styles.characterName}>{playerInUniverse.handle}</h4>
                          <p className={styles.characterStatus}>Your character in this universe</p>
                        </div>
                        <button
                          className={styles.playButton}
                          onClick={() => handlePlayerSelect(playerInUniverse)}
                        >
                          🚀 Play Character
                        </button>
                      </div>
                    ) : (
                      <div className={styles.createCharacterSection}>
                        {showCreatePlayer && selectedUniverse === universe.id ? (
                          <div className={styles.createForm}>
                            <h4>Create Character in {universe.name}</h4>
                            <div className={styles.formRow}>
                              <input
                                type="text"
                                placeholder="Character name (3-20 characters)"
                                value={newPlayerHandle}
                                onChange={(e) => setNewPlayerHandle(e.target.value)}
                                className={styles.input}
                                required
                                minLength={3}
                                maxLength={20}
                                pattern="[a-zA-Z0-9_-]+"
                              />
                              <button 
                                className={styles.submitButton}
                                onClick={handleCreatePlayer}
                                disabled={creatingPlayer || !newPlayerHandle.trim()}
                              >
                                {creatingPlayer ? 'Creating...' : 'Create Character'}
                              </button>
                              <button 
                                className={styles.cancelButton}
                                onClick={() => {
                                  setShowCreatePlayer(false)
                                  setSelectedUniverse('')
                                  setNewPlayerHandle('')
                                }}
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : (
                          <button
                            className={styles.createButton}
                            onClick={() => {
                              setShowCreatePlayer(true)
                              setSelectedUniverse(universe.id)
                              setNewPlayerHandle('')
                            }}
                          >
                            + Create Character
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}