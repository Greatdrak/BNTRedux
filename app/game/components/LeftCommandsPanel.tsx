'use client'

import styles from '../page.module.css'

interface LeftCommandsPanelProps {
  tradeRoutes: any[];
  onCommandClick: (command: string) => void;
  onTradeRouteClick: (routeId: string) => void;
  onTradeRouteExecute: (routeId: string) => void;
  currentSector: number;
  playerTurns: number;
  onTravelToSector: (sector: number, type: 'warp' | 'realspace') => void;
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
          onClick={() => onCommandClick('genesis')}
        >
          ⚠️ Genesis
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('activity')}
        >
          📝 Player Logs
        </button>
        <button 
          className={styles.commandItem}
          onClick={() => onCommandClick('new-player-guide')}
        >
          📚 New Player Guide
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
                  <button className={styles.routeNameBtn} onClick={() => onTradeRouteClick(route.id)}>
                    {route.name}
                  </button>
                  <span className={styles.routeProfit} title="Profit per Turn">P/T {route.current_profit_per_turn ? route.current_profit_per_turn.toLocaleString() : '—'}</span>
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
                          onTravelToSector(waypoint.port_info?.sector_number, 'realspace')
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

                {/* Quick execute presets */}
                {route.waypoints[0]?.port_info?.sector_number === currentSector ? (
                  <div className={styles.segmentGroup}>
                    {[1,5,10,20,50].map((iters) => (
                      <button
                        key={iters}
                        className={styles.segmentBtn}
                        disabled={!playerTurns}
                        onClick={() => {
                          if (iters === 1) return onTradeRouteExecute(route.id)
                          onTradeRouteExecute(`${route.id}|${iters}` as unknown as string)
                        }}
                        title={iters === 1 ? 'Execute once' : `Execute x${iters}`}
                      >
                        {iters === 1 ? 'Execute' : `x${iters}`}
                      </button>
                    ))}
                  </div>
                ) : (
                  <div className={styles.hintText}>Move to start sector to execute</div>
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
