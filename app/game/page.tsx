'use client'

import { useEffect, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import HeaderHUD from './components/HeaderHUD'
import SectorPanel from './components/SectorPanel'
import MineIndicator from './components/MineIndicator'
import MineDeployer from './components/MineDeployer'
import PortPanel from './components/PortPanel'
import ActionsPanel from './components/ActionsPanel'
import InventoryPanel from './components/InventoryPanel'
import HyperspacePanel from './components/HyperspacePanel'
import AdminLink from './components/AdminLink'
import MapOverlay from './components/MapOverlay'
import WarpScanOverlay from './components/WarpScanOverlay'
import PortOverlay from './components/PortOverlay'
import SpecialPortOverlay from './components/SpecialPortOverlay'
import PlanetOverlay from './components/PlanetOverlay'
import LeaderboardOverlay from './components/LeaderboardOverlay'
import TradeRouteOverlay from './components/TradeRouteOverlay'
import TravelConfirmationModal from './components/TravelConfirmationModal'
import StatusBar from './components/StatusBar'
import { useBackground } from '@/lib/use-background'
import styles from './page.module.css'
import './retro-theme.module.css'

// Helper function to make authenticated API calls
async function apiCall(endpoint: string, options: RequestInit = {}) {
  const { data: { session } } = await supabase.auth.getSession()
  
  if (!session) {
    throw new Error('No session')
  }
  
  const response = await fetch(endpoint, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
      ...options.headers,
    },
  })
  
  if (response.status === 401) {
    // Redirect to login on auth failure
    window.location.href = '/login'
    return
  }
  
  return response
}

// SWR fetcher for authenticated requests
async function fetcher(endpoint: string) {
  const response = await apiCall(endpoint)
  if (!response) return null
  return await response.json()
}

