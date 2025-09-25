'use client'

import styles from '../page.module.css'

interface LeftCommandsPanelProps {
  tradeRoutes: any[];
  onCommandClick: (command: string) => void;
  onTradeRouteClick: (routeId: string) => void;
  onTradeRouteExecute: (routeId: string) => void;
  currentSector: number;
  playerTurns: number;
  onTravelToSector: (sector: number, type: 'warp') => void;
}

export default function LeftCommandsPanel({
  tradeRoutes,
  onCommandClick,
  onTradeRouteClick,
  onTradeRouteExecute,
  currentSector,
  playerTurns,
  onTravelToSector
}: LeftCommandsPanelProps) {
  return (
    <div className={styles.commandsBox}>
      <h3>Commands</h3>
      <div className={styles.commandList}>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('ship')}
        >
          🚀 Ship
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('leaderboard')}
        >
          🏆 Leaderboard
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('trade-routes')}
        >
          🤝 Trade Routes
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('planets')}
        >
          🪐 Planets
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('admin')}
        >
          ⚙️ Admin
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('favorite-sector')}
        >
          ⭐ Favorite Sector
        </button>
      </div>

      {/* Trade Routes Section */}
      <div className={styles.tradeRoutesSection}>
        <h3>Trade Routes</h3>
        {tradeRoutes.length > 0 ? (
          <div className={styles.tradeRoutesList}>
            {tradeRoutes.slice(0, 5).map((route: any) => (
              <div key={route.id} className={styles.routeItem}>
                <div className={styles.routeHeader}>
                  <span className={styles.routeName}>{route.name}</span>
                  <span className={styles.routeProfit}>
                    +{route.total_profit?.toLocaleString() || 0}
                  </span>
                </div>
                
                <div className={styles.routeWaypoints}>
                  {route.waypoints.slice(0, 2).map((waypoint: any) => (
                    <button
                      key={`${route.id}-${waypoint.id}`}
                      className={`${styles.sectorBtn} ${
                        waypoint.port_info?.sector_number === currentSector ? styles.currentSector : ''
                      }`}
                      onClick={() => {
                        if (waypoint.port_info?.sector_number !== currentSector) {
                          onTravelToSector(waypoint.port_info?.sector_number, 'warp')
                        }
                      }}
                      title={`Travel to Sector ${waypoint.port_info?.sector_number}`}
                    >
                      S{waypoint.port_info?.sector_number}
                    </button>
                  ))}
                  {route.waypoints.length > 2 && (
                    <span className={styles.moreSectors}>+{route.waypoints.length - 2}</span>
                  )}
                </div>
                
                {/* Execute button only if in first sector */}
                {route.waypoints[0]?.port_info?.sector_number === currentSector && (
                  <button 
                    className={styles.executeBtn}
                    onClick={() => onTradeRouteExecute(route.id)}
                    disabled={!playerTurns}
                  >
                    ▶️ Execute
                  </button>
                )}
              </div>
            ))}
            {tradeRoutes.length > 5 && (
              <p className={styles.moreRoutes}>+{tradeRoutes.length - 5} more</p>
            )}
          </div>
        ) : (
          <p className={styles.noRoutes}>None</p>
        )}
      </div>
    </div>
  )
}
