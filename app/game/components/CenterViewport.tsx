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
  onPlanetClick: (index: number) => void;
  onPortClick: () => void;
}

export default function CenterViewport({
  sector,
  planets,
  port,
  onPlanetClick,
  onPortClick
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

        {/* Planets */}
        {planets.length > 0 && (
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
        )}

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
    </div>
  )
}
