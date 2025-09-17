'use client'

import { useEffect, useRef } from 'react'
import styles from './PortOverlay.module.css'
import ActionsPanel from './ActionsPanel'
import { useState, useMemo } from 'react'

interface PortOverlayProps {
  open: boolean
  onClose: () => void
  port?: { id: string; kind: string }
  player?: any
  ship?: any
  inventory?: any
  onTrade?: (data: { action: string; resource: string; qty: number }) => void
  tradeLoading?: boolean
  onAutoTrade?: () => Promise<any>
}

export default function PortOverlay({ open, onClose, port, player, ship, inventory, onTrade, tradeLoading, onAutoTrade }: PortOverlayProps) {
  const [mode, setMode] = useState<'buy'|'sell'|'trade'>('buy')
  const native = (port?.kind||'ore') as 'ore'|'organics'|'goods'|'energy'
  const nonNatives = useMemo(()=>(['ore','organics','goods','energy'].filter(r=> r!== native)) as Array<'ore'|'organics'|'goods'|'energy'>,[native])
  const firstRef = useRef<HTMLButtonElement|null>(null)
  const [result, setResult] = useState<any>(null)

  useEffect(() => {
    if (!open) return
    setTimeout(()=> firstRef.current?.focus(), 0)
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div className={styles.panel} onClick={(e)=> e.stopPropagation()}>
        <div className={styles.header}>
          <div className={styles.title}>Trading Port: {port?.kind ?? '-'}</div>
          <button className={styles.close} onClick={onClose} ref={firstRef}>✕</button>
        </div>
        <div className={styles.content}>
          {result && (
            <div className={`${styles.result} ${Number(result.creditsDelta||0) >= 0 ? styles.gain : styles.loss}`} style={{gridColumn:'1 / -1'}}>
              <div>
                Credits {Number(result.creditsDelta||0) >= 0 ? '+' : ''}{Number(result.creditsDelta||0).toLocaleString()}
              </div>
              <div className={styles.recap}>
                {renderRecap(result)}
              </div>
            </div>
          )}
          {/* Stock summary */}
          <div className={styles.pane} style={{gridColumn:'1 / -1'}}>
            <div className={styles.paneTitle}>Stock</div>
            <div style={{display:'grid',gridTemplateColumns:'repeat(4,1fr)',gap:8}}>
              <div>{renderRes('ore')}: {String((port as any)?.ore ?? (port as any)?.stock?.ore ?? 0)}</div>
              <div>{renderRes('organics')}: {String((port as any)?.organics ?? (port as any)?.stock?.organics ?? 0)}</div>
              <div>{renderRes('goods')}: {String((port as any)?.goods ?? (port as any)?.stock?.goods ?? 0)}</div>
              <div>{renderRes('energy')}: {String((port as any)?.energy ?? (port as any)?.stock?.energy ?? 0)}</div>
            </div>
          </div>
          {/* Stacked trading panel */}
          <div className={styles.pane} style={{gridColumn:'1 / -1'}}>
            <div className={styles.paneTitle}>Trading Port: {port?.kind?.toUpperCase()}</div>
            <div className={styles.segmented} role="tablist" aria-label="Trade mode">
              <button className={`${styles.segBtn} ${mode==='buy'?styles.segActive:''}`} onClick={()=> setMode('buy')}>Buy</button>
              <button className={`${styles.segBtn} ${mode==='sell'?styles.segActive:''}`} onClick={()=> setMode('sell')}>Sell</button>
              <button className={`${styles.segBtn} ${mode==='trade'?styles.segActive:''}`} onClick={()=> setMode('trade')}>Trade</button>
            </div>

            {mode==='buy' && (
              <div style={{marginTop:10}}>
                <ActionsPanel
                  port={port}
                  player={player}
                  ship={ship}
                  inventory={inventory}
                  onTrade={(d)=> onTrade && onTrade(d)}
                  tradeLoading={tradeLoading}
                  lockAction={'buy'}
                  allowedResources={[native]}
                  defaultResource={native}
                />
              </div>
            )}

            {mode==='sell' && (
              <div style={{marginTop:10}}>
                <ActionsPanel
                  port={port}
                  player={player}
                  ship={ship}
                  inventory={inventory}
                  onTrade={(d)=> onTrade && onTrade(d)}
                  tradeLoading={tradeLoading}
                  lockAction={'sell'}
                  allowedResources={nonNatives}
                  defaultResource={nonNatives[0]}
                />
              </div>
            )}

            {mode==='trade' && (
              <div style={{marginTop:10}} className={styles.stack}>
                <div className={`${styles.row} ${styles.muted}`}>Will sell: all non-{renderRes(native)}</div>
                <div className={`${styles.row}`}><span>Will buy:</span> <span className={styles.accent}>{renderRes(native)}</span></div>
                <div className={styles.row}><span>Preview updates after trade</span></div>
                <button className={`${styles.btn} ${styles.btnPrimary}`} onClick={async()=>{
                  if (!onAutoTrade) return
                  const res = await onAutoTrade()
                  if (res && !res.error) {
                    const creditsDelta = Number(res.credits) - Number(player?.credits ?? 0)
                    setResult({ ...res, creditsDelta })
                  }
                }}>Auto Trade</button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

function renderRes(kind: 'ore'|'organics'|'goods'|'energy'|string) {
  const icon = kind==='ore'?'🪨': kind==='organics'?'🌿': kind==='goods'?'📦':'⚡'
  const name = kind.charAt(0).toUpperCase()+kind.slice(1)
  return (
    <span className={styles.res}><span className={styles.resIcon}>{icon}</span><span className={styles.resName}>{name}</span></span>
  )
}

function renderRecap(result: any) {
  const sold = result?.sold || {}
  const bought = result?.bought || {}
  const parts: string[] = []
  ;(['ore','organics','goods','energy'] as const).forEach((k)=>{
    const s = Number(sold[k]||0)
    if (s>0) parts.push(`${capitalize(k)} -${s}`)
  })
  if (bought?.resource && bought?.qty) {
    parts.push(`${capitalize(bought.resource)} +${bought.qty}`)
  }
  return <span>{parts.join('  •  ')}</span>
}

function capitalize(t: string){ return t.charAt(0).toUpperCase()+t.slice(1) }


