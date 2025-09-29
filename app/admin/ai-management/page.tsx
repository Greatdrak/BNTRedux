'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@supabase/supabase-js'
import styles from './page.module.css'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

interface AIPlayer {
  player_id: string
  player_name: string
  ship_id: string
  sector_number: number
  credits: number
  ai_personality: string
  ship_levels: {
    hull: number
    engine: number
    power: number
    computer: number
    sensors: number
    beam_weapon: number
    armor: number
    cloak: number
    torp_launcher: number
    shield: number
  }
  last_action?: string
  current_goal?: string
  owned_planets?: number
}

interface AIMemory {
  player_id: string
  player_name: string
  last_action: string
  current_goal: string
  target_sector_id: string
  owned_planets: number
  last_profit: number
  consecutive_losses: number
}

interface AIStats {
  total_ai_players: number
  active_ai_players: number
  total_actions_today: number
  personality_distribution: Record<string, number>
  average_credits: number
  total_ai_planets: number
}

export default function AIManagementPage() {
  const router = useRouter()
  const [aiPlayers, setAiPlayers] = useState<AIPlayer[]>([])
  const [aiMemories, setAiMemories] = useState<AIMemory[]>([])
  const [aiStats, setAiStats] = useState<AIStats | null>(null)
  const [selectedUniverse, setSelectedUniverse] = useState<string>('')
  const [universes, setUniverses] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchUniverses()
  }, [])

  useEffect(() => {
    if (selectedUniverse) {
      fetchAIData()
    }
  }, [selectedUniverse])

  const fetchUniverses = async () => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setError('No authentication token')
        return
      }
      
      const response = await fetch('/api/admin/universes', {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })
      
      if (response.ok) {
        const data = await response.json()
        setUniverses(data.universes || data)
        if ((data.universes || data).length > 0) {
          setSelectedUniverse((data.universes || data)[0].id)
        }
      } else {
        setError('Failed to fetch universes')
      }
    } catch (err) {
      setError('Failed to fetch universes')
    }
  }

  const fetchAIData = async () => {
    setLoading(true)
    setError(null)
    
    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setError('No authentication token')
        return
      }
      
      const headers = {
        'Authorization': `Bearer ${session.access_token}`
      }
      
      // Fetch AI players
      const playersResponse = await fetch(`/api/admin/ai-players?universe_id=${selectedUniverse}`, { headers })
      if (playersResponse.ok) {
        const playersData = await playersResponse.json()
        setAiPlayers(playersData.aiPlayers || playersData)
      }

      // Fetch AI memories and stats
      const memoryResponse = await fetch(`/api/admin/ai-memory?universe_id=${selectedUniverse}`, { headers })
      if (memoryResponse.ok) {
        const memoryData = await memoryResponse.json()
        setAiMemories(memoryData.memories || [])
        setAiStats(memoryData.stats || null)
      }

    } catch (err) {
      setError('Failed to fetch AI data')
    } finally {
      setLoading(false)
    }
  }

  const triggerAIActions = async () => {
    setLoading(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setError('No authentication token')
        return
      }
      
      const response = await fetch('/api/admin/trigger-ai-actions', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ universe_id: selectedUniverse })
      })
      
      if (response.ok) {
        await fetchAIData() // Refresh data
      } else {
        setError('Failed to trigger AI actions')
      }
    } catch (err) {
      setError('Failed to trigger AI actions')
    } finally {
      setLoading(false)
    }
  }

  const resetAIPlayer = async (playerId: string) => {
    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setError('No authentication token')
        return
      }
      
      const response = await fetch('/api/admin/reset-ai-player', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ player_id: playerId })
      })
      
      if (response.ok) {
        await fetchAIData() // Refresh data
      } else {
        setError('Failed to reset AI player')
      }
    } catch (err) {
      setError('Failed to reset AI player')
    }
  }

  const createAIPlayers = async () => {
    if (!selectedUniverse) return

    setLoading(true)
    setError(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session?.access_token) {
        setError('No authentication token')
        return
      }

      const response = await fetch('/api/admin/ai-players', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ 
          universeId: selectedUniverse, 
          count: 5 
        })
      })

      const result = await response.json()

      if (response.ok) {
        await fetchAIData() // Refresh data
      } else {
        setError(result.error || 'Failed to create AI players')
      }
    } catch (err) {
      setError('Failed to create AI players')
    } finally {
      setLoading(false)
    }
  }


  const getPersonalityColor = (personality: string) => {
    const colors = {
      trader: '#4CAF50',
      explorer: '#2196F3', 
      warrior: '#F44336',
      colonizer: '#FF9800',
      balanced: '#9C27B0'
    }
    return colors[personality as keyof typeof colors] || '#666'
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <h1>🤖 AI Management Dashboard</h1>
          <button onClick={() => router.push('/admin')} className={styles.backBtn}>
            Back to Admin
          </button>
        </div>
        <div className={styles.controls}>
          <select 
            value={selectedUniverse} 
            onChange={(e) => setSelectedUniverse(e.target.value)}
            className={styles.universeSelect}
          >
            {universes.map(u => (
              <option key={u.id} value={u.id}>{u.name}</option>
            ))}
          </select>
          <button 
            onClick={createAIPlayers} 
            disabled={loading}
            className={styles.createButton}
          >
            {loading ? 'Creating...' : '🤖 Create AI Players'}
          </button>
          <button 
            onClick={triggerAIActions} 
            disabled={loading}
            className={styles.triggerButton}
          >
            {loading ? 'Processing...' : '⚡ Trigger AI Actions'}
          </button>
          <button 
            onClick={fetchAIData} 
            disabled={loading}
            className={styles.refreshButton}
          >
            🔄 Refresh
          </button>
        </div>
      </div>

      {error && <div className={styles.error}>{error}</div>}

      {/* Enhanced AI Status */}
      {selectedUniverse && (
        <div className={styles.enhancedAiToggle}>
          <div className={styles.toggleContainer}>
            <span className={styles.toggleLabel}>
              Enhanced AI System: 
              <span className={styles.enabled}>
                🟢 ALWAYS ENABLED
              </span>
            </span>
          </div>
          <div className={styles.toggleDescription}>
            <strong>Enhanced AI System Features:</strong><br/>
            • <strong>Personality Types:</strong> Trader, Explorer, Warrior, Colonizer, Balanced<br/>
            • <strong>Strategic Trading:</strong> AI analyzes port prices and cargo capacity to maximize profits<br/>
            • <strong>Intelligent Exploration:</strong> AI targets sectors with ports, planets, and other players<br/>
            • <strong>Planet Management:</strong> AI claims unclaimed planets and manages production<br/>
            • <strong>Ship Upgrades:</strong> AI upgrades hull, engines, weapons, and systems based on strategy<br/>
            • <strong>Combat Tactics:</strong> AI buys fighters/torpedoes and engages in strategic combat<br/>
            • <strong>Memory System:</strong> AI remembers previous actions and adapts behavior<br/>
            • <strong>Turn Tracking:</strong> AI actions increment turns_spent for leaderboard visibility<br/>
            • <strong>Territory Control:</strong> AI patrols owned sectors and defends territory
          </div>
        </div>
      )}

      {aiStats && (
        <div className={styles.statsGrid}>
          <div className={styles.statCard}>
            <h3>Total AI Players</h3>
            <div className={styles.statValue}>{aiStats.total_ai_players}</div>
          </div>
          <div className={styles.statCard}>
            <h3>Active Today</h3>
            <div className={styles.statValue}>{aiStats.active_ai_players}</div>
          </div>
          <div className={styles.statCard}>
            <h3>Actions Today</h3>
            <div className={styles.statValue}>{aiStats.total_actions_today}</div>
          </div>
          <div className={styles.statCard}>
            <h3>Average Credits</h3>
            <div className={styles.statValue}>{aiStats.average_credits?.toLocaleString()}</div>
          </div>
          <div className={styles.statCard}>
            <h3>AI Owned Planets</h3>
            <div className={styles.statValue}>{aiStats.total_ai_planets}</div>
          </div>
        </div>
      )}

      <div className={styles.personalityDistribution}>
        <h3>Personality Distribution</h3>
        <div className={styles.personalityBars}>
          {aiStats?.personality_distribution && Object.entries(aiStats.personality_distribution).map(([personality, count]) => (
            <div key={personality} className={styles.personalityBar}>
              <span className={styles.personalityLabel} style={{ color: getPersonalityColor(personality) }}>
                {personality.charAt(0).toUpperCase() + personality.slice(1)}
              </span>
              <div className={styles.barContainer}>
                <div 
                  className={styles.bar}
                  style={{ 
                    width: `${(count / aiStats.total_ai_players) * 100}%`,
                    backgroundColor: getPersonalityColor(personality)
                  }}
                />
              </div>
              <span className={styles.count}>{count}</span>
            </div>
          ))}
        </div>
      </div>

      <div className={styles.tabsContainer}>
        <div className={styles.tabs}>
          <button className={styles.tabActive}>AI Players</button>
          <button className={styles.tab}>AI Memory</button>
        </div>

        <div className={styles.playersGrid}>
          {aiPlayers.map(player => {
            const memory = aiMemories.find(m => m.player_id === player.player_id)
            return (
              <div key={player.player_id} className={styles.playerCard}>
                <div className={styles.playerHeader}>
                  <h4>{player.player_name}</h4>
                  <span 
                    className={styles.personality}
                    style={{ backgroundColor: getPersonalityColor(player.ai_personality) }}
                  >
                    {player.ai_personality}
                  </span>
                </div>
                
                <div className={styles.playerStats}>
                  <div className={styles.statRow}>
                    <span>Sector:</span>
                    <span>{player.sector_number}</span>
                  </div>
                  <div className={styles.statRow}>
                    <span>Credits:</span>
                    <span>{player.credits?.toLocaleString()}</span>
                  </div>
                  <div className={styles.statRow}>
                    <span>Planets:</span>
                    <span>{memory?.owned_planets || 0}</span>
                  </div>
                  <div className={styles.statRow}>
                    <span>Goal:</span>
                    <span>{memory?.current_goal || 'explore'}</span>
                  </div>
                  <div className={styles.statRow}>
                    <span>Last Action:</span>
                    <span>{memory?.last_action ? new Date(memory.last_action).toLocaleTimeString() : 'Never'}</span>
                  </div>
                </div>

                <div className={styles.shipLevels}>
                  <h5>Ship Levels</h5>
                  <div className={styles.levelsGrid}>
                    <span>Hull: {player.ship_levels.hull}</span>
                    <span>Engine: {player.ship_levels.engine}</span>
                    <span>Weapons: {player.ship_levels.beam_weapon}</span>
                    <span>Armor: {player.ship_levels.armor}</span>
                  </div>
                </div>

                <div className={styles.playerActions}>
                  <button 
                    onClick={() => resetAIPlayer(player.player_id)}
                    className={styles.resetButton}
                  >
                    Reset AI
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
