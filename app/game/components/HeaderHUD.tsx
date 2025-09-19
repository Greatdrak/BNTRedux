'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import useSWR from 'swr'
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

  // Scheduler-driven countdown (source of truth)
  interface SchedulerStatus {
    universe_id: string
    next_turn_generation: string | null
    time_until_turn_generation_seconds: number
  }

  const schedulerFetcher = async (url: string) => {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session?.access_token) throw new Error('No authentication token')
    const res = await fetch(url, { headers: { 'Authorization': `Bearer ${session.access_token}` } })
    if (!res.ok) throw new Error('Failed to fetch scheduler status')
    return res.json()
  }

  const schedulerKey = useMemo(() => (
    currentUniverseId ? `/api/scheduler/status?universe_id=${currentUniverseId}` : null
  ), [currentUniverseId])

  const { data: schedulerStatus, mutate: mutateScheduler } = useSWR<SchedulerStatus>(
    schedulerKey,
    schedulerFetcher,
    { refreshInterval: 60000, revalidateOnFocus: false, dedupingInterval: 20000 }
  )

  // Keep a rolling, second-by-second countdown that resyncs to server on updates
  const serverRemainingRef = useRef<number | null>(null)
  const windowSecondsRef = useRef<number>(180) // fallback to 3 minutes if we cannot infer

  // When server value changes, reset local countdown and window size heuristic
  useEffect(() => {
    if (schedulerStatus?.time_until_turn_generation_seconds !== undefined) {
      const remaining = Math.max(0, Math.floor(schedulerStatus.time_until_turn_generation_seconds))
      serverRemainingRef.current = remaining
      // Heuristic window: if remaining appears within a sensible window, use it as window size; else keep default
      if (remaining > 0) {
        // Clamp window between 60s and 900s to avoid absurd values
        windowSecondsRef.current = Math.min(900, Math.max(60, remaining))
      }
      setCountdown(remaining)
      setProgress(((windowSecondsRef.current - remaining) / windowSecondsRef.current) * 100)
    }
  }, [schedulerStatus?.time_until_turn_generation_seconds])

  // Local ticking countdown that decrements every second, but will be corrected by server refresh
  useEffect(() => {
    const interval = setInterval(() => {
      setCountdown(prev => {
        const next = Math.max(0, (prev ?? 0) - 1)
        // Update progress accordingly
        const windowS = windowSecondsRef.current || 180
        setProgress(((windowS - next) / windowS) * 100)
        return next
      })
    }, 1000)
    return () => clearInterval(interval)
  }, [])

  // Fallback: if scheduler unavailable, keep legacy per-minute timer based on lastTurnTs
  useEffect(() => {
    if (schedulerStatus) return // prefer scheduler when available
    if (!lastTurnTs || !turnCap || turns === undefined) return

    const updateCountdown = () => {
      const lastTurn = new Date(lastTurnTs).getTime()
      const now = Date.now()
      const timeSinceLastTurn = now - lastTurn
      const timeUntilNextTurn = 60000 - (timeSinceLastTurn % 60000)
      const seconds = Math.max(0, Math.ceil(timeUntilNextTurn / 1000))
      setCountdown(seconds)
      setProgress((60000 - timeUntilNextTurn) / 60000 * 100)
    }

    updateCountdown()
    const interval = setInterval(updateCountdown, 1000)
    return () => clearInterval(interval)
  }, [schedulerStatus, lastTurnTs, turnCap, turns])

  // Trigger refresh only on transition to 0 to avoid repeated calls
  const prevCountdownRef = useRef<number>(countdown)
  useEffect(() => {
    const prev = prevCountdownRef.current
    prevCountdownRef.current = countdown
    if (prev > 0 && countdown === 0 && turns !== undefined && turnCap !== undefined && turns < turnCap) {
      try { mutateScheduler(); } catch {}
      onRefresh()
    }
  }, [countdown, turns, turnCap, onRefresh, mutateScheduler])

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
        <h1>Quantum Nova Traders</h1>
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
        {turnCap !== undefined && turns !== undefined && (
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
