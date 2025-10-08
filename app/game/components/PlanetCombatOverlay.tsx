'use client'

import React, { useMemo } from 'react'
import styles from './CombatOverlay.module.css'
import ShipArt from '../../ship/components/ShipArt'

interface PlanetCombatOverlayProps {
  open: boolean
  onClose: () => void
  playerShip: any
  planet: { name: string; defenses?: { fighters: number; torpedoes: number; shields: number }; stock?: { energy: number } }
  steps: Array<{ id: number; type?: string; attacker?: 'attacker' | 'defender' | 'player' | 'enemy'; action: string; description?: string; damage?: number; target?: string }>
  winner: 'attacker' | 'defender' | 'draw'
}

export default function PlanetCombatOverlay({ open, onClose, playerShip, planet, steps, winner }: PlanetCombatOverlayProps) {
  const normalizedSteps = useMemo(() => {
    return (steps || []).map((s) => ({
      id: s.id,
      type: (s.type as any) || 'damage',
      attacker: (s.attacker === 'attacker' ? 'player' : s.attacker === 'defender' ? 'enemy' : s.attacker) as 'player' | 'enemy',
      action: s.action,
      description: s.description || '',
      damage: s.damage,
      target: s.target as any
    }))
  }, [steps])

  if (!open) return null

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>Planet Combat</h2>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>

        <div className={styles.content}>
          {/* Player Ship vs Planet Panel */}
          <div className={styles.shipStatus}>
            <div className={styles.playerShip}>
              <h3>{playerShip?.name || 'Your Ship'}</h3>
              <div className={styles.shipImage}>
                <ShipArt level={playerShip?.hull_lvl || 1} size={80} />
              </div>
              <div className={styles.shipStats}>
                <div className={styles.statRow}>
                  <span>Armor:</span>
                  <span>{playerShip?.armor || 0} / {playerShip?.armor_max || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Shields:</span>
                  <span>{playerShip?.shield || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Fighters:</span>
                  <span>{playerShip?.fighters || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Torpedoes:</span>
                  <span>{playerShip?.torpedoes || 0}</span>
                </div>
              </div>
            </div>

            <div className={styles.vsDivider}>
              <div className={styles.vsText}>VS</div>
            </div>

            <div className={styles.enemyShip}>
              <h3>Planet: {planet?.name}</h3>
              <div className={styles.shipImage}>
                <div style={{ fontSize: 48 }}>🪐</div>
              </div>
              <div className={styles.shipStats}>
                <div className={styles.statRow}>
                  <span>Fighters:</span>
                  <span>{planet?.defenses?.fighters?.toLocaleString() || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Torpedoes:</span>
                  <span>{planet?.defenses?.torpedoes?.toLocaleString() || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Energy:</span>
                  <span>{planet?.stock?.energy?.toLocaleString() || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Shield Buffer:</span>
                  <span>{planet?.defenses?.shields?.toLocaleString() || 0}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Steps */}
          <div className={styles.combatSteps}>
            <h3>Combat Progress</h3>
            <div className={styles.stepsContainer}>
              {normalizedSteps.map((step) => (
                <div key={step.id} className={styles.step}>
                  <div className={styles.stepIcon}>
                    {step.type === 'result' ? '📊' : step.attacker === 'player' ? '⚔️' : '💥'}
                  </div>
                  <div className={styles.stepContent}>
                    <div className={styles.stepAction}>{step.action}</div>
                    {step.description && (
                      <div className={styles.stepDescription}>{step.description}</div>
                    )}
                    {typeof step.damage === 'number' && (
                      <div className={styles.damageInfo}>
                        Damage: {step.damage}{step.target ? ` to ${step.target}` : ''}
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Results */}
          <div className={styles.combatResults}>
            <h3>Combat Results</h3>
            <div className={styles.resultSummary}>
              <div className={`${styles.winner} ${styles[winner === 'attacker' ? 'player' : winner === 'defender' ? 'enemy' : 'draw']}`}>
                {winner === 'attacker' ? '🎉 Victory!' : winner === 'defender' ? '💀 Defeat!' : '🤝 Draw!'}
              </div>
            </div>
          </div>

          <div className={styles.actionSection}>
            <button className={styles.closeCombatBtn} onClick={onClose}>Close Combat Report</button>
          </div>
        </div>
      </div>
    </div>
  )
}


