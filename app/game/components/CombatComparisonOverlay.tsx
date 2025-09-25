'use client'

import React from 'react'
import styles from './CombatComparisonOverlay.module.css'
import ShipArt from '../../ship/components/ShipArt'

interface PlayerShip {
  id: string
  name: string
  hull: number
  hull_max: number
  hull_lvl: number
  shield: number
  shield_max: number
  shield_lvl: number
  engine_lvl: number
  comp_lvl: number
  sensor_lvl: number
  power_lvl: number
  beam_lvl: number
  torp_launcher_lvl: number
  cloak_lvl: number
  armor: number
  armor_lvl: number
  cargo: number
  fighters: number
  torpedoes: number
  colonists: number
  energy: number
  energy_max: number
  credits: number
  ore: number
  organics: number
  goods: number
}

interface EnemyShip {
  id: string
  name: string
  player_handle: string
  hull?: number
  hull_max?: number
  hull_lvl?: number
  shield?: number
  shield_max?: number
  shield_lvl?: number
  fighters?: number
  torpedoes?: number
  energy?: number
  energy_max?: number
  engine_lvl?: number
  comp_lvl?: number
  sensor_lvl?: number
  power_lvl?: number
  beam_lvl?: number
  torp_launcher_lvl?: number
  cloak_lvl?: number
  armor?: number
  armor_lvl?: number
  credits?: number
  ore?: number
  organics?: number
  goods?: number
  colonists?: number
}

interface CombatComparisonOverlayProps {
  open: boolean
  onClose: () => void
  playerShip: PlayerShip | null
  enemyShip: EnemyShip | null
  onConfirmAttack: () => void
}

export default function CombatComparisonOverlay({
  open,
  onClose,
  playerShip,
  enemyShip,
  onConfirmAttack
}: CombatComparisonOverlayProps) {
  if (!open || !playerShip || !enemyShip) return null

  const renderComparisonRow = (label: string, playerValue: any, enemyValue: any, format?: (val: any) => string) => {
    const formatValue = format || ((val: any) => val?.toString() || '???')
    
    return (
      <div className={styles.comparisonRow}>
        <div className={styles.label}>{label}</div>
        <div className={styles.playerValue}>{formatValue(playerValue)}</div>
        <div className={styles.vs}>VS</div>
        <div className={styles.enemyValue}>{formatValue(enemyValue)}</div>
      </div>
    )
  }

  const formatNumber = (val: any) => {
    if (val === undefined || val === null) return '???'
    return typeof val === 'number' ? val.toLocaleString() : val.toString()
  }

  const formatLevel = (val: any) => {
    if (val === undefined || val === null) return '???'
    return val.toString()
  }

  const formatHealth = (current: any, max: any) => {
    if (current === undefined || max === undefined) return '???'
    return `${current.toLocaleString()} / ${max.toLocaleString()}`
  }

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>Combat Comparison</h2>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>

        <div className={styles.content}>
          {/* Ship Images */}
          <div className={styles.shipImages}>
            <div className={styles.playerShip}>
              <h3>{playerShip.name}</h3>
              <div className={styles.shipImage}>
                <ShipArt level={playerShip.hull_lvl || 1} size={100} />
              </div>
              <p className={styles.pilotName}>You</p>
            </div>
            
            <div className={styles.vsDivider}>
              <div className={styles.vsText}>VS</div>
            </div>
            
            <div className={styles.enemyShip}>
              <h3>{enemyShip.name}</h3>
              <div className={styles.shipImage}>
                <ShipArt level={enemyShip.hull_lvl || 1} size={100} />
              </div>
              <p className={styles.pilotName}>{enemyShip.player_handle || 'Unknown'}</p>
            </div>
          </div>

          {/* Combat Stats Comparison */}
          <div className={styles.comparisonSection}>
            <h3>Combat Statistics</h3>
            <div className={styles.comparisonGrid}>
              {renderComparisonRow('Hull', formatHealth(playerShip.hull, playerShip.hull_max), formatHealth(enemyShip.hull, enemyShip.hull_max))}
              {renderComparisonRow('Shield', formatHealth(playerShip.shield, playerShip.shield_max), formatHealth(enemyShip.shield, enemyShip.shield_max))}
              {renderComparisonRow('Energy', formatHealth(playerShip.energy, playerShip.energy_max), formatHealth(enemyShip.energy, enemyShip.energy_max))}
              {renderComparisonRow('Fighters', formatNumber(playerShip.fighters), formatNumber(enemyShip.fighters))}
              {renderComparisonRow('Torpedoes', formatNumber(playerShip.torpedoes), formatNumber(enemyShip.torpedoes))}
              {renderComparisonRow('Armor', formatNumber(playerShip.armor), formatNumber(enemyShip.armor))}
            </div>
          </div>

          {/* Tech Levels Comparison */}
          <div className={styles.comparisonSection}>
            <h3>Technology Levels</h3>
            <div className={styles.comparisonGrid}>
              {renderComparisonRow('Hull Level', formatLevel(playerShip.hull_lvl), formatLevel(enemyShip.hull_lvl))}
              {renderComparisonRow('Engine Level', formatLevel(playerShip.engine_lvl), formatLevel(enemyShip.engine_lvl))}
              {renderComparisonRow('Computer Level', formatLevel(playerShip.comp_lvl), formatLevel(enemyShip.comp_lvl))}
              {renderComparisonRow('Sensor Level', formatLevel(playerShip.sensor_lvl), formatLevel(enemyShip.sensor_lvl))}
              {renderComparisonRow('Power Level', formatLevel(playerShip.power_lvl), formatLevel(enemyShip.power_lvl))}
              {renderComparisonRow('Shield Level', formatLevel(playerShip.shield_lvl), formatLevel(enemyShip.shield_lvl))}
              {renderComparisonRow('Beam Level', formatLevel(playerShip.beam_lvl), formatLevel(enemyShip.beam_lvl))}
              {renderComparisonRow('Torpedo Level', formatLevel(playerShip.torp_launcher_lvl), formatLevel(enemyShip.torp_launcher_lvl))}
            </div>
          </div>

          {/* Cargo Comparison */}
          <div className={styles.comparisonSection}>
            <h3>Cargo & Resources</h3>
            <div className={styles.comparisonGrid}>
              {renderComparisonRow('Credits', formatNumber(playerShip.credits), formatNumber(enemyShip.credits))}
              {renderComparisonRow('Ore', formatNumber(playerShip.ore), formatNumber(enemyShip.ore))}
              {renderComparisonRow('Organics', formatNumber(playerShip.organics), formatNumber(enemyShip.organics))}
              {renderComparisonRow('Goods', formatNumber(playerShip.goods), formatNumber(enemyShip.goods))}
              {renderComparisonRow('Colonists', formatNumber(playerShip.colonists), formatNumber(enemyShip.colonists))}
            </div>
          </div>

          {/* Action Buttons */}
          <div className={styles.actionSection}>
            <button className={styles.cancelBtn} onClick={onClose}>
              Cancel
            </button>
            <button className={styles.attackBtn} onClick={onConfirmAttack}>
              ATTACK!
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
