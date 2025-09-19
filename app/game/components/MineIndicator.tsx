'use client'

import { useState, useEffect } from 'react'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './MineIndicator.module.css'

interface MineInfo {
  sector_number: number
  mine_count: number
  total_torpedoes: number
  deployed_by: Array<{
    player_handle: string
    torpedoes_used: number
    deployed_at: string
  }>
  has_mines: boolean
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
    throw new Error('Failed to fetch mine information')
  }
  return response.json()
}

export default function MineIndicator({ 
  sectorNumber, 
  universeId, 
  playerHullLevel 
}: { 
  sectorNumber: number
  universeId?: string
  playerHullLevel?: number
}) {
  const { data: mineInfo, error } = useSWR<MineInfo>(
    universeId ? `/api/sector/mines?number=${sectorNumber}&universe_id=${universeId}` : null,
    fetcher
  )

  const isSafeToEnter = () => {
    if (!mineInfo?.has_mines || !playerHullLevel) return true
    return playerHullLevel < 13  // Ships with hull level < 13 are safe from mines
  }

  if (error) {
    return null // Don't show error, just don't display mine info
  }

  if (!mineInfo || !mineInfo.has_mines) {
    return null // No mines, nothing to show
  }

  const safe = isSafeToEnter()

  return (
    <div className={`${styles.container} ${safe ? styles.safe : styles.dangerous}`}>
      <div className={styles.header}>
        <span className={styles.icon}>⚠️</span>
        <span className={styles.title}>Minefield Detected</span>
        <span className={`${styles.status} ${safe ? styles.safe : styles.dangerous}`}>
          {safe ? '✅ Safe' : '⚠️ Dangerous'}
        </span>
      </div>
      
      <div className={styles.details}>
        <div className={styles.mineCount}>
          {mineInfo.mine_count} mine{mineInfo.mine_count > 1 ? 's' : ''} detected
          ({mineInfo.total_torpedoes} torpedoes total)
        </div>
        
        <div className={styles.deployedBy}>
          <div className={styles.deployedByTitle}>Deployed by:</div>
          {mineInfo.deployed_by.map((deployment, index) => (
            <div key={index} className={styles.deployment}>
              <span className={styles.playerHandle}>{deployment.player_handle}</span>
              <span className={styles.torpedoesUsed}>
                ({deployment.torpedoes_used} torpedo{deployment.torpedoes_used > 1 ? 'es' : ''})
              </span>
            </div>
          ))}
        </div>
        
        <div className={styles.hullRequirement}>
          Hull Level Vulnerability: 13+
          {playerHullLevel && (
            <span className={styles.playerHull}>
              (Your: {playerHullLevel})
            </span>
          )}
        </div>
        
        {!safe && (
          <div className={styles.warning}>
            ⚠️ Entering this sector may damage your ship!
          </div>
        )}
      </div>
    </div>
  )
}
