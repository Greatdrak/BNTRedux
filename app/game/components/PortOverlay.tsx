'use client'

import { useEffect, useRef } from 'react'
import styles from './PortOverlay.module.css'
import ActionsPanel from './ActionsPanel'
import { useState, useMemo } from 'react'

interface PortOverlayProps {
  open: boolean
  onClose: () => void
  port?: { 
    id: string; 
    kind: string;
    stock: { ore: number; organics: number; goods: number; energy: number };
    prices: { ore: number; organics: number; goods: number; energy: number };
  }
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
  
  // Special port state
  const [deviceQuantities, setDeviceQuantities] = useState<Record<string, number>>({})
  const [componentUpgrades, setComponentUpgrades] = useState<Record<string, number>>({})
  const [itemQuantities, setItemQuantities] = useState<Record<string, number>>({})
  const [totalCost, setTotalCost] = useState(0)

  // Special port data
  const devices = [
    { name: 'Genesis Torpedoes', cost: 1000000, current: 1, max: 49, type: 'quantity' },
    { name: 'Space Beacons', cost: 1000000, current: 0, max: 10, type: 'quantity' },
    { name: 'Emergency Warp Device', cost: 1000000, current: 1, max: 9, type: 'quantity' },
    { name: 'Warp Editors', cost: 1000000, current: 10, max: 0, type: 'quantity' },
    { name: 'Mine Deflectors', cost: 1000, current: 0, max: -1, type: 'quantity' },
    { name: 'Escape Pod', cost: 1000000, current: 1, max: 1, type: 'checkbox' },
    { name: 'Fuel Scoop', cost: 100000, current: 0, max: 1, type: 'checkbox' },
    { name: 'Last Ship Seen Device', cost: 10000000, current: 0, max: 1, type: 'checkbox' }
  ]

  const components = [
    { name: 'Hull', cost: 0, current: 0 },
    { name: 'Engines', cost: 0, current: 0 },
    { name: 'Power', cost: 0, current: 0 },
    { name: 'Computer', cost: 0, current: 0 },
    { name: 'Sensors', cost: 0, current: 0 },
    { name: 'Beam Weapons', cost: 0, current: 0 },
    { name: 'Armor', cost: 0, current: 0 },
    { name: 'Cloak', cost: 0, current: 0 },
    { name: 'Torpedo Launchers', cost: 0, current: 0 },
    { name: 'Shields', cost: 0, current: 0 }
  ]

  const items = [
    { name: 'Fighters', cost: 50, current: 10, max: 90 },
    { name: 'Armor Points', cost: 5, current: 10, max: 90 },
    { name: 'Torpedoes', cost: 25, current: 0, max: 100 },
    { name: 'Colonists', cost: 500, current: 0, max: 100 }
  ]

