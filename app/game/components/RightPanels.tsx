'use client'

import InventoryPanel from './InventoryPanel'
import HyperspacePanel from './HyperspacePanel'
import styles from '../page.module.css'

interface RightPanelsProps {
  // Inventory props
  inventory: any;
  inventoryLoading: boolean;
  
  // Hyperspace props
  engineLevel: number;
  currentSector: number;
  turns: number;
  targetSector: number;
  onTargetSectorChange: (sector: number) => void;
  onHyperspaceJump: (targetSector: number) => void;
  hyperLoading: boolean;
  
  // Navigation props
  onMapClick: () => void;
  onScanWarps: () => void;
  warps: number[];
  onWarpClick: (sectorNumber: number) => void;
  moveLoading: boolean;
  playerTurns: number;
}

export default function RightPanels({
  inventory,
  inventoryLoading,
  engineLevel,
  currentSector,
  turns,
  targetSector,
  onTargetSectorChange,
  onHyperspaceJump,
  hyperLoading,
  onMapClick,
  onScanWarps,
  warps,
  onWarpClick,
  moveLoading,
  playerTurns
}: RightPanelsProps) {
  return (
    <>
      <InventoryPanel inventory={inventory} loading={inventoryLoading} />

      <HyperspacePanel
        engineLvl={engineLevel}
        currentSector={currentSector}
        turns={turns}
        target={targetSector}
        onChangeTarget={onTargetSectorChange}
        onJump={onHyperspaceJump}
        loading={hyperLoading}
      />

      <div className={styles.sideCard}>
        <h3>Navigation</h3>
        
        {/* Navigation Actions */}
        <div className={styles.navActions}>
          <button className={styles.navBtn} onClick={onMapClick}>🗺️ Map</button>
          <button 
            className={styles.navBtn} 
            onClick={onScanWarps} 
            disabled={!playerTurns}
          >
            🔎 Scan Warps (-1)
          </button>
        </div>

        {/* Warp Gates */}
        {warps.length > 0 && (
          <div className={styles.warpSection}>
            <h4>Warp Gates</h4>
            <div className={styles.warpList}>
              {warps.map((warpNumber: number) => (
                <button
                  key={warpNumber}
                  onClick={() => onWarpClick(warpNumber)}
                  disabled={moveLoading || !playerTurns}
                  className={styles.warpGate}
                >
                  {moveLoading ? 'Moving...' : `=> ${warpNumber}`}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>
    </>
  )
}
