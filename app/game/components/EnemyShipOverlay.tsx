'use client'

import React, { useState, useEffect } from 'react'
import styles from './EnemyShipOverlay.module.css'

interface EnemyShip {
  id: string
  name: string
  player_handle: string
  hull?: number
  hull_max?: number
  shield?: number
  shield_max?: number
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

interface EnemyShipOverlayProps {
  open: boolean
  onClose: () => void
  enemyShip: EnemyShip | null
  currentPlayerTurns: number
  onScanShip: (shipId: string) => Promise<{ success: boolean; data?: any; error?: string }>
  onAttackShip: (shipId: string, scannedData?: any) => void
}

export default function EnemyShipOverlay({
  open,
  onClose,
  enemyShip,
  currentPlayerTurns,
  onScanShip,
  onAttackShip
}: EnemyShipOverlayProps) {
  const [scanData, setScanData] = useState<EnemyShip | null>(null)
  const [scanAttempted, setScanAttempted] = useState(false)
  const [scanning, setScanning] = useState(false)
  const [scanResult, setScanResult] = useState<'none' | 'partial' | 'full' | 'failure'>('none')

  // Reset scan state when enemyShip changes
  useEffect(() => {
    if (enemyShip) {
      setScanData(null)
      setScanAttempted(false)
      setScanning(false)
      setScanResult('none')
    }
  }, [enemyShip?.id])

  if (!open || !enemyShip) return null

  const handleScanShip = async () => {
    if (scanning || currentPlayerTurns < 1) return
    
    setScanning(true)
    try {
      const result = await onScanShip(enemyShip.id)
      
      if (result.success && result.data) {
        // Merge new scan data with existing data
        const newScanData = { ...scanData, ...result.data.scanned_data }
        
        setScanData(newScanData)
        setScanAttempted(true)
        setScanResult(result.data.scan_type || 'partial')
      } else {
        setScanAttempted(true)
        setScanResult('failure')
      }
    } catch (error) {
      setScanAttempted(true)
      setScanResult('failure')
    } finally {
      setScanning(false)
    }
  }

  const renderDataPoint = (label: string, value: any, key: string) => {
    if (!scanAttempted) {
      return <div className={styles.dataItem}><span>{label}</span><span className={styles.unknown}>???</span></div>
    }

    if (scanResult === 'failure') {
      return <div className={styles.dataItem}><span>{label}</span><span className={styles.failed}>SCAN FAILED</span></div>
    }

    // Check if we have data for this specific key
    const hasData = scanData && (scanData as any)[key] !== undefined && (scanData as any)[key] !== null
    
    if (hasData) {
      // Show the actual scanned data
      const displayValue = typeof value === 'number' ? value.toLocaleString() : (scanData as any)[key]
      return <div className={styles.dataItem}><span>{label}</span><span className={styles.success}>{displayValue}</span></div>
    } else {
      // No data available for this key
      return <div className={styles.dataItem}><span>{label}</span><span className={styles.unknown}>???</span></div>
    }
  }

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>Enemy Ship Report</h2>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>

        <div className={styles.content}>
          <div className={styles.shipInfo}>
            <h3>{enemyShip.name}</h3>
            <p className={styles.playerName}>Pilot: {enemyShip.player_handle}</p>
          </div>

          {!scanAttempted && (
            <div className={styles.scanPrompt}>
              <p>This ship's data is encrypted. Use your ship's sensors to scan for information.</p>
              <button 
                className={styles.scanBtn}
                onClick={handleScanShip}
                disabled={scanning || currentPlayerTurns < 1}
              >
                {scanning ? 'Scanning...' : `Scan Ship (1 Turn)`}
              </button>
              {currentPlayerTurns < 1 && (
                <p className={styles.noTurns}>Insufficient turns to scan</p>
              )}
            </div>
          )}

          {scanAttempted && (
            <div className={styles.scanResults}>
              <div className={styles.scanStatus}>
                {scanResult === 'failure' && (
                  <div className={styles.statusFailure}>
                    <h4>❌ Scan Failed</h4>
                    <p>Your sensors were unable to penetrate the enemy's defenses.</p>
                  </div>
                )}
                {scanResult === 'partial' && (
                  <div className={styles.statusPartial}>
                    <h4>⚠️ Partial Scan Success</h4>
                    <p>Your sensors gathered some data, but the enemy's cloak interfered with the scan.</p>
                  </div>
                )}
                {scanResult === 'full' && (
                  <div className={styles.statusSuccess}>
                    <h4>✅ Full Scan Success</h4>
                    <p>Your sensors successfully penetrated all enemy defenses.</p>
                  </div>
                )}
                
                {/* Action buttons - always show after first scan */}
                <div className={styles.actionSection}>
                  <div className={styles.buttonRow}>
                    <button 
                      className={styles.rescanBtn}
                      onClick={handleScanShip}
                      disabled={scanning || currentPlayerTurns < 1}
                    >
                      {scanning ? 'Scanning...' : `Rescan Ship (1 Turn)`}
                    </button>
                    <button 
                      className={styles.attackBtn}
                      onClick={() => onAttackShip(enemyShip.id, scanData)}
                      disabled={currentPlayerTurns < 1}
                    >
                      Attack Ship
                    </button>
                  </div>
                  {currentPlayerTurns < 1 && (
                    <p className={styles.noTurns}>Insufficient turns for actions</p>
                  )}
                </div>
              </div>

              <div className={styles.shipData}>
                <div className={styles.section}>
                  <h4>Ship Systems</h4>
                  {renderDataPoint('Hull', `${scanData?.hull || 0} / ${scanData?.hull_max || 0}`, 'hull')}
                  {renderDataPoint('Shield', `${scanData?.shield || 0} / ${scanData?.shield_max || 0}`, 'shield')}
                  {renderDataPoint('Energy', `${scanData?.energy || 0} / ${scanData?.energy_max || 0}`, 'energy')}
                </div>

                <div className={styles.section}>
                  <h4>Weapons & Defenses</h4>
                  {renderDataPoint('Fighters', scanData?.fighters || 0, 'fighters')}
                  {renderDataPoint('Torpedoes', scanData?.torpedoes || 0, 'torpedoes')}
                  {renderDataPoint('Armor Points', scanData?.armor || 0, 'armor')}
                  {renderDataPoint('Armor Level', scanData?.armor_lvl || 0, 'armor_lvl')}
                </div>

                <div className={styles.section}>
                  <h4>Tech Levels</h4>
                  {renderDataPoint('Engine', scanData?.engine_lvl || 0, 'engine_lvl')}
                  {renderDataPoint('Computer', scanData?.comp_lvl || 0, 'comp_lvl')}
                  {renderDataPoint('Sensors', scanData?.sensor_lvl || 0, 'sensor_lvl')}
                  {renderDataPoint('Power', scanData?.power_lvl || 0, 'power_lvl')}
                  {renderDataPoint('Beam Weapons', scanData?.beam_lvl || 0, 'beam_lvl')}
                  {renderDataPoint('Torpedo Launcher', scanData?.torp_launcher_lvl || 0, 'torp_launcher_lvl')}
                  {renderDataPoint('Cloak', scanData?.cloak_lvl || 0, 'cloak_lvl')}
                </div>

                <div className={styles.section}>
                  <h4>Cargo & Resources</h4>
                  {renderDataPoint('Credits', scanData?.credits || 0, 'credits')}
                  {renderDataPoint('Ore', scanData?.ore || 0, 'ore')}
                  {renderDataPoint('Organics', scanData?.organics || 0, 'organics')}
                  {renderDataPoint('Goods', scanData?.goods || 0, 'goods')}
                  {renderDataPoint('Colonists', scanData?.colonists || 0, 'colonists')}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
