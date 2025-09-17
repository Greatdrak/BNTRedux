'use client'

import { useState } from 'react'
import styles from './EquipmentPanel.module.css'

interface EquipmentPanelProps {
  port?: {
    id: string
    kind: string
  }
  player?: {
    credits: number
  }
  ship?: {
    hull: number
    fighters: number
    torpedoes: number
  }
  onUpgrade: (data: { item: string; qty: number }) => void
  onRepair: (data: { hull: number }) => void
  upgradeLoading?: boolean
  repairLoading?: boolean
}

// Client-side pricing constants (for preview only, server is source of truth)
const FIGHTER_COST = 50
const TORPEDO_COST = 120
const HULL_REPAIR_COST = 2
const HULL_MAX = 100

export default function EquipmentPanel({ 
  port, 
  player, 
  ship, 
  onUpgrade, 
  onRepair, 
  upgradeLoading, 
  repairLoading 
}: EquipmentPanelProps) {
  const [upgradeItem, setUpgradeItem] = useState<'fighters' | 'torpedoes'>('fighters')
  const [upgradeQty, setUpgradeQty] = useState(1)
  const [repairHull, setRepairHull] = useState(1)

  const getUpgradeCost = () => {
    const unitCost = upgradeItem === 'fighters' ? FIGHTER_COST : TORPEDO_COST
    return unitCost * upgradeQty
  }

  const getRepairCost = () => {
    if (!ship) return 0
    const actualRepair = Math.min(repairHull, HULL_MAX - ship.hull)
    return actualRepair * HULL_REPAIR_COST
  }

  const getRepairPreview = () => {
    if (!ship) return 0
    return Math.min(ship.hull + repairHull, HULL_MAX)
  }

  const isUpgradeValid = () => {
    if (!player || !ship || upgradeQty <= 0) return false
    return getUpgradeCost() <= player.credits
  }

  const isRepairValid = () => {
    if (!player || !ship || repairHull <= 0) return false
    if (ship.hull >= HULL_MAX) return false
    return getRepairCost() <= player.credits
  }

  const handleUpgradeSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (isUpgradeValid() && !upgradeLoading) {
      onUpgrade({ item: upgradeItem, qty: upgradeQty })
    }
  }

  const handleRepairSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (isRepairValid() && !repairLoading) {
      onRepair({ hull: repairHull })
    }
  }

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat('en-US').format(num)
  }

  if (!port) {
    return (
      <div className={styles.panel}>
        <h3>Equipment & Repair</h3>
        <div className={styles.noPort}>
          <p>No port available in this sector</p>
          <p className={styles.hint}>Find a sector with a port to purchase equipment</p>
        </div>
      </div>
    )
  }

  return (
    <div className={styles.panel}>
      <h3>Equipment & Repair</h3>
      
      {/* Equipment Purchase */}
      <div className={styles.section}>
        <h4>Purchase Equipment</h4>
        <form onSubmit={handleUpgradeSubmit} className={styles.form}>
          <div className={styles.formGroup}>
            <label htmlFor="upgradeItem">Item</label>
            <select
              id="upgradeItem"
              value={upgradeItem}
              onChange={(e) => setUpgradeItem(e.target.value as 'fighters' | 'torpedoes')}
              className={styles.select}
            >
              <option value="fighters">Fighters (50 cr each)</option>
              <option value="torpedoes">Torpedoes (120 cr each)</option>
            </select>
          </div>
          
          <div className={styles.formGroup}>
            <label htmlFor="upgradeQty">Quantity</label>
            <input
              id="upgradeQty"
              type="number"
              min="1"
              value={upgradeQty}
              onChange={(e) => setUpgradeQty(parseInt(e.target.value) || 1)}
              className={styles.input}
            />
          </div>

          <div className={styles.preview}>
            <div className={styles.previewRow}>
              <span>Total Cost:</span>
              <span>{formatNumber(getUpgradeCost())} cr</span>
            </div>
          </div>
          
          <button
            type="submit"
            disabled={upgradeLoading || !isUpgradeValid()}
            className={styles.submitBtn}
          >
            {upgradeLoading ? 'Purchasing...' : `Buy ${upgradeQty} ${upgradeItem}`}
          </button>
        </form>
      </div>

      {/* Hull Repair */}
      <div className={styles.section}>
        <h4>Repair Hull</h4>
        <form onSubmit={handleRepairSubmit} className={styles.form}>
          <div className={styles.formGroup}>
            <label htmlFor="repairHull">Hull Points to Repair</label>
            <input
              id="repairHull"
              type="number"
              min="1"
              max={ship ? HULL_MAX - ship.hull : 100}
              value={repairHull}
              onChange={(e) => setRepairHull(parseInt(e.target.value) || 1)}
              className={styles.input}
            />
          </div>

          <div className={styles.preview}>
            <div className={styles.previewRow}>
              <span>Current Hull:</span>
              <span>{ship?.hull || 0}/100</span>
            </div>
            <div className={styles.previewRow}>
              <span>After Repair:</span>
              <span>{getRepairPreview()}/100</span>
            </div>
            <div className={styles.previewRow}>
              <span>Cost:</span>
              <span>{formatNumber(getRepairCost())} cr</span>
            </div>
          </div>
          
          <button
            type="submit"
            disabled={repairLoading || !isRepairValid()}
            className={styles.submitBtn}
          >
            {repairLoading ? 'Repairing...' : `Repair ${repairHull} Hull Points`}
          </button>
        </form>
      </div>
    </div>
  )
}
