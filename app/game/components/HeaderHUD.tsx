'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase-client'
import styles from './HeaderHUD.module.css'

interface Universe {
  id: string
  name: string
}

interface Player {
  id: string
  handle: string
  universe_id: string
  universe_name: string
}

interface HeaderHUDProps {
  handle?: string
  turns?: number
  turnCap?: number
  lastTurnTs?: string
  credits?: number
  currentSector?: number
  engineLvl?: number
  onRefresh: () => void
  loading?: boolean
  currentUniverseId?: string
}

export default function HeaderHUD({ 
  handle, 
  turns, 
  turnCap,
  lastTurnTs,
  credits, 
  currentSector, 
  engineLvl,
  onRefresh, 
  loading,
  currentUniverseId
}: HeaderHUDProps) {
  const [countdown, setCountdown] = useState<number>(0)
  const [progress, setProgress] = useState<number>(0)
  const [players, setPlayers] = useState<Player[]>([])
  const [loadingPlayers, setLoadingPlayers] = useState(false)
  const router = useRouter()

  useEffect(() => {
    if (!lastTurnTs || !turnCap || turns === undefined) return

    const updateCountdown = () => {
      const lastTurn = new Date(lastTurnTs).getTime()
      const now = Date.now()
      const timeSinceLastTurn = now - lastTurn
      const timeUntilNextTurn = 60000 - (timeSinceLastTurn % 60000) // 60 seconds = 1 turn
      
      setCountdown(Math.max(0, Math.ceil(timeUntilNextTurn / 1000)))
      setProgress((60000 - timeUntilNextTurn) / 60000 * 100)
    }

    updateCountdown()
    const interval = setInterval(updateCountdown, 1000)

    return () => clearInterval(interval)
  }, [lastTurnTs, turnCap, turns])

  useEffect(() => {
    if (countdown === 0 && turns !== undefined && turnCap !== undefined && turns < turnCap) {
      // Trigger silent refresh when countdown reaches 0
      setTimeout(() => {
        onRefresh()
      }, 1000)
    }
  }, [countdown, turns, turnCap, onRefresh])

  // Fetch players for universe switching
  useEffect(() => {
    const fetchPlayers = async () => {
      try {
        setLoadingPlayers(true)
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
      } catch (err) {
        console.error('Error fetching players:', err)
      } finally {
        setLoadingPlayers(false)
      }
    }

    fetchPlayers()
  }, [])

  const handleUniverseSwitch = (player: Player) => {
    // Navigate to the new universe
    router.push(`/game?universe_id=${player.universe_id}`)
  }

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/')
  }

  const formatCredits = (amount: number) => {
    return new Intl.NumberFormat('en-US').format(amount)
  }

  const formatCountdown = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`
  }

  return (
    <header className={styles.header}>
      <div className={styles.title}>
        <h1>BNT Redux</h1>
        <span className={styles.handle}>{handle || 'Loading...'}</span>
      </div>
      
      <div className={styles.metrics}>
        <div className={styles.metric}>
          <span className={styles.label}>Sector</span>
          <span className={styles.value}>{currentSector ?? '--'}</span>
        </div>
        <div className={styles.metric}>
          <span className={styles.label}>Turns</span>
          <span className={styles.value}>{turns || '--'}</span>
        </div>
        <div className={styles.metric}>
          <span className={styles.label}>Credits</span>
          <span className={styles.value}>{credits ? formatCredits(credits) : '--'}</span>
        </div>
        <div className={styles.metric}>
          <span className={styles.label}>ENG</span>
          <span className={styles.value}>{engineLvl ?? '--'}</span>
        </div>
        {turnCap !== undefined && turns !== undefined && turns < turnCap && (
          <div className={styles.metric}>
            <span className={styles.label}>Next Turn</span>
            <div className={styles.countdownContainer}>
              <span className={styles.value}>{formatCountdown(countdown)}</span>
              <div className={styles.progressBar}>
                <div 
                  className={styles.progressFill} 
                  style={{ width: `${progress}%` }}
                />
              </div>
            </div>
          </div>
        )}
      </div>
      
      <div className={styles.controls}>
        <div className={styles.universeSwitcher}>
          <select
            value={currentUniverseId || ''}
            onChange={(e) => {
              const selectedPlayer = players.find(p => p.universe_id === e.target.value)
              if (selectedPlayer) {
                handleUniverseSwitch(selectedPlayer)
              }
            }}
            className={styles.universeSelect}
            disabled={loadingPlayers}
          >
            <option value="">Switch Universe</option>
            {players.map((player) => (
              <option key={player.id} value={player.universe_id}>
                {player.universe_name} ({player.handle})
              </option>
            ))}
          </select>
        </div>
        
        <button 
          onClick={onRefresh} 
          className={styles.refreshBtn}
          disabled={loading}
        >
          {loading ? 'Refreshing...' : 'Refresh'}
        </button>
        
        <button 
          onClick={handleLogout} 
          className={styles.logoutBtn}
        >
          Logout
        </button>
      </div>
    </header>
  )
}
