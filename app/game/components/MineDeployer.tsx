'use client'

import { useState } from 'react'
import { supabase } from '@/lib/supabase-client'
import styles from './MineDeployer.module.css'

interface MineDeployerProps {
  sectorNumber: number
  universeId: string
  playerTorpedoes: number
  onDeploySuccess?: () => void
}

export default function MineDeployer({ 
  sectorNumber, 
  universeId, 
  playerTorpedoes,
  onDeploySuccess 
}: MineDeployerProps) {
  const [torpedoesToUse, setTorpedoesToUse] = useState(1)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState<{ type: 'success' | 'error', message: string } | null>(null)
  const [showInput, setShowInput] = useState(false)

  const handleDeploy = async () => {
    if (torpedoesToUse > playerTorpedoes) {
      setStatus({ type: 'error', message: 'Not enough torpedoes' })
      return
    }

    setLoading(true)
    setStatus(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        throw new Error('No authentication token')
      }

      const response = await fetch('/api/mines/deploy', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          sector_number: sectorNumber,
          universe_id: universeId,
          torpedoes_to_use: torpedoesToUse
        })
      })

      const result = await response.json()

      if (!response.ok) {
        throw new Error(result.error?.message || 'Failed to deploy mines')
      }

      setStatus({ 
        type: 'success', 
        message: `Successfully deployed ${torpedoesToUse} torpedo mine(s)!` 
      })
      
      if (onDeploySuccess) {
        onDeploySuccess()
      }

      setShowInput(false)

    } catch (error) {
      console.error('Error deploying mines:', error)
      setStatus({ 
        type: 'error', 
        message: error instanceof Error ? error.message : 'Failed to deploy mines' 
      })
    } finally {
      setLoading(false)
    }
  }

  const handleMaxTorpedoes = () => {
    setTorpedoesToUse(playerTorpedoes)
  }

  if (!showInput) {
    return (
      <div className={styles.floatingMineButton}>
        <button 
          onClick={() => setShowInput(true)}
          className={styles.mineIcon}
          title="Deploy Mines"
          disabled={playerTorpedoes === 0}
        >
          💣
        </button>
      </div>
    )
  }

  return (
    <div className={styles.container}>
      <div className={styles.inputContainer}>
        <label htmlFor="torpedoes" className={styles.label}>
          Torpedoes to use:
        </label>
        <input
          id="torpedoes"
          type="number"
          min="1"
          max={playerTorpedoes}
          value={torpedoesToUse}
          onChange={(e) => setTorpedoesToUse(Math.max(1, Math.min(playerTorpedoes, parseInt(e.target.value) || 1)))}
          className={styles.input}
          disabled={loading || playerTorpedoes === 0}
        />
        <button 
          onClick={handleMaxTorpedoes}
          className={styles.maxButton}
          disabled={loading || playerTorpedoes === 0}
        >
          Max ({playerTorpedoes})
        </button>
        <button
          onClick={handleDeploy}
          disabled={loading || playerTorpedoes === 0 || torpedoesToUse > playerTorpedoes}
          className={styles.deployButton}
        >
          {loading ? 'Deploying...' : 'Deploy'}
        </button>
        <button 
          onClick={() => setShowInput(false)}
          className={styles.cancelButton}
          disabled={loading}
        >
          ✕
        </button>
      </div>

      {status && (
        <div className={`${styles.status} ${styles[status.type]}`}>
          {status.message}
        </div>
      )}
    </div>
  )
}