  useEffect(() => {
    if (!open) return
    setTimeout(()=> firstRef.current?.focus(), 0)
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  // Calculate total cost
  useEffect(() => {
    let cost = 0
    
    // Device costs
    devices.forEach(device => {
      const qty = deviceQuantities[device.name] || 0
      cost += qty * device.cost
    })
    
    // Component upgrade costs
    components.forEach(component => {
      const upgrade = componentUpgrades[component.name] || 0
      cost += upgrade * component.cost
    })
    
    // Item costs
    items.forEach(item => {
      const qty = itemQuantities[item.name] || 0
      cost += qty * item.cost
    })
    
    setTotalCost(cost)
  }, [deviceQuantities, componentUpgrades, itemQuantities])

  if (!open) return null

  const isSpecialPort = port?.kind === 'special'

  return (
    <div className={`${styles.backdrop} ${isSpecialPort ? styles.specialPort : ''}`} onClick={onClose}>
      <div className={styles.panel} onClick={(e)=> e.stopPropagation()}>
        <div className={styles.header}>
          <div className={styles.title}>
            {isSpecialPort ? 'Special Port' : 'Trading Port'}:
            {port?.kind && (
              <span className={styles.portBadge}>
                {port.kind === 'ore' && '🪨 Ore'}
                {port.kind === 'organics' && '🌿 Organics'}
                {port.kind === 'goods' && '📦 Goods'}
                {port.kind === 'energy' && '⚡ Energy'}
                {port.kind === 'special' && '⭐ Special'}
              </span>
            )}
          </div>
          <button className={styles.close} onClick={onClose} ref={firstRef}>✕</button>
        </div>
        
        {isSpecialPort ? (
          <SpecialPortContent 
            player={player}
            ship={ship}
            devices={devices}
            components={components}
            items={items}
            deviceQuantities={deviceQuantities}
            setDeviceQuantities={setDeviceQuantities}
            componentUpgrades={componentUpgrades}
            setComponentUpgrades={setComponentUpgrades}
            itemQuantities={itemQuantities}
            setItemQuantities={setItemQuantities}
            totalCost={totalCost}
          />
        ) : (
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
                <div>{renderRes('ore')}: {Number((port as any)?.ore ?? (port as any)?.stock?.ore ?? 0).toLocaleString()}</div>
                <div>{renderRes('organics')}: {Number((port as any)?.organics ?? (port as any)?.stock?.organics ?? 0).toLocaleString()}</div>
                <div>{renderRes('goods')}: {Number((port as any)?.goods ?? (port as any)?.stock?.goods ?? 0).toLocaleString()}</div>
                <div>{renderRes('energy')}: {Number((port as any)?.energy ?? (port as any)?.stock?.energy ?? 0).toLocaleString()}</div>
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
                    shipCredits={ship?.credits}
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
                    shipCredits={ship?.credits}
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
                      const creditsDelta = Number(res.credits) - Number(ship?.credits ?? 0)
                      setResult({ ...res, creditsDelta })
                    }
                  }}>Auto Trade</button>
                </div>
              )}
            </div>
          </div>
        )}
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

