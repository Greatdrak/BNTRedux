'use client'

import { useEffect, useRef } from 'react'
import styles from './MapOverlay.module.css'

interface MapCell {
  number: number
  visited: boolean
  scanned: boolean
  portKind: 'ore'|'organics'|'goods'|'energy'|'special'|null
  hasPlanet: boolean
  planetOwned: boolean
}

interface MapOverlayProps {
  open: boolean
  onClose: () => void
  sectors: MapCell[]
  onPickTarget: (n: number) => void
  currentSector?: number
}

export default function MapOverlay({ open, onClose, sectors, onPickTarget, currentSector }: MapOverlayProps) {
  const firstRef = useRef<HTMLButtonElement|null>(null)

  useEffect(() => {
    if (open) {
      setTimeout(()=> firstRef.current?.focus(), 0)
      const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
      window.addEventListener('keydown', onKey)
      return () => window.removeEventListener('keydown', onKey)
    }
  }, [open, onClose])

  if (!open) return null

  const iconFor = (k: MapCell['portKind']) => {
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
          <h3>Map</h3>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>
        <div className={styles.grid}>
          {sectors.map((s, idx) => (
            <button
              key={s.number}
              ref={idx===0?firstRef:null}
              className={[
                styles.cell,
                s.visited?styles.visited:'',
                s.scanned?styles.scanned:'',
                !s.visited?styles.unvisited:''
              ].join(' ')}
              style={{ borderColor: s.visited? '#63e6be':'var(--line)' }}
              onClick={()=> onPickTarget(s.number)}
              title={`Sector ${s.number}${(s.visited||s.scanned) && s.portKind?` — Port: ${s.portKind}`:''}${(s.visited||s.scanned) && s.hasPlanet?` — Planet ${s.planetOwned?'(owned)':'(unowned)'}`:''}`}
            >
              <span className={styles.number}>{s.number}</span>
              <span className={styles.badgeBelow}>{(s.visited||s.scanned)? iconFor(s.portKind) : ''}</span>
              {(s.visited||s.scanned) && s.hasPlanet && (
                <span className={[styles.planetBadge, s.planetOwned ? styles.planetOwned : styles.planetUnowned].join(' ')}>
                  🪐
                </span>
              )}
              {currentSector === s.number && (
                <span className={styles.here}>You are here</span>
              )}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}


