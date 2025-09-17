'use client'

import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase-client'
import styles from './LeaderboardOverlay.module.css'

interface LeaderboardEntry {
  rank: number
  name: string
  total_score: number
  economic_score: number
  territorial_score: number
  military_score: number
  exploration_score: number
  type: 'player' | 'ai'
}

interface LeaderboardOverlayProps {
  open: boolean
  onClose: () => void
  universeId: string
}

export default function LeaderboardOverlay({ open, onClose, universeId }: LeaderboardOverlayProps) {
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selectedCategory, setSelectedCategory] = useState<'overall' | 'economic' | 'territorial' | 'military' | 'exploration'>('overall')

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
      if (data.ok) {
        console.log('Leaderboard data:', data.leaderboard)
        setLeaderboard(data.leaderboard || [])
      } else {
        throw new Error(data.error?.message || 'Failed to load leaderboard')
      }
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

      console.log('Calculating rankings for universe:', universeId)
      
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
      
      if (data.ok) {
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

  const getSortedLeaderboard = () => {
    if (!leaderboard.length) return []
    
    const sorted = [...leaderboard].sort((a, b) => {
      switch (selectedCategory) {
        case 'economic':
          return b.economic_score - a.economic_score
        case 'territorial':
          return b.territorial_score - a.territorial_score
        case 'military':
          return b.military_score - a.military_score
        case 'exploration':
          return b.exploration_score - a.exploration_score
        default:
          return b.total_score - a.total_score
      }
    })
    
    return sorted.map((entry, index) => ({
      ...entry,
      rank: index + 1
    }))
  }

  const getScoreForCategory = (entry: LeaderboardEntry) => {
    switch (selectedCategory) {
      case 'economic':
        return entry.economic_score
      case 'territorial':
        return entry.territorial_score
      case 'military':
        return entry.military_score
      case 'exploration':
        return entry.exploration_score
      default:
        return entry.total_score
    }
  }

  const formatScore = (score: number) => {
    return new Intl.NumberFormat('en-US').format(score)
  }

  const getRankIcon = (rank: number) => {
    if (rank === 1) return '🥇'
    if (rank === 2) return '🥈'
    if (rank === 3) return '🥉'
    return `#${rank}`
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

        <div className={styles.categories}>
          <button 
            className={`${styles.categoryBtn} ${selectedCategory === 'overall' ? styles.active : ''}`}
            onClick={() => setSelectedCategory('overall')}
          >
            Overall
          </button>
          <button 
            className={`${styles.categoryBtn} ${selectedCategory === 'economic' ? styles.active : ''}`}
            onClick={() => setSelectedCategory('economic')}
          >
            Economic
          </button>
          <button 
            className={`${styles.categoryBtn} ${selectedCategory === 'territorial' ? styles.active : ''}`}
            onClick={() => setSelectedCategory('territorial')}
          >
            Territorial
          </button>
          <button 
            className={`${styles.categoryBtn} ${selectedCategory === 'military' ? styles.active : ''}`}
            onClick={() => setSelectedCategory('military')}
          >
            Military
          </button>
          <button 
            className={`${styles.categoryBtn} ${selectedCategory === 'exploration' ? styles.active : ''}`}
            onClick={() => setSelectedCategory('exploration')}
          >
            Exploration
          </button>
        </div>

        {loading && (
          <div className={styles.loading}>
            <div className={styles.spinner}></div>
            <p>Loading leaderboard...</p>
          </div>
        )}

        {error && (
          <div className={styles.error}>
            <p>{error}</p>
            <button className={styles.retryBtn} onClick={fetchLeaderboard}>
              Retry
            </button>
          </div>
        )}

        {!loading && !error && (
          <div className={styles.leaderboard}>
            {leaderboard.length === 0 && (
              <div className={styles.emptyState}>
                <p>No rankings data available</p>
                <button className={styles.calculateBtn} onClick={calculateRankings}>
                  Calculate Rankings
                </button>
              </div>
            )}
            
            {leaderboard.length > 0 && (
              <>
                <div className={styles.tableHeader}>
                  <div className={styles.rankCol}>Rank</div>
                  <div className={styles.nameCol}>Player</div>
                  <div className={styles.scoreCol}>Score</div>
                  <div className={styles.typeCol}>Type</div>
                </div>
            
                <div className={styles.tableBody}>
                  {getSortedLeaderboard().map((entry) => (
                    <div key={`${entry.type}-${entry.name}`} className={styles.tableRow}>
                      <div className={styles.rankCol}>
                        <span className={styles.rankIcon}>
                          {getRankIcon(entry.rank)}
                        </span>
                      </div>
                      <div className={styles.nameCol}>
                        <span className={entry.type === 'ai' ? styles.aiName : styles.playerName}>
                          {entry.name}
                        </span>
                      </div>
                      <div className={styles.scoreCol}>
                        {formatScore(getScoreForCategory(entry))}
                      </div>
                      <div className={styles.typeCol}>
                        <span className={`${styles.typeBadge} ${styles[entry.type]}`}>
                          {entry.type.toUpperCase()}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </div>
        )}

        <div className={styles.footer}>
          <p className={styles.lastUpdated}>
            Rankings update every 5 minutes
          </p>
        </div>
      </div>
    </div>
  )
}
