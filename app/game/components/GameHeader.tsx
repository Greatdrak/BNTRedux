'use client'

import { useState, useEffect, useRef } from 'react'
import styles from '../page.module.css'

interface GameHeaderProps {
  playerName: string;
  currentSector: number;
  turns: number;
  turnsUsed: number;
  credits: number;
  engineLevel: number;
  lastTurnTs?: string;
  turnCap?: number;
  universeName: string;
  universeId: string;
  onUniverseChange: (universeId: string) => void;
  onRefresh: () => void;
  onLogout: () => void;
}

export default function GameHeader({
  playerName,
  currentSector,
  turns,
  turnsUsed,
  credits,
  engineLevel,
  lastTurnTs,
  turnCap,
  universeName,
  universeId,
  onUniverseChange,
  onRefresh,
  onLogout
}: GameHeaderProps) {
  const [showUniverseDropdown, setShowUniverseDropdown] = useState(false)
  const [countdown, setCountdown] = useState<number>(0)
  const [progress, setProgress] = useState<number>(0)

  // Countdown logic based on lastTurnTs
  useEffect(() => {
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
  }, [lastTurnTs, turnCap, turns])

  // Trigger refresh when countdown hits 0
  const prevCountdownRef = useRef<number>(countdown)
  useEffect(() => {
    const prev = prevCountdownRef.current
    prevCountdownRef.current = countdown
    if (prev > 0 && countdown === 0 && turns !== undefined && turnCap !== undefined && turns < turnCap) {
      onRefresh()
    }
  }, [countdown, turns, turnCap, onRefresh])

  const formatCountdown = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`
  }

  return (
    <div className={styles.headerContent}>
      {/* Game Title and Player */}
      <div className={styles.headerLeft}>
        <h1 className={styles.gameTitle}>Quantum Nova Traders</h1>
        <p className={styles.playerName}>{playerName}</p>
      </div>

      {/* Game Stats */}
      <div className={styles.headerStats}>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>SECTOR</span>
          <span className={styles.statValue}>{currentSector}</span>
        </div>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>TURNS</span>
          <span className={styles.statValue}>{turns}</span>
        </div>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>USED</span>
          <span className={styles.statValue}>{turnsUsed}</span>
        </div>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>CREDITS</span>
          <span className={styles.statValue}>{credits.toLocaleString()}</span>
        </div>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>ENG</span>
          <span className={styles.statValue}>{engineLevel}</span>
        </div>
        <div className={styles.statItem}>
          <span className={styles.statLabel}>NEXT TURN</span>
          <span className={styles.statValue}>{formatCountdown(countdown)}</span>
        </div>
      </div>

      {/* Controls */}
      <div className={styles.headerControls}>
        <div className={styles.universeSelector}>
          <button 
            className={styles.universeButton}
            onClick={() => setShowUniverseDropdown(!showUniverseDropdown)}
          >
            {universeName} ({playerName}) ▼
          </button>
          {showUniverseDropdown && (
            <div className={styles.universeDropdown}>
              <button 
                onClick={() => {
                  onUniverseChange(universeId)
                  setShowUniverseDropdown(false)
                }}
              >
                {universeName} ({playerName})
              </button>
            </div>
          )}
        </div>
        <button className={styles.refreshButton} onClick={onRefresh}>
          Refresh
        </button>
        <button className={styles.logoutButton} onClick={onLogout}>
          Logout
        </button>
      </div>
    </div>
  )
}
