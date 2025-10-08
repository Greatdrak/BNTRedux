'use client'

import styles from '../page.module.css'

interface CenterViewportProps {
  sector: {
    number: number;
  } | null;
  planets: Array<{
    id: string;
    name: string;
    ownerName?: string;
  }>;
  port: {
    kind: 'ore' | 'organics' | 'goods' | 'energy' | 'special';
  } | null;
  ships?: Array<{
    id: string;
    name: string;
    player?: { id?: string; handle?: string; is_ai?: boolean };
  }>;
  currentPlayerShipId?: string;
  onPlanetClick: (index: number) => void;
  onPortClick: () => void;
  onShipClick?: (ship: any) => void;
}

export default function CenterViewport({
  sector,
  planets,
  port,
  ships = [],
  currentPlayerShipId,
  onPlanetClick,
  onPortClick,
  onShipClick
}: CenterViewportProps) {
  // console.log('CenterViewport rendered:', { sector, planets, port })
  return (
    <div className={styles.centerArea}>
      <div className={styles.spaceViewport}>
        <div className={styles.viewportHeader}>
          <div className={styles.sectorTitle}>SECTOR</div>
          <div className={styles.sectorNumber}>
            {sector?.number ?? '--'}
          </div>
        </div>

        {/* Trading Port - Top Right */}
        {port ? (
          <div className={styles.portTopRight}>
            <span
              className={styles.portBadge}
              onClick={onPortClick}
            >
              {port.kind === 'ore' && '🪨 Ore'}
              {port.kind === 'organics' && '🌿 Organics'}
              {port.kind === 'goods' && '📦 Goods'}
              {port.kind === 'energy' && '⚡ Energy'}
              {port.kind === 'special' && '⭐ Special'}
            </span>
          </div>
        ) : null}
      </div>

      {/* Bottom section: Planets (left) and Ships (right) */}
      <div className={styles.bottomSection}>
        {/* Planets - Left */}
        {planets.length > 0 && (
          <div className={styles.planetsSection}>
            <div className={styles.sectionTitle}>Planets</div>
            <div className={styles.planetBelt}>
              {planets.map((planet: any, index: number) => (
                <div 
                  key={planet.id} 
                  className={styles.planetContainer}
                  onClick={() => onPlanetClick(index)}
                  style={{ cursor: 'pointer' }}
                >
                  <div className={styles.planetOrb} />
                  <div className={styles.planetLabel}>{planet.name}</div>
                  {planet.ownerName && (
                    <div className={styles.planetOwner}>Owner: {planet.ownerName}</div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Ships - Right */}
        {ships.filter(ship => ship.id !== currentPlayerShipId).length > 0 && (
          <div className={styles.shipsSection}>
            <div className={styles.sectionTitle}>Ships in Sector</div>
            <div className={styles.shipCards}>
              {ships.filter(ship => ship.id !== currentPlayerShipId).map((ship: any) => (
                <div 
                  key={ship.id} 
                  className={styles.shipCard}
                  onClick={() => onShipClick && onShipClick(ship)}
                  style={{ cursor: 'pointer' }}
                >
                  <div className={styles.shipGraphic}>
                    <div className={styles.shipImageContainer}>
                      <img className={styles.shipImage} src="/images/ShipLevel1.png" alt="ship" />
                    </div>
                  </div>
                  <div className={styles.shipInfo}>
                    <div className={styles.shipName}>{ship.name || 'Ship'}</div>
                    <div className={styles.playerName}>
                      {ship.player?.handle || (ship.player?.is_ai ? 'AI' : 'Unknown')}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
