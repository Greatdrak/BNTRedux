'use client'

import React, { useState, useEffect } from 'react'
import styles from './CombatOverlay.module.css'
import ShipArt from '../../ship/components/ShipArt'

interface CombatStep {
  id: number
  type: 'attack' | 'defense' | 'damage' | 'result'
  attacker: 'player' | 'enemy'
  action: string
  description: string
  damage?: number
  target?: 'hull' | 'shield' | 'fighters' | 'torpedoes'
  success?: boolean
  playerHull?: number
  playerShield?: number
  playerFighters?: number
  playerTorpedoes?: number
  enemyHull?: number
  enemyShield?: number
  enemyFighters?: number
  enemyTorpedoes?: number
}

interface CombatResult {
  winner: 'player' | 'enemy' | 'draw'
  playerShip: {
    hull: number
    hull_max: number
    shield: number
    fighters: number
    torpedoes: number
    energy: number
    energy_max: number
    credits: number
    ore: number
    organics: number
    goods: number
    colonists: number
  }
  enemyShip: {
    hull: number
    hull_max: number
    shield: number
    fighters: number
    torpedoes: number
    energy: number
    energy_max: number
    credits: number
    ore: number
    organics: number
    goods: number
    colonists: number
  }
  salvage?: {
    credits: number
    ore: number
    organics: number
    goods: number
    colonists: number
  }
  turnsUsed: number
}

interface CombatOverlayProps {
  open: boolean
  onClose: () => void
  playerShip: any
  enemyShip: any
  combatResult: CombatResult | null
  combatSteps: CombatStep[]
  isCombatComplete: boolean
  enemyIsPlanet?: boolean
  planetId?: string
  onCapturePlanet?: () => Promise<void> | void
}

