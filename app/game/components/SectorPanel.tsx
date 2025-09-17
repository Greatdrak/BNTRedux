'use client'

import styles from './SectorPanel.module.css'

interface SectorPanelProps {
  sectorNumber?: number
  warps?: number[]
  onMove: (toSector: number) => void
  moveLoading?: boolean
  turns?: number
  loading?: boolean
  planet?: {
    id: string
    name: string
    owner: boolean
  } | null
  playerCredits?: number
  playerTurns?: number
  onClaimPlanet?: () => void
  onManagePlanet?: () => void
}

export default function SectorPanel({ 
  sectorNumber, 
  warps, 
  onMove, 
  moveLoading, 
  turns,
  loading,
  planet,
  playerCredits,
  playerTurns,
  onClaimPlanet,
  onManagePlanet
}: SectorPanelProps) {
  if (loading) {
    return (
      <div className={styles.panel}>
        <h2>Loading sector...</h2>
      </div>
    )
  }

  return (
    <div className={styles.panel}>
      <h2>Sector {sectorNumber || '--'}</h2>
      
      <div className={styles.warps}>
        <h3>Warp Gates</h3>
        <div className={styles.warpButtons}>
          {warps?.map((warpNumber) => (
            <button
              key={warpNumber}
              onClick={() => onMove(warpNumber)}
              disabled={moveLoading || !turns}
              className={styles.warpBtn}
            >
              {moveLoading ? 'Moving...' : `→ ${warpNumber}`}
            </button>
          ))}
        </div>
        {(!warps || warps.length === 0) && (
          <p className={styles.noWarps}>No warp gates available</p>
        )}
      </div>

      {planet && (
        <div className={styles.planet}>
          <h3>🪐 Planet: {planet.name}</h3>
          {planet.owner ? (
            <button 
              className={styles.manageBtn}
              onClick={onManagePlanet}
            >
              Manage Planet
            </button>
          ) : (
            <p className={styles.unowned}>Planet (unowned)</p>
          )}
        </div>
      )}

      {!planet && onClaimPlanet && (
        <div className={styles.planet}>
          <h3>🪐 No Planet</h3>
          <button 
            className={styles.claimBtn}
            onClick={onClaimPlanet}
            disabled={!playerCredits || playerCredits < 10000 || !playerTurns || playerTurns < 5}
          >
            Claim Planet
          </button>
          <p className={styles.costHint}>
            Costs: 10,000 credits + 5 turns
          </p>
        </div>
      )}
    </div>
  )
}
