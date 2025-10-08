'use client'

import { useEffect, useRef } from 'react'
import styles from './WarpScanOverlay.module.css'

interface WarpCell { number: number, port?: { kind: 'ore'|'organics'|'goods'|'energy'|'special' } | null, planetCount?: number, shipCount?: number, lastVisitorHandle?: string|null }

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
          <h3>📡 Scan Warps</h3>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>
        <div className={styles.scrollContainer}>
          <div className={styles.grid}>
            {sectors.map((s, idx)=> (
              <button 
                key={s.number} 
                ref={idx===0?firstRef:null} 
                className={styles.warpCard}
                onClick={()=> onPick(s.number)}
              >
                <div className={styles.cardHeader}>
                  <span className={styles.sectorNumber}>{s.number}</span>
                  {s.port?.kind && (
                    <span className={styles.portIcon}>{iconFor(s.port.kind)}</span>
                  )}
                </div>
                
                {s.port?.kind && (
                  <div className={styles.sectorName}>
                    {s.port.kind === 'ore' ? 'Ore Port' :
                     s.port.kind === 'organics' ? 'Organics Port' :
                     s.port.kind === 'goods' ? 'Goods Port' :
                     s.port.kind === 'energy' ? 'Energy Port' :
                     'Special Port'}
                  </div>
                )}

                <div className={styles.stats}>
                  {typeof s.shipCount === 'number' && (
                    <div className={`${styles.stat} ${styles.shipStat}`}>
                      <span className={styles.statIcon}>🚀</span>
                      <span className={styles.statLabel}>Ships</span>
                      <span className={styles.statValue}>{s.shipCount}</span>
                    </div>
                  )}
                  
                  {typeof s.planetCount === 'number' && (
                    <div className={`${styles.stat} ${styles.planetStat}`}>
                      <span className={styles.statIcon}>🪐</span>
                      <span className={styles.statLabel}>Planets</span>
                      <span className={styles.statValue}>{s.planetCount}</span>
                    </div>
                  )}
                  
                  {s.lastVisitorHandle && (
                    <div className={`${styles.stat} ${styles.visitorStat}`}>
                      <span className={styles.statIcon}>👤</span>
                      <span className={styles.statLabel}>Last Seen</span>
                      <span className={styles.statValue}>{s.lastVisitorHandle}</span>
                    </div>
                  )}
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}


