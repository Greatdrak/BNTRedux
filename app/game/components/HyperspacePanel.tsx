'use client'

import { useState } from 'react'
import styles from './ActionsPanel.module.css'

interface HyperspacePanelProps {
  engineLvl?: number
  currentSector?: number
  turns?: number
  target: number
  onChangeTarget: (n: number) => void
  onJump: (sectorNumber: number) => void
  loading?: boolean
}

export default function HyperspacePanel({ engineLvl=1, currentSector=1, turns=0, target, onChangeTarget, onJump, loading }: HyperspacePanelProps) {

  const distance = Math.abs((target || 0) - (currentSector || 0))
  const cost = Math.max(1, Math.ceil(distance / Math.max(1, engineLvl)))
  const disabled = loading || !target || cost > (turns || 0)

  return (
    <div className={styles.panel}>
      <h3>Realspace</h3>
      <div className={styles.formGroup}>
        <label>Target sector #</label>
        <input
          className={styles.input}
          type="number"
          value={target}
          onChange={(e)=> onChangeTarget(parseInt(e.target.value)||0)}
        />
      </div>
      <div className={styles.tradePreview}>
        <div className={styles.previewRow}><span>Engine</span><span>Lv {engineLvl}</span></div>
        <div className={styles.previewRow}><span>Turns available</span><span>{turns ?? '--'}</span></div>
        <div className={styles.previewRow}><span>Turn cost</span><span>{cost}</span></div>
      </div>
      <button className={styles.submitBtn} disabled={disabled} onClick={()=> onJump(target)}>
        {loading ? 'Jumping...' : 'Jump'}
      </button>
    </div>
  )
}


