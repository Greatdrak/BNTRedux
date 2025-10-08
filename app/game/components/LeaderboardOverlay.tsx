'use client'

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase-client'
import styles from './LeaderboardOverlay.module.css'

interface LeaderboardEntry {
  rank: number
  player_id: string
  player_name: string
  handle: string
  score: number
  turns_spent: number
  last_login: string | null
  is_online: boolean
  is_ai: boolean
}


interface LeaderboardOverlayProps {
  open: boolean
  onClose: () => void
  universeId: string
}

export default function LeaderboardOverlay({ open, onClose, universeId }: LeaderboardOverlayProps) {
  const [humanPlayers, setHumanPlayers] = useState<LeaderboardEntry[]>([])
  const [aiPlayers, setAiPlayers] = useState<LeaderboardEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open && universeId) {
      fetchLeaderboard()
    }
  }, [open, universeId])

  const fetchLeaderboard = async () => {
    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/rankings?universe_id=${universeId}&limit=50`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch leaderboard')
      }

          const data = await response.json()
          console.log('Leaderboard API response:', data)
          setHumanPlayers(data.humanPlayers || [])
          setAiPlayers(data.aiPlayers || [])
    } catch (err) {
      console.error('Error fetching leaderboard:', err)
      setError(err instanceof Error ? err.message : 'Failed to load leaderboard')
    } finally {
      setLoading(false)
    }
  }

  const calculateRankings = async () => {
    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch('/api/rankings', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ universe_id: universeId })
      })

      if (!response.ok) {
        throw new Error('Failed to calculate rankings')
      }

      const data = await response.json()
      console.log('Ranking calculation response:', data)
      
      if (data.success || data.ok) {
        // Refresh the leaderboard after calculation
        await fetchLeaderboard()
      } else {
        throw new Error(data.error?.message || 'Failed to calculate rankings')
      }
    } catch (err) {
      console.error('Error calculating rankings:', err)
      setError(err instanceof Error ? err.message : 'Failed to calculate rankings')
    } finally {
      setLoading(false)
    }
  }

  const formatCredits = (credits: number) => {
    return new Intl.NumberFormat('en-US').format(credits)
  }

  const formatLastLogin = (lastLogin: string) => {
    const date = new Date(lastLogin)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
    const diffDays = Math.floor(diffHours / 24)

    if (diffHours < 1) {
      return 'Just now'
    } else if (diffHours < 24) {
      return `${diffHours}h ago`
    } else if (diffDays < 7) {
      return `${diffDays}d ago`
    } else {
      return date.toLocaleDateString()
    }
  }

  const getRankIcon = (rank: number) => {
    if (rank === 1) return '🥇'
    if (rank === 2) return '🥈'
    if (rank === 3) return '🥉'
    return `#${rank}`
  }

  const renderPlayerList = (players: LeaderboardEntry[], title: string, isAi: boolean) => {
    if (players.length === 0) {
      return (
        <div className={styles.section}>
          <h3 className={styles.sectionTitle}>
            {title} {isAi && '🤖'}
          </h3>
          <div className={styles.emptyMessage}>
            {isAi ? 'No AI players yet' : 'No human players yet'}
          </div>
        </div>
      )
    }

    return (
      <div className={styles.section}>
        <h3 className={styles.sectionTitle}>
          {title} {isAi && '🤖'}
        </h3>
        <div className={styles.table}>
          <div className={styles.tableHeader}>
            <div className={styles.rankCol}>Rank</div>
            <div className={styles.scoreCol}>Score</div>
            <div className={styles.nameCol}>Player</div>
            <div className={styles.turnsCol}>Turns Used</div>
            <div className={styles.lastLoginCol}>Last Login</div>
            <div className={styles.onlineCol}>Online</div>
            <div className={styles.alignmentCol}>Alignment</div>
          </div>
          {players.map((player) => (
            <div key={`${player.player_name}-${player.rank}`} className={styles.tableRow}>
              <div className={styles.rankCol}>
                {getRankIcon(player.rank)}
              </div>
              <div className={styles.scoreCol}>
                {formatCredits(player.score)}
              </div>
              <div className={styles.nameCol}>
                <span className={isAi ? styles.aiPlayerName : styles.humanPlayerName}>
                  {player.player_name}
                </span>
              </div>
              <div className={styles.turnsCol}>
                {player.turns_spent.toLocaleString()}
              </div>
              <div className={styles.lastLoginCol}>
                {player.last_login ? formatLastLogin(player.last_login) : 'Never'}
              </div>
              <div className={styles.onlineCol}>
                <span className={player.is_online ? styles.onlineStatus : styles.offlineStatus}>
                  {player.is_online ? '🟢' : '🔴'}
                </span>
              </div>
              <div className={styles.alignmentCol}>
                <span className={styles.placeholder}>—</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    )
  }

  if (!open) return null

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>🏆 Leaderboard</h2>
          <button className={styles.closeBtn} onClick={onClose}>
            ✕
          </button>
        </div>

        {error && (
          <div className={styles.error}>
            {error}
          </div>
        )}

        {loading && (
          <div className={styles.loading}>
            Loading leaderboard...
          </div>
        )}

        {!loading && !error && (
          <div className={styles.content}>
            {renderPlayerList(humanPlayers, 'Human Players', false)}
            {renderPlayerList(aiPlayers, 'AI Players', true)}
          </div>
        )}

        <div className={styles.footer}>
          <button 
            className={styles.refreshBtn}
            onClick={calculateRankings}
            disabled={loading}
          >
            {loading ? '⏳ Calculating...' : '🔄 Refresh Rankings'}
          </button>
        </div>
      </div>
    </div>
  )
}