export default function Game() {
  const [user, setUser] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [moveLoading, setMoveLoading] = useState(false)
  const [tradeLoading, setTradeLoading] = useState(false)
  const [statusMessage, setStatusMessage] = useState<string | null>(null)
  const [statusType, setStatusType] = useState<'success' | 'error' | 'info'>('info')
  const [mapOpen, setMapOpen] = useState(false)
  const [mapData, setMapData] = useState<any[]>([])
  const [warpScanOpen, setWarpScanOpen] = useState(false)
  const [warpScanData, setWarpScanData] = useState<any[]>([])
  const [planetOverlayOpen, setPlanetOverlayOpen] = useState(false)
  const [portOverlayOpen, setPortOverlayOpen] = useState(false)
  const [specialPortOverlayOpen, setSpecialPortOverlayOpen] = useState(false)
  const [leaderboardOpen, setLeaderboardOpen] = useState(false)
  const [tradeRouteOpen, setTradeRouteOpen] = useState(false)
  const [upgradeLoading, setUpgradeLoading] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)
  const [tradeRoutes, setTradeRoutes] = useState<any[]>([])
  const [travelModalOpen, setTravelModalOpen] = useState(false)
  const [travelTarget, setTravelTarget] = useState<{sector: number, type: 'warp' | 'realspace'} | null>(null)
  const router = useRouter()
  const searchParams = useSearchParams()
  
  // Get universe_id from URL params
  const universeId = searchParams.get('universe_id')
  console.log('Current universeId from URL:', universeId)

  // Check for authentication session
  useEffect(() => {
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        // No session, redirect to login
        const urlParams = new URLSearchParams(window.location.search)
        const universeParam = urlParams.get('universe_id')
        const loginUrl = universeParam ? `/login?universe_id=${universeParam}` : '/login'
        router.push(loginUrl)
      } else {
        setAuthChecked(true)
        
        // Check for pending registration after email verification
        const pendingRegistration = sessionStorage.getItem('pendingRegistration')
        if (pendingRegistration) {
          try {
            const { universe_id, handle } = JSON.parse(pendingRegistration)
            sessionStorage.removeItem('pendingRegistration')
            
            // Complete the registration
            const response = await fetch('/api/register', {
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${session.access_token}`,
              },
              body: JSON.stringify({
                universe_id: universe_id,
                handle: handle.trim()
              })
            })

            const result = await response.json()
            if (result.error) {
              console.error('Registration completion error:', result.error)
              // Redirect to login to show error
              const loginUrl = universe_id ? `/login?universe_id=${universe_id}` : '/login'
              router.push(loginUrl)
            } else {
              console.log('Registration completed successfully')
              // Refresh the page to get the new player data
              window.location.reload()
            }
          } catch (error) {
            console.error('Error completing pending registration:', error)
            sessionStorage.removeItem('pendingRegistration')
          }
        }
      }
    }
    
    checkSession()

    // Listen for auth state changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_IN' && session) {
        setAuthChecked(true)
      } else if (event === 'SIGNED_OUT') {
        setAuthChecked(false)
        const urlParams = new URLSearchParams(window.location.search)
        const universeParam = urlParams.get('universe_id')
        const loginUrl = universeParam ? `/login?universe_id=${universeParam}` : '/login'
        router.push(loginUrl)
      }
    })

    return () => subscription.unsubscribe()
  }, [router])

  // Build API URLs with universe parameter
  const meUrl = authChecked ? (universeId ? `/api/me?universe_id=${universeId}` : '/api/me') : null
  const { data: playerData, error: playerError, mutate: mutatePlayer } = useSWR(
    meUrl,
    fetcher,
    { revalidateOnFocus: false, revalidateOnReconnect: false, dedupingInterval: 10000 }
  )
  const currentSector = playerData?.player?.current_sector_number
  const playerUniverseId = playerData?.player?.universe_id
  const sectorKey = currentSector !== undefined ? `/api/sector?number=${currentSector}&universe_id=${playerUniverseId || universeId || ''}` : null
  const { data: sectorData, error: sectorError, mutate: mutateSector } = useSWR(
    sectorKey,
    fetcher,
    { revalidateOnFocus: false, revalidateOnReconnect: false, dedupingInterval: 10000 }
  )

  // Determine background based on sector data
  const hasPort = sectorData?.port !== null && sectorData?.port !== undefined
  const portKind = sectorData?.port?.kind
  
  let backgroundType: 'space' | 'port-ore' | 'port-organics' | 'port-goods' | 'port-energy' | 'port-special' = 'space'
  
  if (hasPort && portKind) {
    switch (portKind) {
      case 'ore':
        backgroundType = 'port-ore'
        break
      case 'organics':
        backgroundType = 'port-organics'
        break
      case 'goods':
        backgroundType = 'port-goods'
        break
      case 'energy':
        backgroundType = 'port-energy'
        break
      case 'special':
        backgroundType = 'port-special'
        break
      default:
        backgroundType = 'space'
    }
  }
  
  // Apply background
  useBackground(backgroundType)

  // Force refresh data when universe changes
  useEffect(() => {
    if (universeId && authChecked) {
      console.log('Universe changed, refreshing data for:', universeId)
      mutatePlayer()
      mutateSector()
      fetchTradeRoutes()
    }
  }, [universeId, authChecked, mutatePlayer, mutateSector])

  // Fetch trade routes on mount
  useEffect(() => {
    if (authChecked && universeId) {
      fetchTradeRoutes()
    }
  }, [authChecked, universeId])
  
  // Derived snapshots for easier access (and to avoid TDZ in effects)
  const player = playerData?.player
  const sector = sectorData?.sector
  const port = sectorData?.port
  const planets = sectorData?.planets || []

  useEffect(() => {
    const checkSession = async () => {
      const { data: { session } } = await supabase.auth.getSession()
      
      if (!session) {
        router.push('/login')
        return
      }

      setUser(session.user)
      setLoading(false)
    }

    checkSession()

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (event === 'SIGNED_OUT' || !session) {
          router.push('/login')
        } else {
          setUser(session.user)
        }
      }
    )

    return () => subscription.unsubscribe()
  }, [router])

  const handleMove = async (toSectorNumber: number) => {
    if (moveLoading || !playerData?.player?.turns) return
    
    setMoveLoading(true)
    setStatusMessage(null)
    
    try {
      const response = await apiCall('/api/move', {
        method: 'POST',
        body: JSON.stringify({ 
          toSectorNumber,
          universe_id: playerUniverseId || universeId
        })
      })
      
      if (response) {
        const data = await response.json()
        if (data.error) {
          console.error('Move API error:', data.error)
          const errorMsg = data.error.message || data.error.details?.message || 'Move failed'
          setStatusMessage(errorMsg)
          setStatusType('error')
        } else {
          // Revalidate both player and sector data
          mutatePlayer()
          mutateSector()
          setStatusMessage(`Moved to sector ${toSectorNumber}`)
          setStatusType('success')
        }
      }
    } catch (error) {
      setStatusMessage('Move failed')
      setStatusType('error')
    } finally {
      setMoveLoading(false)
    }
  }

  const handleTrade = async (data: { action: string; resource: string; qty: number }) => {
    if (tradeLoading || !sectorData?.port) return
    
    setTradeLoading(true)
    setStatusMessage(null)
    
    try {
      const response = await apiCall('/api/trade', {
        method: 'POST',
        body: JSON.stringify({
          portId: sectorData.port.id,
          action: data.action,
          resource: data.resource,
          qty: data.qty,
          universe_id: playerUniverseId || universeId
        })
      })
      
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          // Revalidate both player and sector data for live inventory updates
          mutatePlayer()
          mutateSector()
          setStatusMessage(`${data.action === 'buy' ? 'Bought' : 'Sold'} ${data.qty} ${data.resource}`)
          setStatusType('success')
        }
      }
    } catch (error) {
      setStatusMessage('Trade failed')
      setStatusType('error')
    } finally {
      setTradeLoading(false)
    }
  }


  const [hyperLoading, setHyperLoading] = useState(false)
  const handleHyperspace = async (toSectorNumber: number) => {
    if (hyperLoading) return
    setHyperLoading(true)
    setStatusMessage(null)
    try {
      const response = await apiCall('/api/hyperspace', {
        method: 'POST',
        body: JSON.stringify({ 
          toSectorNumber,
          universe_id: playerUniverseId || universeId
        })
      })
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          mutatePlayer(); mutateSector()
          setStatusMessage(`Jumped to sector ${toSectorNumber}`)
          setStatusType('success')
        }
      }
    } catch {
      setStatusMessage('Hyperspace failed')
      setStatusType('error')
    } finally {
      setHyperLoading(false)
    }
  }

  // Map & scans helpers
  const [targetSector, setTargetSector] = useState<number>(0)
  useEffect(()=>{
    if (player?.current_sector_number) {
      setTargetSector(player.current_sector_number)
    }
  }, [player?.current_sector_number])

  // Debounced map fetch with viewport-based radius cap
  let mapTimer: any
  const fetchMap = async (center?: number) => {
    const maxCells = Math.max(9, Math.floor((typeof window !== 'undefined' ? window.innerWidth : 720) / 64))
    const radius = Math.min(50, maxCells)
    const currentUniverseId = playerUniverseId || universeId
    const res = await apiCall(`/api/map?center=${center ?? (player?.current_sector_number||0)}&radius=${radius}&universe_id=${currentUniverseId}`)
    if (res) { const j = await res.json(); setMapData(j.sectors||[]) }
  }
  const debouncedFetchMap = (center?: number) => {
    clearTimeout(mapTimer)
    mapTimer = setTimeout(()=> fetchMap(center), 200)
  }

  const openMap = async () => { await fetchMap(); setMapOpen(true) }

  // Planet handlers
  const handleClaimPlanet = async (name: string) => {
    try {
      const response = await apiCall('/api/planet/claim', {
        method: 'POST',
        body: JSON.stringify({ 
          sectorNumber: currentSector,
          name,
          universe_id: playerUniverseId || universeId
        })
      })
      
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          mutatePlayer()
          mutateSector()
          setStatusMessage(`Claimed planet "${name}"`)
          setStatusType('success')
        }
      }
    } catch (error) {
      console.error('Planet claim error:', error)
      setStatusMessage('Planet claim failed')
      setStatusType('error')
    }
  }

  const handleStoreResource = async (resource: string, qty: number) => {
    if (!planets[0]?.id) return
    
    try {
      const response = await apiCall('/api/planet/store', {
        method: 'POST',
        body: JSON.stringify({
          planetId: planets[0].id,
          resource,
          qty,
          universe_id: playerUniverseId || universeId
        })
      })
      
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          mutatePlayer()
          setStatusMessage(`Stored ${qty} ${resource}`)
          setStatusType('success')
        }
      }
    } catch (error) {
      setStatusMessage('Store failed')
      setStatusType('error')
    }
  }

  const handleWithdrawResource = async (resource: string, qty: number) => {
    if (!planets[0]?.id) return
    
    try {
      const response = await apiCall('/api/planet/withdraw', {
        method: 'POST',
        body: JSON.stringify({
          planetId: planets[0].id,
          resource,
          qty,
          universe_id: playerUniverseId || universeId
        })
      })
      
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          mutatePlayer()
          setStatusMessage(`Withdrew ${qty} ${resource}`)
          setStatusType('success')
        }
      }
    } catch (error) {
      setStatusMessage('Withdraw failed')
      setStatusType('error')
    }
  }

  const handleUpgrade = async (attr: string) => {
    if (upgradeLoading) return
    setUpgradeLoading(true)
    setStatusMessage(null)
    try {
      const response = await apiCall('/api/ship/upgrade', {
        method: 'POST',
        body: JSON.stringify({ 
          attr,
          universe_id: playerUniverseId || universeId
        })
      })
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message)
          setStatusType('error')
        } else {
          mutatePlayer()
          setStatusMessage(`${attr.charAt(0).toUpperCase() + attr.slice(1)} upgraded!`)
          setStatusType('success')
        }
      }
    } catch {
      setStatusMessage('Upgrade failed')
      setStatusType('error')
    } finally {
      setUpgradeLoading(false)
    }
  }

  // Auto-trade handler
  const handleAutoTrade = async () => {
    try {
      if (!port?.id) return
      const response = await apiCall('/api/trade/auto', {
        method: 'POST',
        body: JSON.stringify({ 
          portId: port.id,
          universe_id: playerUniverseId || universeId
        })
      })
      if (response) {
        const result = await response.json()
        if (result.error) {
          setStatusMessage(result.error.message || 'Auto-trade failed')
          setStatusType('error')
          return { error: result.error }
        } else {
          // Revalidate
          mutatePlayer(); mutateSector()
          const sold = result.sold || {}
          const bought = result.bought || {}
          const soldParts = ['ore','organics','goods','energy']
            .map((k)=> sold[k] ? `${sold[k]} ${k}` : '')
            .filter(Boolean)
            .join(', ')
          const msg = `Auto-trade complete${soldParts?`: sold ${soldParts}`:''}${bought?.qty?`, bought ${bought.qty} ${bought.resource}`:''}`
          setStatusMessage(msg)
          setStatusType('success')
          return result
        }
      }
    } catch (e) {
      setStatusMessage('Auto-trade failed')
      setStatusType('error')
      return { error: 'Auto-trade failed' }
    }
  }

  const scanWarps = async () => {
    const currentUniverseId = playerUniverseId || universeId
    const res = await apiCall('/api/scan/warps', { 
      method: 'POST',
      body: JSON.stringify({ universe_id: currentUniverseId })
    })
    if (res) {
      const j = await res.json()
      if (j.error) {
        setStatusMessage(j.error.message)
        setStatusType('error')
      } else {
        setWarpScanData(j.sectors || [])
        setWarpScanOpen(true)
        // Refresh turns after spending 1
        mutatePlayer()
      }
    }
  }

  const refreshData = () => {
    mutatePlayer()
    mutateSector()
    fetchTradeRoutes()
    setStatusMessage('Data refreshed')
    setStatusType('info')
  }

  const fetchTradeRoutes = async () => {
    if (!authChecked || !universeId) return
    
    try {
      const response = await apiCall(`/api/trade-routes?universe_id=${universeId}`)
      if (response) {
        const data = await response.json()
        if (data.ok) {
          setTradeRoutes(data.routes || [])
        }
      }
    } catch (error) {
      console.error('Error fetching trade routes:', error)
    }
  }

  const executeTradeRoute = async (routeId: string) => {
    if (!player?.turns) {
      setStatusMessage('No turns remaining')
      setStatusType('error')
      return
    }

    try {
      const response = await apiCall(`/api/trade-routes/${routeId}/execute`, {
        method: 'POST',
        body: JSON.stringify({ 
          max_iterations: 1,
          universe_id: universeId
        })
      })

      if (response) {
        const data = await response.json()
        if (data.ok) {
          setStatusMessage('Trade route executed successfully!')
          setStatusType('success')
          await fetchTradeRoutes() // Refresh routes
          await mutatePlayer() // Refresh player data (turns, credits, inventory)
        } else {
          setStatusMessage(data.error?.message || 'Failed to execute trade route')
          setStatusType('error')
        }
      }
    } catch (error) {
      console.error('Error executing trade route:', error)
      setStatusMessage('Failed to execute trade route')
      setStatusType('error')
    }
  }

  // Travel confirmation handler
  const handleTravelConfirmation = async () => {
    if (!travelTarget) return
    
    if (travelTarget.type === 'warp') {
      await handleMove(travelTarget.sector)
    } else {
      // Realspace travel - would need to implement this
      setStatusMessage('Realspace travel not yet implemented')
      setStatusType('error')
    }
  }

  // Calculate turns required for travel
  const calculateTurnsRequired = (targetSector: number, travelType: 'warp' | 'realspace') => {
    if (travelType === 'warp') {
      return 1 // Warp travel always costs 1 turn
    } else {
      // Realspace travel - calculate based on distance
      const distance = Math.abs(targetSector - (player?.current_sector_number || 0))
      return Math.max(1, Math.ceil(distance / 10)) // 1 turn per 10 sectors
    }
  }

  if (loading || !authChecked) {
    return (
      <div className={styles.container}>
        <div className={styles.loadingScreen}>
          <h1>BNT Redux</h1>
          <p>{!authChecked ? 'Checking authentication...' : 'Loading...'}</p>
        </div>
      </div>
    )
  }

  // Handle player not found error - redirect to registration
  if (playerError && playerError.status === 404) {
    const errorData = playerError.info?.error
    if (errorData?.code === 'player_not_found') {
      // Redirect to login with universe context for registration
      const universeParam = universeId ? `?universe_id=${universeId}` : ''
      router.push(`/login${universeParam}`)
      return (
        <div className={styles.container}>
          <div className={styles.loadingScreen}>
            <h1>BNT Redux</h1>
            <p>Redirecting to registration...</p>
          </div>
        </div>
      )
    }
  }

  // moved above

  return (
    <div className={styles.container}>
      {/* Header HUD */}
      <HeaderHUD
        handle={player?.handle}
        turns={player?.turns}
        turnCap={playerData?.player?.turn_cap}
        lastTurnTs={player?.last_turn_ts}
        credits={player?.credits}
        currentSector={player?.current_sector_number}
        engineLvl={playerData?.ship?.engine_lvl}
        onRefresh={refreshData}
        loading={!playerData}
        currentUniverseId={playerUniverseId || universeId}
      />

      {/* Main Layout */}
      <div className={styles.mainLayout}>
        {/* Left Commands */}
        <div className={styles.leftPanel}>
          <div className={styles.commandsBox}>
            <h3>Commands</h3>
            <div className={styles.commandList}>
              <button className={styles.commandItem} onClick={() => router.push('/ship')}>🚀 Ship</button>
              <button className={styles.commandItem} onClick={() => setLeaderboardOpen(true)}>🏆 Leaderboard</button>
              <button className={styles.commandItem} onClick={() => setTradeRouteOpen(true)}>🚀 Trade Routes</button>
              {/* Admin link visible only if user is admin */}
              <AdminLink />
              <button className={styles.commandItem} onClick={async ()=>{
                try {
                  const res = await apiCall('/api/favorite', { method:'POST', body: JSON.stringify({ sectorNumber: sector?.number, flag: true })})
                  if (res) { await res.json(); setStatusMessage('Favorited'); setStatusType('success') }
                } catch {}
              }}>⭐ Favorite Sector</button>
            </div>
          </div>

          <div className={styles.sideCard}>
            <h3>Trade Routes</h3>
            {tradeRoutes.length === 0 ? (
              <p className={styles.subtleNote}>None</p>
            ) : (
              <div className={styles.tradeRoutesList}>
                {tradeRoutes.slice(0, 5).map((route) => (
                  <div key={route.id} className={styles.tradeRouteItem}>
                    <div className={styles.routeName}>{route.name}</div>
                    <div className={styles.routeStats}>
                      <span className={styles.waypointCount}>{route.waypoint_count || 0} waypoints</span>
                      {route.is_active && <span className={styles.activeBadge}>Active</span>}
                    </div>
                    {route.waypoints && route.waypoints.length > 0 && (
                      <div className={styles.routeActions}>
                        {/* Show route sectors as clickable */}
                        <div className={styles.routeSectors}>
                          {route.waypoints.slice(0, 2).map((waypoint: any, index: number) => (
                            <button
                              key={`${route.id}-${waypoint.id}`}
                              className={`${styles.sectorBtn} ${
                                waypoint.port_info?.sector_number === sector?.number ? styles.currentSector : ''
                              }`}
                              onClick={() => {
                                if (waypoint.port_info?.sector_number !== sector?.number) {
                                  setTravelTarget({
                                    sector: waypoint.port_info?.sector_number,
                                    type: 'warp'
                                  })
                                  setTravelModalOpen(true)
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
                        {route.waypoints[0]?.port_info?.sector_number === sector?.number && (
                          <button 
                            className={styles.executeBtn}
                            onClick={() => executeTradeRoute(route.id)}
                            disabled={!player?.turns}
                          >
                            ▶️ Execute
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                ))}
                {tradeRoutes.length > 5 && (
                  <p className={styles.moreRoutes}>+{tradeRoutes.length - 5} more</p>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Center Space Viewport */}
        <div className={styles.centerArea}>
          <div className={styles.spaceViewport}>
            <div className={styles.viewportHeader}>
              <div className={styles.sectorTitle}>SECTOR</div>
              <div className={styles.sectorNumber}>
                {sector?.number ?? '--'}
              </div>
              {/* Center-pane controls removed per design: no Map/Scan here */}
            </div>

            {port ? (
              <div className={styles.portInline}>
                Trading port:
                <span
                  className={styles.portBadge}
                  onClick={() => {
                    if (port.kind === 'special') {
                      setSpecialPortOverlayOpen(true)
                    } else {
                      setPortOverlayOpen(true)
                    }
                  }}
                >
                  {port.kind === 'ore' && '🪨 Ore'}
                  {port.kind === 'organics' && '🌿 Organics'}
                  {port.kind === 'goods' && '📦 Goods'}
                  {port.kind === 'energy' && '⚡ Energy'}
                  {port.kind === 'special' && '⭐ Special'}
                </span>
              </div>
            ) : (
              <div className={styles.portInline}>No port available in this sector</div>
            )}

            {/* Planets */}
            {planets.length > 0 && (
              <div className={styles.planetBelt}>
                {planets.map((planet: any, index: number) => (
                  <div key={planet.id} style={{ marginBottom: index < planets.length - 1 ? '8px' : '0' }}>
                    <div className={styles.planetOrb} />
                    <div className={styles.planetLabel}>{planet.name}</div>
                    <button 
                      className={styles.planetBtn} 
                      onClick={() => setPlanetOverlayOpen(true)}
                    >
                      View Planet
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Mine Information */}
            {sector?.number && (playerUniverseId || universeId) && (
              <MineIndicator 
                sectorNumber={sector.number}
                universeId={playerUniverseId || universeId}
                playerHullLevel={playerData?.ship?.hull_lvl}
              />
            )}

            {/* Mine Deployment */}
            {sector?.number && (playerUniverseId || universeId) && playerData?.ship?.torpedoes !== undefined && (
              <MineDeployer 
                sectorNumber={sector.number}
                universeId={playerUniverseId || universeId}
                playerTorpedoes={playerData.ship.torpedoes}
              />
            )}

            {/* Other ships section */}
            <div className={styles.shipsSection}>
              <h3>Other ships in sector {sector?.number || '--'}</h3>
              <p className={styles.subtleNote}>None</p>
            </div>
          </div>
        </div>

        {/* Right Sidebar: Cargo, Realspace, Warp */}
        <div className={styles.rightPanel}>
          {/* Scheduler widget moved to Admin panel */}
          
          <InventoryPanel inventory={playerData?.inventory} loading={!playerData} />

          <HyperspacePanel
            engineLvl={playerData?.ship?.engine_lvl}
            currentSector={player?.current_sector_number}
            turns={player?.turns}
            target={targetSector}
            onChangeTarget={setTargetSector}
            onJump={handleHyperspace}
            loading={hyperLoading}
          />


          <div className={styles.sideCard}>
            <h3>Navigation</h3>
            
            {/* Navigation Actions */}
            <div className={styles.navActions}>
              <button className={styles.navBtn} onClick={openMap}>🗺️ Map</button>
              <button 
                className={styles.navBtn} 
                onClick={scanWarps} 
                disabled={!player?.turns}
              >
                🔎 Scan Warps (-1)
              </button>
            </div>
            
            {/* Warp Gates */}
            <div className={styles.warpSection}>
              <h4>Warp Gates</h4>
              <div className={styles.warpList}>
                {sectorData?.warps?.map((warpNumber: number) => (
                  <button
                    key={warpNumber}
                    onClick={() => handleMove(warpNumber)}
                    disabled={moveLoading || !player?.turns}
                    className={styles.warpLink}
                  >
                    {moveLoading ? 'Moving...' : `=> ${warpNumber}`}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {/* Trading actions are launched from the Port (modal) – removed from sidebar */}
          {/* Equipment & Repair moved to special ports for future ship upgrades */}
        </div>
      </div>

      {/* Status Bar */}
      <StatusBar
        message={statusMessage ?? undefined}
        type={statusType}
        loading={moveLoading || tradeLoading || upgradeLoading}
      />

      <MapOverlay
        open={mapOpen}
        onClose={()=> setMapOpen(false)}
        sectors={mapData}
        onPickTarget={(n)=> { setTargetSector(n); setMapOpen(false) }}
        currentSector={player?.current_sector_number}
      />

      <WarpScanOverlay
        open={warpScanOpen}
        onClose={()=> setWarpScanOpen(false)}
        sectors={warpScanData}
        onPick={(n)=> { setWarpScanOpen(false); handleMove(n) }}
      />

      <PortOverlay
        open={portOverlayOpen}
        onClose={() => setPortOverlayOpen(false)}
        port={port}
        player={player}
        ship={playerData?.ship}
        inventory={playerData?.inventory}
        onTrade={handleTrade}
        tradeLoading={tradeLoading}
        onAutoTrade={handleAutoTrade}
      />

      <SpecialPortOverlay
        open={specialPortOverlayOpen}
        onClose={() => setSpecialPortOverlayOpen(false)}
        shipData={playerData?.ship}
        playerCredits={player?.credits}
        shipCredits={playerData?.ship?.credits}
        onUpgrade={handleUpgrade}
        upgradeLoading={upgradeLoading}
        universeId={playerUniverseId || universeId}
        onStatusMessage={(message, type) => {
          setStatusMessage(message)
          setStatusType(type)
        }}
      />

      {planetOverlayOpen && planets[0] && (
        <PlanetOverlay
          planet={planets[0]}
          player={{
            credits: playerData?.ship?.credits || 0,
            turns: player.turns,
            inventory: {
              ore: playerData?.ship?.ore || 0,
              organics: playerData?.ship?.organics || 0,
              goods: playerData?.ship?.goods || 0,
              energy: playerData?.ship?.energy || 0,
              colonists: playerData?.ship?.colonists || 0,
              credits: playerData?.ship?.credits || 0
            }
          }}
          onClose={() => setPlanetOverlayOpen(false)}
          onClaim={handleClaimPlanet}
          onStore={handleStoreResource}
          onWithdraw={handleWithdrawResource}
          onRefresh={() => { mutatePlayer(); mutateSector(); }}
        />
      )}


      <LeaderboardOverlay
        open={leaderboardOpen}
        onClose={() => setLeaderboardOpen(false)}
        universeId={playerUniverseId || universeId || ''}
      />
      
        <TradeRouteOverlay
          open={tradeRouteOpen}
          onClose={() => setTradeRouteOpen(false)}
          universeId={playerUniverseId || universeId || ''}
          onRouteChange={() => {
            mutatePlayer()
            mutateSector()
            fetchTradeRoutes()
          }}
        />

        <TravelConfirmationModal
          open={travelModalOpen}
          onClose={() => {
            setTravelModalOpen(false)
            setTravelTarget(null)
          }}
          onConfirm={handleTravelConfirmation}
          targetSector={travelTarget?.sector || 0}
          currentSector={player?.current_sector_number || 0}
          turnsRequired={travelTarget ? calculateTurnsRequired(travelTarget.sector, travelTarget.type) : 1}
          travelType={travelTarget?.type || 'warp'}
        />

    </div>
  )
}
