'use client'

import { useState, useEffect, useRef } from 'react'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './TurnCounter.module.css'

interface SchedulerStatus {
  universe_id: string
  next_turn_generation: string
  next_cycle_event: string
  next_update_event: string
  time_until_turn_generation_seconds: number
  time_until_cycle_seconds: number
  time_until_update_seconds: number
  status: {
    turn_generation: 'ready' | 'waiting'
    cycle_event: 'ready' | 'waiting'
    update_event: 'ready' | 'waiting'
  }
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
    throw new Error('Failed to fetch scheduler status')
  }
  return response.json()
}

export default function TurnCounter({ universeId }: { universeId?: string }) {
  const [currentTime, setCurrentTime] = useState(Date.now())
  // Keep a stable ref for rollover detection; must be declared before any conditional returns
  const prevCountsRef = useRef({ t: 0, u: 0, c: 0 })
  
  const { data: schedulerStatus, error, mutate } = useSWR<SchedulerStatus>(
    universeId ? `/api/scheduler/status?universe_id=${universeId}` : null,
    fetcher,
    { refreshInterval: 60000, revalidateOnFocus: false, dedupingInterval: 20000 }
  )

  // Update current time every second for countdown
  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentTime(Date.now())
    }, 1000)
    
    return () => clearInterval(interval)
  }, [])

  const formatTime = (seconds: number) => {
    if (seconds <= 0) return '0:00'
    
    const minutes = Math.floor(seconds / 60)
    const remainingSeconds = seconds % 60
    
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
  }

  // Calculate real-time countdowns based on server timestamps
  const calculateCountdown = (nextEvent: string | null, intervalMinutes: number, lastEvent: string | null) => {
    if (!nextEvent && !lastEvent) return 0
    
    const now = currentTime
    let nextTime: number
    
    if (nextEvent) {
      nextTime = new Date(nextEvent).getTime()
    } else if (lastEvent) {
      // Calculate next event time from last event + interval
      nextTime = new Date(lastEvent).getTime() + (intervalMinutes * 60 * 1000)
    } else {
      return 0
    }
    
    // If the next event time has passed, calculate the next occurrence
    if (nextTime <= now) {
      // Find the next occurrence by adding intervals until we're in the future
      while (nextTime <= now) {
        nextTime += (intervalMinutes * 60 * 1000)
      }
    }
    
    const diffSeconds = Math.max(0, Math.floor((nextTime - now) / 1000))
    return diffSeconds
  }

  const getStatusColor = (status: 'ready' | 'waiting') => {
    return status === 'ready' ? '#42f5b9' : '#cfc3ff'
  }

  const getStatusIcon = (status: 'ready' | 'waiting') => {
    return status === 'ready' ? '⚡' : '⏱️'
  }

  const isError = Boolean(error)
  const isLoading = !schedulerStatus

  // Check if cron job is actually running by seeing if timestamps are recent
  const now = Date.now()
  const lastTurnGen = schedulerStatus?.next_turn_generation ? new Date(schedulerStatus.next_turn_generation).getTime() : 0
  const lastUpdate = schedulerStatus?.next_update_event ? new Date(schedulerStatus.next_update_event).getTime() : 0
  
  // If the last events are more than 10 minutes old, consider cron offline
  const cronOffline = (now - lastTurnGen > 10 * 60 * 1000) && (now - lastUpdate > 20 * 60 * 1000)
  
  const showCronOffline = !isLoading && !isError && cronOffline

  // Calculate real-time countdowns
  const turnCountdown = schedulerStatus ? calculateCountdown(schedulerStatus.next_turn_generation, 3, null) : 0
  const cycleCountdown = schedulerStatus ? calculateCountdown(schedulerStatus.next_cycle_event, 360, null) : 0
  const updateCountdown = schedulerStatus ? calculateCountdown(schedulerStatus.next_update_event, 15, null) : 0

  // When any countdown transitions to zero, request a fresh status to roll to next window (once per rollover)
  useEffect(() => {
    const prev = prevCountsRef.current
    const hitZero = (
      (prev.t > 0 && turnCountdown === 0) ||
      (prev.u > 0 && updateCountdown === 0) ||
      (prev.c > 0 && cycleCountdown === 0)
    )
    prevCountsRef.current = { t: turnCountdown, u: updateCountdown, c: cycleCountdown }
    if (hitZero) {
      try { mutate(); } catch {}
    }
  }, [turnCountdown, updateCountdown, cycleCountdown, mutate])

  return (
    <div className={styles.container}>
      {isError && (
        <div className={styles.error}>Scheduler offline</div>
      )}
      {isLoading && !isError && (
        <div className={styles.loading}>Loading scheduler...</div>
      )}
      {showCronOffline && (
        <div className={styles.error}>Cron job offline - events not updating</div>
      )}
      {!isLoading && !isError && !showCronOffline && (
        <>
      <div className={styles.header}>
        <h4>Game Scheduler</h4>
      </div>
      
      <div className={styles.events}>
        <div className={styles.event}>
          <div className={styles.eventHeader}>
            <span className={styles.eventIcon}>🎯</span>
            <span className={styles.eventName}>Turn Generation</span>
            <span 
              className={styles.eventStatus}
              style={{ color: getStatusColor(turnCountdown === 0 ? 'ready' : 'waiting') }}
            >
              {getStatusIcon(turnCountdown === 0 ? 'ready' : 'waiting')}
            </span>
          </div>
          <div className={styles.eventTimer}>
            {formatTime(turnCountdown)}
          </div>
        </div>

        <div className={styles.event}>
          <div className={styles.eventHeader}>
            <span className={styles.eventIcon}>🔄</span>
            <span className={styles.eventName}>Cycle Events</span>
            <span 
              className={styles.eventStatus}
              style={{ color: getStatusColor(cycleCountdown === 0 ? 'ready' : 'waiting') }}
            >
              {getStatusIcon(cycleCountdown === 0 ? 'ready' : 'waiting')}
            </span>
          </div>
          <div className={styles.eventTimer}>
            {formatTime(cycleCountdown)}
          </div>
        </div>

        <div className={styles.event}>
          <div className={styles.eventHeader}>
            <span className={styles.eventIcon}>⚙️</span>
            <span className={styles.eventName}>Updates</span>
            <span 
              className={styles.eventStatus}
              style={{ color: getStatusColor(updateCountdown === 0 ? 'ready' : 'waiting') }}
            >
              {getStatusIcon(updateCountdown === 0 ? 'ready' : 'waiting')}
            </span>
          </div>
          <div className={styles.eventTimer}>
            {formatTime(updateCountdown)}
          </div>
        </div>
      </div>

      <div className={styles.footer}>
        <small>Next turn generation in {formatTime(turnCountdown)}</small>
      </div>
        </>
      )}
    </div>
  )
}