export default function CombatOverlay({
  open,
  onClose,
  playerShip,
  enemyShip,
  combatResult,
  combatSteps,
  isCombatComplete,
  enemyIsPlanet,
  planetId,
  onCapturePlanet
}: CombatOverlayProps) {
  const [currentStepIndex, setCurrentStepIndex] = useState(0)
  const [isAnimating, setIsAnimating] = useState(false)

  // Auto-advance through combat steps
  useEffect(() => {
    if (!open || isCombatComplete) return

    const interval = setInterval(() => {
      setIsAnimating(true)
      setTimeout(() => {
        setCurrentStepIndex(prev => {
          if (prev < combatSteps.length - 1) {
            return prev + 1
          }
          return prev
        })
        setIsAnimating(false)
      }, 500)
    }, 2000) // 2 seconds per step

    return () => clearInterval(interval)
  }, [open, combatSteps.length, isCombatComplete])

  if (!open) return null

  const currentStep = combatSteps[currentStepIndex]
  const isLastStep = currentStepIndex === combatSteps.length - 1

  const getStepIcon = (step: CombatStep) => {
    switch (step.type) {
      case 'attack':
        return step.attacker === 'player' ? '⚔️' : '🛡️'
      case 'defense':
        return '🛡️'
      case 'damage':
        return '💥'
      case 'result':
        return '📊'
      default:
        return '⚡'
    }
  }

  const getStepColor = (step: CombatStep) => {
    if (step.type === 'damage') return 'var(--error)'
    if (step.type === 'result') return 'var(--accent)'
    if (step.attacker === 'player') return 'var(--accent)'
    return 'var(--error)'
  }

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>{enemyIsPlanet ? 'Planet Combat' : 'Ship Combat'}</h2>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>

        <div className={styles.content}>
          {/* Ship Status Display */}
          <div className={styles.shipStatus}>
            <div className={styles.playerShip}>
              <h3>{playerShip?.name || 'Your Ship'}</h3>
              <div className={styles.shipImage}>
                <ShipArt level={playerShip?.hull_lvl || 1} size={80} />
              </div>
              <div className={styles.shipStats}>
                <div className={styles.statRow}>
                  <span>Hull:</span>
                  <span>{currentStep?.playerHull || playerShip?.hull || 0} / {playerShip?.hull_max || 100}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Shield:</span>
                  <span>{currentStep?.playerShield || playerShip?.shield || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Fighters:</span>
                  <span>{currentStep?.playerFighters || playerShip?.fighters || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Torpedoes:</span>
                  <span>{currentStep?.playerTorpedoes || playerShip?.torpedoes || 0}</span>
                </div>
              </div>
            </div>

            <div className={styles.vsDivider}>
              <div className={styles.vsText}>VS</div>
            </div>

            <div className={styles.enemyShip}>
              <h3>{enemyShip?.name || (enemyIsPlanet ? 'Planet' : 'Enemy Ship')}</h3>
              <div className={styles.shipImage}>
                {enemyIsPlanet ? (
                  <div style={{ fontSize: 48 }}>🪐</div>
                ) : (
                  <ShipArt level={enemyShip?.hull_lvl || 1} size={80} />
                )}
              </div>
              <div className={styles.shipStats}>
                {!enemyIsPlanet && (
                  <div className={styles.statRow}>
                    <span>Hull:</span>
                    <span>{currentStep?.enemyHull || enemyShip?.hull || 0} / {enemyShip?.hull_max || 100}</span>
                  </div>
                )}
                <div className={styles.statRow}>
                  <span>Shield:</span>
                  <span>{currentStep?.enemyShield || enemyShip?.shield || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Fighters:</span>
                  <span>{currentStep?.enemyFighters || enemyShip?.fighters || 0}</span>
                </div>
                <div className={styles.statRow}>
                  <span>Torpedoes:</span>
                  <span>{currentStep?.enemyTorpedoes || enemyShip?.torpedoes || 0}</span>
                </div>
                {enemyIsPlanet && (
                  <div className={styles.statRow}>
                    <span>Energy:</span>
                    <span>{enemyShip?.energy || 0}</span>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Combat Steps */}
          <div className={styles.combatSteps}>
            <h3>Combat Progress</h3>
            <div className={styles.stepsContainer}>
              {combatSteps.map((step, index) => (
                <div
                  key={step.id}
                  className={`${styles.step} ${index === currentStepIndex ? styles.activeStep : ''} ${index < currentStepIndex ? styles.completedStep : ''}`}
                >
                  <div className={styles.stepIcon} style={{ color: getStepColor(step) }}>
                    {getStepIcon(step)}
                  </div>
                  <div className={styles.stepContent}>
                    <div className={styles.stepAction}>{step.action}</div>
                    <div className={styles.stepDescription}>{step.description}</div>
                    {step.damage && (
                      <div className={styles.damageInfo}>
                        Damage: {step.damage} to {step.target}
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Combat Results */}
          {isCombatComplete && combatResult && (
            <div className={styles.combatResults}>
              <h3>Combat Results</h3>
              <div className={styles.resultSummary}>
                <div className={`${styles.winner} ${styles[combatResult.winner]}`}>
                  {combatResult.winner === 'player' ? '🎉 Victory!' : 
                   combatResult.winner === 'enemy' ? '💀 Defeat!' : 
                   '🤝 Draw!'}
                </div>
                
                {combatResult.salvage && (
                  <div className={styles.salvage}>
                    <h4>Salvage Gained:</h4>
                    <div className={styles.salvageItems}>
                      {combatResult.salvage.credits > 0 && (
                        <div>Credits: {combatResult.salvage.credits.toLocaleString()}</div>
                      )}
                      {combatResult.salvage.ore > 0 && (
                        <div>Ore: {combatResult.salvage.ore.toLocaleString()}</div>
                      )}
                      {combatResult.salvage.organics > 0 && (
                        <div>Organics: {combatResult.salvage.organics.toLocaleString()}</div>
                      )}
                      {combatResult.salvage.goods > 0 && (
                        <div>Goods: {combatResult.salvage.goods.toLocaleString()}</div>
                      )}
                      {combatResult.salvage.colonists > 0 && (
                        <div>Colonists: {combatResult.salvage.colonists.toLocaleString()}</div>
                      )}
                    </div>
                  </div>
                )}
                
                <div className={styles.turnsUsed}>
                  Turns Used: {combatResult.turnsUsed}
                </div>
              </div>
            </div>
          )}

          {/* Action Buttons */}
          <div className={styles.actionSection}>
            {!isCombatComplete ? (
              <div className={styles.combatProgress}>
                <div className={styles.progressBar}>
                  <div 
                    className={styles.progressFill}
                    style={{ width: `${((currentStepIndex + 1) / combatSteps.length) * 100}%` }}
                  />
                </div>
                <p>Combat in progress...</p>
              </div>
            ) : (
              <div className={styles.actionsRow}>
                {enemyIsPlanet && combatResult?.winner === 'player' && (enemyShip?.shield || 0) <= 0 && (enemyShip?.fighters || 0) <= 0 && onCapturePlanet && planetId ? (
                  <button className={styles.closeCombatBtn} onClick={async () => { await onCapturePlanet(); onClose(); }}>
                    Capture Planet
                  </button>
                ) : null}
                <button className={styles.closeCombatBtn} onClick={onClose}>
                  Close Combat Report
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