// Special Port Content Component
function SpecialPortContent({ 
  player, 
  ship, 
  devices, 
  components, 
  items, 
  deviceQuantities, 
  setDeviceQuantities, 
  componentUpgrades, 
  setComponentUpgrades, 
  itemQuantities, 
  setItemQuantities, 
  totalCost 
}: any) {
  return (
    <div className={styles.content}>
      {/* Credits Display */}
      <div className={styles.pane} style={{gridColumn:'1 / -1'}}>
        <div className={styles.paneTitle}>Credits Available</div>
        <div style={{fontSize: '16px', fontWeight: '600', color: '#fbbf24'}}>
          You have {Number(ship?.credits || 0).toLocaleString()} credits to spend.
        </div>
        <div style={{marginTop: '8px', display: 'flex', gap: '12px'}}>
          <a href="#" className={styles.specialLink}>IGB Banking Terminal</a>
          <a href="#" className={styles.specialLink}>Place or view bounties</a>
        </div>
      </div>

      {/* Devices Table */}
      <div className={styles.pane}>
        <div className={styles.paneTitle}>Devices</div>
        <table className={styles.deviceTable}>
          <thead>
            <tr>
              <th>Device</th>
              <th>Cost</th>
              <th>Current</th>
              <th>Max</th>
              <th>Quantity</th>
            </tr>
          </thead>
          <tbody>
            {devices.map((device: any) => (
              <tr key={device.name}>
                <td>{device.name}</td>
                <td className={styles.cost}>{device.cost.toLocaleString()}</td>
                <td>{device.current}</td>
                <td className={styles.maxValue}>
                  {device.max === -1 ? 'Unlimited' : device.max === 0 ? 'Full' : device.max}
                </td>
                <td>
                  {device.type === 'checkbox' ? (
                    <input 
                      type="checkbox" 
                      className={styles.deviceCheckbox}
                      checked={deviceQuantities[device.name] > 0}
                      onChange={(e) => setDeviceQuantities({
                        ...deviceQuantities,
                        [device.name]: e.target.checked ? 1 : 0
                      })}
                    />
                  ) : (
                    <input 
                      type="number" 
                      className={styles.quantityInput}
                      value={deviceQuantities[device.name] || 0}
                      onChange={(e) => setDeviceQuantities({
                        ...deviceQuantities,
                        [device.name]: Math.max(0, parseInt(e.target.value) || 0)
                      })}
                      min="0"
                      max={device.max === -1 ? undefined : device.max}
                    />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Ship Component Levels */}
      <div className={styles.pane}>
        <div className={styles.paneTitle}>Ship Component Levels</div>
        <table className={styles.componentTable}>
          <thead>
            <tr>
              <th>Component</th>
              <th>Cost</th>
              <th>Current</th>
              <th>Upgrade?</th>
            </tr>
          </thead>
          <tbody>
            {components.map((component: any) => (
              <tr key={component.name}>
                <td>{component.name}</td>
                <td className={styles.cost}>{component.cost.toLocaleString()}</td>
                <td>{component.current}</td>
                <td>
                  <select 
                    className={styles.quantityInput}
                    value={componentUpgrades[component.name] || 0}
                    onChange={(e) => setComponentUpgrades({
                      ...componentUpgrades,
                      [component.name]: parseInt(e.target.value) || 0
                    })}
                  >
                    {[0,1,2,3,4,5].map(level => (
                      <option key={level} value={level}>{level}</option>
                    ))}
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Items - Left Column */}
      <div className={styles.pane}>
        <div className={styles.paneTitle}>Items</div>
        <table className={styles.deviceTable}>
          <thead>
            <tr>
              <th>Item</th>
              <th>Cost</th>
              <th>Current</th>
              <th>Max</th>
              <th>Quantity</th>
            </tr>
          </thead>
          <tbody>
            {items.slice(0, 2).map((item: any) => (
              <tr key={item.name}>
                <td>{item.name}</td>
                <td className={styles.cost}>{item.cost.toLocaleString()}</td>
                <td>{item.current} / {item.max + item.current}</td>
                <td className={styles.maxValue}>{item.max}</td>
                <td>
                  <input 
                    type="number" 
                    className={styles.quantityInput}
                    value={itemQuantities[item.name] || 0}
                    onChange={(e) => setItemQuantities({
                      ...itemQuantities,
                      [item.name]: Math.max(0, parseInt(e.target.value) || 0)
                    })}
                    min="0"
                    max={item.max}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Items - Right Column */}
      <div className={styles.pane}>
        <div className={styles.paneTitle}>Items</div>
        <table className={styles.deviceTable}>
          <thead>
            <tr>
              <th>Item</th>
              <th>Cost</th>
              <th>Current</th>
              <th>Max</th>
              <th>Quantity</th>
            </tr>
          </thead>
          <tbody>
            {items.slice(2).map((item: any) => (
              <tr key={item.name}>
                <td>{item.name}</td>
                <td className={styles.cost}>{item.cost.toLocaleString()}</td>
                <td>{item.current} / {item.max + item.current}</td>
                <td className={styles.maxValue}>{item.max}</td>
                <td>
                  <input 
                    type="number" 
                    className={styles.quantityInput}
                    value={itemQuantities[item.name] || 0}
                    onChange={(e) => setItemQuantities({
                      ...itemQuantities,
                      [item.name]: Math.max(0, parseInt(e.target.value) || 0)
                    })}
                    min="0"
                    max={item.max}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Buy Button and Total Cost */}
      <div className={styles.pane} style={{gridColumn:'1 / -1'}}>
        <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
          <button 
            className={styles.buyButton}
            disabled={totalCost === 0 || totalCost > (ship?.credits || 0)}
          >
            Buy
          </button>
          <div className={styles.totalCost}>
            <span className={styles.totalCostLabel}>Total cost:</span>
            <span className={styles.totalCostValue}>{totalCost.toLocaleString()}</span>
          </div>
        </div>
        
        <div style={{marginTop: '12px', display: 'flex', gap: '12px'}}>
          <a href="#" className={styles.specialLink}>If you would like to dump all your colonists here, click here.</a>
        </div>
        <div style={{marginTop: '8px'}}>
          <a href="#" className={styles.specialLink}>Click here to return to the main menu.</a>
        </div>
      </div>
    </div>
  )
}


