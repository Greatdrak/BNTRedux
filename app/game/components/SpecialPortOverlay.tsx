'use client'

import { useState } from 'react'
import styles from './SpecialPortOverlay.module.css'

interface SpecialPortOverlayProps {
  open: boolean
  onClose: () => void
  shipData?: {
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
    cargo: number
    fighters: number
    torpedoes: number
  }
  playerCredits?: number
  onUpgrade: (attr: string) => void
  upgradeLoading?: boolean
}

export default function SpecialPortOverlay({ 
  open, 
  onClose, 
  shipData, 
  playerCredits = 0,
  onUpgrade,
  upgradeLoading = false
}: SpecialPortOverlayProps) {
  if (!open) return null

  const upgradeCosts = {
    engine: 500 * (shipData?.engine_lvl || 1),
    computer: 400 * (shipData?.comp_lvl || 1),
    sensors: 400 * (shipData?.sensor_lvl || 1),
    shields: 300 * (shipData?.shield_lvl || 1),
    hull: 2000 * (shipData?.hull_lvl || 1)
  }

  const canAfford = (attr: string) => {
    return playerCredits >= upgradeCosts[attr as keyof typeof upgradeCosts]
  }

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <h2>SPECIAL PORT: SHIP UPGRADES</h2>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>

        <div className={styles.content}>
          {/* Ship Status */}
          <div className={styles.shipStatus}>
            <h3>Ship Status</h3>
            <div className={styles.shipInfo}>
              <div className={styles.shipName}>{shipData?.name || 'Unknown Ship'}</div>
              <div className={styles.credits}>Credits: {playerCredits.toLocaleString()}</div>
            </div>
          </div>

          {/* Ship Attributes */}
          <div className={styles.attributes}>
            <h3>Ship Attributes</h3>
            <div className={styles.attrGrid}>
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Hull</div>
                <div className={styles.attrValue}>
                  {shipData?.hull || 0} / {shipData?.hull_max || 0}
                  <span className={styles.level}>Lv.{shipData?.hull_lvl || 1}</span>
                </div>
              </div>
              
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Shields</div>
                <div className={styles.attrValue}>
                  {shipData?.shield || 0} / {shipData?.shield_max || 0}
                  <span className={styles.level}>Lv.{shipData?.shield_lvl || 0}</span>
                </div>
              </div>
              
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Engines</div>
                <div className={styles.attrValue}>
                  Level {shipData?.engine_lvl || 1}
                </div>
              </div>
              
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Computer</div>
                <div className={styles.attrValue}>
                  Level {shipData?.comp_lvl || 1}
                </div>
              </div>
              
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Sensors</div>
                <div className={styles.attrValue}>
                  Level {shipData?.sensor_lvl || 1}
                </div>
              </div>
              
              <div className={styles.attrItem}>
                <div className={styles.attrLabel}>Cargo</div>
                <div className={styles.attrValue}>
                  {shipData?.cargo || 0} units
                </div>
              </div>
            </div>
          </div>

          {/* Upgrades */}
          <div className={styles.upgrades}>
            <h3>Available Upgrades</h3>
            <div className={styles.upgradeGrid}>
              {Object.entries(upgradeCosts).map(([attr, cost]) => (
                <div key={attr} className={styles.upgradeItem}>
                  <div className={styles.upgradeInfo}>
                    <div className={styles.upgradeName}>
                      {attr.charAt(0).toUpperCase() + attr.slice(1)}
                    </div>
                    <div className={styles.upgradeCost}>
                      {cost.toLocaleString()} cr
                    </div>
                  </div>
                  <button
                    className={`${styles.upgradeBtn} ${!canAfford(attr) ? styles.disabled : ''}`}
                    onClick={() => onUpgrade(attr)}
                    disabled={!canAfford(attr) || upgradeLoading}
                  >
                    {upgradeLoading ? 'Upgrading...' : 'Upgrade'}
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
