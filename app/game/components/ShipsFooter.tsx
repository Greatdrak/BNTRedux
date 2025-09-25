'use client'

import styles from '../page.module.css'

interface ShipsFooterProps {
  sectorNumber: number;
  ships: Array<{
    id: string;
    name: string;
    player: {
      handle: string;
      is_ai: boolean;
    };
  }>;
  currentPlayerShipId?: string;
  onShipClick?: (ship: any) => void;
}

export default function ShipsFooter({ sectorNumber, ships, currentPlayerShipId, onShipClick }: ShipsFooterProps) {
  const otherShips = ships.filter(ship => ship.id !== currentPlayerShipId)
  
  if (otherShips.length === 0) return null

  return (
    <div className={styles.shipsSectionBottom}>
      <h3>Other ships in sector {sectorNumber} ({otherShips.length})</h3>
      <div className={styles.shipCards}>
        {otherShips.slice(0, 5).map((ship: any) => (
          <div 
            key={ship.id} 
            className={`${styles.shipCard} ${onShipClick ? styles.clickable : ''}`}
            onClick={() => onShipClick?.(ship)}
          >
            <div className={styles.shipGraphic}>
              <div className={styles.shipImageContainer}>
                <img 
                  src="/images/ShipLevel1.png" 
                  alt="Ship" 
                  className={styles.shipImage}
                />
                {/* AI indicator */}
                {ship.player.is_ai && (
                  <div className={styles.aiIndicator}>AI</div>
                )}
              </div>
            </div>
            <div className={styles.shipInfo}>
              <div className={styles.shipName}>{ship.name}</div>
              <div className={`${styles.playerName} ${ship.player.is_ai ? styles.aiPlayer : styles.humanPlayer}`}>
                {ship.player.handle}
                {ship.player.is_ai && <span className={styles.aiTag}>[AI]</span>}
              </div>
            </div>
          </div>
        ))}
      </div>
      {otherShips.length > 5 && (
        <div className={styles.showAllShips}>
          <button className={styles.showAllBtn}>
            Show All Ships ({otherShips.length})
          </button>
        </div>
      )}
    </div>
  )
}
