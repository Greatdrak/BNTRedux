'use client'

import { useEffect, useRef } from 'react'
import styles from './MapOverlay.module.css'

interface WarpCell { number: number, port?: { kind: 'ore'|'organics'|'goods'|'energy'|'special' } | null, planetCount?: number }

interface WarpScanOverlayProps {
  open: boolean
  onClose: () => void
  sectors: WarpCell[]
  onPick: (n: number) => void
}

export default function WarpScanOverlay({ open, onClose, sectors, onPick }: WarpScanOverlayProps) {
  const firstRef = useRef<HTMLButtonElement|null>(null)
  useEffect(()=>{
    if (open) {
      setTimeout(()=> firstRef.current?.focus(), 0)
      const onKey = (e: KeyboardEvent)=>{ if (e.key==='Escape') onClose() }
      window.addEventListener('keydown', onKey)
      return ()=> window.removeEventListener('keydown', onKey)
    }
  }, [open, onClose])
  if (!open) return null

  const iconFor = (k: 'ore'|'organics'|'goods'|'energy'|'special'|undefined) => {
    switch (k) {
      case 'ore': return '🪨'
      case 'organics': return '🌿'
      case 'goods': return '📦'
      case 'energy': return '⚡'
      case 'special': return '✦'
      default: return ''
    }
  }

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div className={styles.panel} onClick={(e)=> e.stopPropagation()}>
        <div className={styles.header}>
          <h3>Scan Warps</h3>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>
        <div className={styles.grid}>
          {sectors.map((s, idx)=> (
            <button key={s.number} ref={idx===0?firstRef:null} className={[styles.cell, styles.visited].join(' ')} onClick={()=> onPick(s.number)} title={`Sector ${s.number}${s.port?.kind?` — Port: ${s.port.kind}`:''}${s.planetCount ? ` — Planets: ${s.planetCount}`:''}`}>
              <span className={styles.number}>{s.number}</span>
              {iconFor(s.port?.kind as any) && (
                <span className={styles.badgeBelow}>{iconFor(s.port?.kind as any)}</span>
              )}
              {s.planetCount && s.planetCount > 0 && (
                <span className={styles.planetCount}>🪐 {s.planetCount}</span>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}


