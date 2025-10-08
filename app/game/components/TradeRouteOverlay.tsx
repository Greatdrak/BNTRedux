'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@supabase/supabase-js'
import styles from './TradeRouteOverlay.module.css'

interface TradeRouteOverlayProps {
  open: boolean
  onClose: () => void
  universeId: string
  onRouteChange?: () => void
  onTravelToSector?: (sectorNumber: number, travelType: 'warp' | 'realspace') => void
}

interface TradeRoute {
  id: string
  name: string
  description: string
  is_active: boolean
  is_automated: boolean
  max_iterations: number
  current_iteration: number
  total_profit: number
  total_turns_spent: number
  waypoint_count: number
  current_profit_per_turn: number
  created_at: string
  updated_at: string
  last_executed_at: string
  waypoints: Waypoint[]
}

interface Waypoint {
  id: string
  sequence_order: number
  port_id: string
  action_type: 'buy' | 'sell' | 'trade_auto'
  resource: string
  quantity: number
  notes: string
  port_info: {
    sector_number: number
    port_kind: string
  }
}

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

export default function TradeRouteOverlay({ open, onClose, universeId, onRouteChange, onTravelToSector }: TradeRouteOverlayProps) {
  const [routes, setRoutes] = useState<TradeRoute[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [newRouteName, setNewRouteName] = useState('')
  const [newRouteDescription, setNewRouteDescription] = useState('')
  const [selectedRoute, setSelectedRoute] = useState<TradeRoute | null>(null)
  const [showRouteDetails, setShowRouteDetails] = useState(false)
  
  // New state for sector selection and port validation
  const [fromSector, setFromSector] = useState('')
  const [toSector, setToSector] = useState('')
  const [fromPort, setFromPort] = useState<any>(null)
  const [toPort, setToPort] = useState<any>(null)
  const [validatingPorts, setValidatingPorts] = useState(false)
  const [portValidationError, setPortValidationError] = useState<string | null>(null)
  const [movementType, setMovementType] = useState<'warp' | 'realspace'>('warp')
  const [connectionValid, setConnectionValid] = useState<boolean | null>(null)

  useEffect(() => {
    if (open && universeId) {
      fetchRoutes()
    }
  }, [open, universeId])

  const fetchRoutes = async () => {
    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/trade-routes?universe_id=${universeId}`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch trade routes')
      }

      const data = await response.json()
      if (data.ok) {
        setRoutes(data.routes || [])
      } else {
        throw new Error(data.error?.message || 'Failed to load trade routes')
      }
    } catch (err) {
      console.error('Error fetching trade routes:', err)
      setError(err instanceof Error ? err.message : 'Failed to load trade routes')
    } finally {
      setLoading(false)
    }
  }

  const validatePorts = async () => {
    if (!fromSector.trim() || !toSector.trim()) {
      setPortValidationError('Please enter both from and to sectors')
      return false
    }

    const fromSectorNum = parseInt(fromSector)
    const toSectorNum = parseInt(toSector)

    if (isNaN(fromSectorNum) || isNaN(toSectorNum)) {
      setPortValidationError('Sector numbers must be valid integers')
      return false
    }

    if (fromSectorNum === toSectorNum) {
      setPortValidationError('From and to sectors must be different')
      return false
    }

    try {
      setValidatingPorts(true)
      setPortValidationError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return false

      // Check from sector port
      const fromResponse = await fetch(`/api/sector?number=${fromSectorNum}&universe_id=${universeId}`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!fromResponse.ok) {
        throw new Error('Failed to validate from sector')
      }

      const fromData = await fromResponse.json()
      if (!fromData.port) {
        setPortValidationError(`No port found in sector ${fromSectorNum}`)
        return false
      }

      // Check to sector port
      const toResponse = await fetch(`/api/sector?number=${toSectorNum}&universe_id=${universeId}`, {
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!toResponse.ok) {
        throw new Error('Failed to validate to sector')
      }

      const toData = await toResponse.json()
      if (!toData.port) {
        setPortValidationError(`No port found in sector ${toSectorNum}`)
        return false
      }

      // Validate port types (both must be commodity ports, not special)
      if (fromData.port.kind === 'special') {
        setPortValidationError(`Sector ${fromSectorNum} has a Special port - cannot trade commodities`)
        return false
      }

      if (toData.port.kind === 'special') {
        setPortValidationError(`Sector ${toSectorNum} has a Special port - cannot trade commodities`)
        return false
      }

      // Check sector connection based on movement type
      let hasConnection = false
      if (movementType === 'warp') {
        // Check for warp connection
        hasConnection = await checkWarpConnection(fromSectorNum, toSectorNum, session.access_token)
      } else {
        // For realspace, we'll allow any connection (distance-based turn calculation)
        hasConnection = true
      }

      if (!hasConnection) {
        setPortValidationError(`No ${movementType} connection found between sectors ${fromSectorNum} and ${toSectorNum}`)
        setConnectionValid(false)
        return false
      }

      // Store port info for route creation
      setFromPort(fromData.port)
      setToPort(toData.port)
      setConnectionValid(true)

      return true
    } catch (err) {
      console.error('Error validating ports:', err)
      setPortValidationError(err instanceof Error ? err.message : 'Failed to validate ports')
      return false
    } finally {
      setValidatingPorts(false)
    }
  }

  const checkWarpConnection = async (fromSector: number, toSector: number, accessToken: string): Promise<boolean> => {
    try {
      // Check if there's a warp connection between the sectors
      const response = await fetch(`/api/sector?number=${fromSector}&universe_id=${universeId}`, {
        headers: { 'Authorization': `Bearer ${accessToken}` }
      })
      
      const data = await response.json()
      
      // Look for the target sector in the warps array (it's just sector numbers, not objects)
      return data.warps?.includes(toSector) || false
    } catch (err) {
      console.error('Error checking warp connection:', err)
      return false
    }
  }

  const createRoute = async () => {
    if (!newRouteName.trim()) return

    // Validate ports first
    const portsValid = await validatePorts()
    if (!portsValid) return

    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch('/api/trade-routes', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          universe_id: universeId,
          name: newRouteName.trim(),
          description: newRouteDescription.trim() || null
        })
      })

      if (!response.ok) {
        throw new Error('Failed to create trade route')
      }

      const data = await response.json()
      if (data.ok) {
        // Add waypoints to the route
        await addWaypointsToRoute(data.route_id)
        
        setNewRouteName('')
        setNewRouteDescription('')
        setFromSector('')
        setToSector('')
        setFromPort(null)
        setToPort(null)
        setShowCreateForm(false)
        await fetchRoutes()
        onRouteChange?.()
      } else {
        throw new Error(data.error?.message || 'Failed to create trade route')
      }
    } catch (err) {
      console.error('Error creating trade route:', err)
      setError(err instanceof Error ? err.message : 'Failed to create trade route')
    } finally {
      setLoading(false)
    }
  }

  const addWaypointsToRoute = async (routeId: string) => {
    if (!fromPort || !toPort) return

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      // Add start port waypoint (first)
      await fetch(`/api/trade-routes/${routeId}/waypoints`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          port_id: fromPort.id,
          action_type: 'trade_auto',
          resource_type: fromPort.kind,
          quantity: 0
        })
      })

      // Add target port waypoint (second)
      await fetch(`/api/trade-routes/${routeId}/waypoints`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          port_id: toPort.id,
          action_type: 'trade_auto',
          resource_type: toPort.kind,
          quantity: 0
        })
      })
    } catch (err) {
      console.error('Error adding waypoints:', err)
    }
  }

  const deleteRoute = async (routeId: string) => {
    if (!confirm('Are you sure you want to delete this trade route?')) return

    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/trade-routes/${routeId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to delete trade route')
      }

      const data = await response.json()
      if (data.ok) {
        await fetchRoutes()
        onRouteChange?.()
      } else {
        throw new Error(data.error?.message || 'Failed to delete trade route')
      }
    } catch (err) {
      console.error('Error deleting trade route:', err)
      setError(err instanceof Error ? err.message : 'Failed to delete trade route')
    } finally {
      setLoading(false)
    }
  }

  const calculateProfitability = async (routeId: string) => {
    try {
      setLoading(true)
      setError(null)
      
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      const response = await fetch(`/api/trade-routes/${routeId}/calculate`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${session.access_token}`
        }
      })

      if (!response.ok) {
        throw new Error('Failed to calculate profitability')
      }

      const data = await response.json()
      if (data.ok) {
        await fetchRoutes() // Refresh to show updated profitability
      } else {
        throw new Error(data.error?.message || 'Failed to calculate profitability')
      }
    } catch (err) {
      console.error('Error calculating profitability:', err)
      setError(err instanceof Error ? err.message : 'Failed to calculate profitability')
    } finally {
      setLoading(false)
    }
  }

  const executeRoute = async (routeId: string, iterations: number = 1) => {
    try {
      setLoading(true)
      setError(null)
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) return

      // Add timeout to prevent hanging
      const controller = new AbortController()
      const timeoutId = setTimeout(() => controller.abort(), 30000)

      const response = await fetch(`/api/trade-routes/${routeId}/execute`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ 
          max_iterations: iterations,
          universe_id: universeId
        }),
        signal: controller.signal
      })
      clearTimeout(timeoutId)
      if (!response.ok) throw new Error('Failed to execute trade route')
      const data = await response.json()
      if (data.ok) {
        await fetchRoutes()
        onRouteChange?.()
      } else {
        throw new Error(data.error?.message || 'Failed to execute trade route')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to execute trade route')
    } finally {
      setLoading(false)
    }
  }

  const moveToSector = async (sectorNumber: number) => {
    if (onTravelToSector) {
      onTravelToSector(sectorNumber, 'realspace')
    }
  }

  const estimateTurns = (route: TradeRoute, iterations: number) => {
    // If we have historical data, estimate turns/iteration, else assume 2
    const perIteration = route.current_iteration > 0 && route.total_turns_spent > 0
      ? Math.max(1, Math.round(route.total_turns_spent / route.current_iteration))
      : 2
    return perIteration * iterations
  }

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(amount)
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString()
  }

  if (!open) return null

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>🚀 Trade Routes</h2>
          <button onClick={onClose} className={styles.closeButton}>✕</button>
        </div>

        <div className={styles.content}>
          <div className={styles.toolbar}>
            <button 
              className={styles.createBtn}
              onClick={() => setShowCreateForm(true)}
              disabled={loading || routes.length >= 10}
            >
              + New Route ({routes.length}/10)
            </button>
            <button 
              className={styles.refreshBtn}
              onClick={fetchRoutes}
              disabled={loading}
            >
              🔄 Refresh
            </button>
          </div>

          {routes.length >= 10 && (
            <div className={styles.limitReached}>
              <p>⚠️ You have reached the maximum of 10 trade routes. Delete an existing route to create a new one.</p>
            </div>
          )}

          {showCreateForm && (
            <div className={styles.createForm}>
              <h3>Create New Trade Route</h3>
              
              <div className={styles.formGroup}>
                <label htmlFor="routeName">Route Name:</label>
                <input
                  id="routeName"
                  type="text"
                  value={newRouteName}
                  onChange={(e) => setNewRouteName(e.target.value)}
                  placeholder="Enter route name..."
                  maxLength={50}
                />
              </div>
              
              <div className={styles.formGroup}>
                <label htmlFor="routeDescription">Description (optional):</label>
                <textarea
                  id="routeDescription"
                  value={newRouteDescription}
                  onChange={(e) => setNewRouteDescription(e.target.value)}
                  placeholder="Enter route description..."
                  rows={3}
                />
              </div>

              <div className={styles.sectorSelection}>
                <h4>Route Sectors</h4>
                <div className={styles.sectorInputs}>
                  <div className={styles.formGroup}>
                    <label htmlFor="fromSector">From Sector:</label>
                    <input
                      id="fromSector"
                      type="number"
                      value={fromSector}
                      onChange={(e) => setFromSector(e.target.value)}
                      placeholder="Enter sector number..."
                      min="0"
                      max="500"
                    />
                  </div>
                  <div className={styles.formGroup}>
                    <label htmlFor="toSector">To Sector:</label>
                    <input
                      id="toSector"
                      type="number"
                      value={toSector}
                      onChange={(e) => setToSector(e.target.value)}
                      placeholder="Enter sector number..."
                      min="0"
                      max="500"
                    />
                  </div>
                </div>

                <div className={styles.formGroup}>
                  <label htmlFor="movementType">Movement Type:</label>
                  <select
                    id="movementType"
                    value={movementType}
                    onChange={(e) => setMovementType(e.target.value as 'warp' | 'realspace')}
                  >
                    <option value="warp">Warp (requires warp connection)</option>
                    <option value="realspace">Realspace (distance-based turns)</option>
                  </select>
                </div>
                
                {portValidationError && (
                  <div className={styles.validationError}>
                    <p>{portValidationError}</p>
                  </div>
                )}

                {connectionValid === true && (
                  <div className={styles.validationSuccess}>
                    <p>✅ {movementType === 'warp' ? 'Warp connection found' : 'Realspace route valid'}</p>
                  </div>
                )}

                {fromPort && toPort && (
                  <div className={styles.portInfo}>
                    <div className={styles.portCard}>
                      <h5>Sector {fromSector} - {fromPort.kind.toUpperCase()} Port</h5>
                      <p>Native: {fromPort.kind} | Stock: {fromPort[fromPort.kind]?.toLocaleString() || 0}</p>
                    </div>
                    <div className={styles.routeArrow}>→</div>
                    <div className={styles.portCard}>
                      <h5>Sector {toSector} - {toPort.kind.toUpperCase()} Port</h5>
                      <p>Native: {toPort.kind} | Stock: {toPort[toPort.kind]?.toLocaleString() || 0}</p>
                    </div>
                  </div>
                )}
              </div>
              
              <div className={styles.formActions}>
                <button 
                  className={styles.validateBtn}
                  onClick={validatePorts}
                  disabled={loading || validatingPorts || !fromSector.trim() || !toSector.trim()}
                >
                  {validatingPorts ? 'Validating...' : 'Validate Ports'}
                </button>
                <button 
                  className={styles.submitBtn}
                  onClick={createRoute}
                  disabled={loading || !newRouteName.trim() || !fromPort || !toPort}
                >
                  Create Route
                </button>
                <button 
                  className={styles.cancelBtn}
                  onClick={() => {
                    setShowCreateForm(false)
                    setNewRouteName('')
                    setNewRouteDescription('')
                    setFromSector('')
                    setToSector('')
                    setFromPort(null)
                    setToPort(null)
                    setPortValidationError(null)
                  }}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}

          {error && (
            <div className={styles.error}>
              <p>{error}</p>
              <button onClick={() => setError(null)} className={styles.dismissBtn}>
                Dismiss
              </button>
            </div>
          )}

          {loading && <p className={styles.loading}>Loading trade routes...</p>}

          {!loading && !error && (
            <div className={styles.routesList}>
              {routes.length === 0 ? (
                <div className={styles.emptyState}>
                  <p>No trade routes found. Create your first route to get started!</p>
                </div>
              ) : (
                routes.map((route) => (
                  <div key={route.id} className={styles.routeCard}>
                    {/* Compact row layout */}
                    <div className={styles.routeRow}>
                      <div className={styles.rowLeft}>
                        <div className={styles.rowTitle}>
                          <span className={styles.routeName}>{route.name}</span>
                          {route.is_active && <span className={styles.badge}>Active</span>}
                          {route.is_automated && <span className={styles.badgeWarn}>Automated</span>}
                        </div>

                        {route.waypoints && route.waypoints.length >= 2 && (
                          <div className={styles.pathInline}>
                            <button className={styles.linkBtn} onClick={() => onTravelToSector?.(route.waypoints[0].port_info.sector_number, 'realspace')}>
                              {route.waypoints[0].port_info.sector_number}
                            </button>
                            <span className={styles.kindChip}>{route.waypoints[0].port_info.port_kind}</span>
                            <span className={styles.arrow}>→</span>
                            <button className={styles.linkBtn} onClick={() => onTravelToSector?.(route.waypoints[1].port_info.sector_number, 'realspace')}>
                              {route.waypoints[1].port_info.sector_number}
                            </button>
                            <span className={styles.kindChip}>{route.waypoints[1].port_info.port_kind}</span>
                          </div>
                        )}
                      </div>

                      <div className={styles.inlineStats}>
                        <span title="Waypoints">Pts {route.waypoint_count}</span>
                        <span title="Profit/Turn">P/T {route.current_profit_per_turn ? formatCurrency(route.current_profit_per_turn) : '—'}</span>
                        <span title="Iterations">Iter {route.current_iteration}</span>
                        <span title="Total Profit">Tot {formatCurrency(route.total_profit)}</span>
                      </div>

                      <div className={styles.rowActions}>
                        <div className={styles.segmentGroup}>
                          {[1,5,10,20,50].map((iters) => (
                            <button
                              key={iters}
                              className={styles.segmentBtn}
                              disabled={loading || route.waypoint_count === 0}
                              onClick={() => {
                                if (iters === 1) return executeRoute(route.id, 1)
                                const est = estimateTurns(route, iters)
                                const ok = confirm(`Execute ${iters} iterations? Estimated turns: ${est}.`)
                                if (ok) executeRoute(route.id, iters)
                              }}
                            >
                              {iters === 1 ? 'Execute' : `x${iters}`}
                            </button>
                          ))}
                        </div>
                        <button className={styles.iconBtn} onClick={() => calculateProfitability(route.id)} title="Calculate Profit">📊</button>
                        <button className={styles.iconBtnDanger} onClick={() => deleteRoute(route.id)} title="Delete">🗑️</button>
                        <button className={styles.iconBtn} onClick={() => { setSelectedRoute(route); setShowRouteDetails(true) }} title="Details">📋</button>
                      </div>
                    </div>
                    
                    <div className={styles.routeMeta}>
                      <span>Created: {formatDate(route.created_at)}</span>
                      {route.last_executed_at && (
                        <span>Last run: {formatDate(route.last_executed_at)}</span>
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
