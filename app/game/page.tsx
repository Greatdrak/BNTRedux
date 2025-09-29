'use client'

import { useEffect, useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import GameLayout from './components/GameLayout'
import GameHeader from './components/GameHeader'
import LeftCommandsPanel from './components/LeftCommandsPanel'
import CenterViewport from './components/CenterViewport'
import RightPanels from './components/RightPanels'
import ShipsFooter from './components/ShipsFooter'
import EnemyShipOverlay from './components/EnemyShipOverlay'
import CombatComparisonOverlay from './components/CombatComparisonOverlay'
import CombatOverlay from './components/CombatOverlay'
import AdminLink from './components/AdminLink'
import MapOverlay from './components/MapOverlay'
import WarpScanOverlay from './components/WarpScanOverlay'
import PortOverlay from './components/PortOverlay'
import SpecialPortOverlay from './components/SpecialPortOverlay'
import PlanetOverlay from './components/PlanetOverlay'
import PlanetsOverlay from './components/PlanetsOverlay'
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

function GameContent() {
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
  const [selectedPlanetIndex, setSelectedPlanetIndex] = useState(0)
  const [portOverlayOpen, setPortOverlayOpen] = useState(false)
  const [specialPortOverlayOpen, setSpecialPortOverlayOpen] = useState(false)
  const [leaderboardOpen, setLeaderboardOpen] = useState(false)
  const [tradeRouteOpen, setTradeRouteOpen] = useState(false)
  const [planetsOpen, setPlanetsOpen] = useState(false)
  const [upgradeLoading, setUpgradeLoading] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)
  const [tradeRoutes, setTradeRoutes] = useState<any[]>([])
  const [travelModalOpen, setTravelModalOpen] = useState(false)
  const [travelTarget, setTravelTarget] = useState<{sector: number, type: 'warp' | 'realspace'} | null>(null)
  const [enemyShipOverlayOpen, setEnemyShipOverlayOpen] = useState(false)
  const [selectedEnemyShip, setSelectedEnemyShip] = useState<any>(null)
  const [combatComparisonOpen, setCombatComparisonOpen] = useState(false)
  const [combatOverlayOpen, setCombatOverlayOpen] = useState(false)
  const [combatResult, setCombatResult] = useState<any>(null)
  const [combatSteps, setCombatSteps] = useState<any[]>([])
  const [isCombatComplete, setIsCombatComplete] = useState(false)
  const router = useRouter()
  const searchParams = useSearchParams()
  
  // Get universe_id from URL params
  const universeId = searchParams.get('universe_id')

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

  // Handle universe deletion errors and character creation
  useEffect(() => {
    
    // Check for errors in the data response (since we return 200 with error objects)
    if (playerData?.error?.code === 'universe_not_found') {
      const redirectUniverse = playerData.error.redirect_universe
      const redirectUniverseName = playerData.error.redirect_universe_name
      
      if (redirectUniverse) {
        setStatusMessage(`The universe you were in no longer exists. Redirecting to "${redirectUniverseName}"...`)
        setStatusType('info')
        
        // Redirect to the available universe
        setTimeout(() => {
          router.push(`/game?universe_id=${redirectUniverse}`)
        }, 2000)
      }
    } else if (playerData?.error?.code === 'no_universes') {
      setStatusMessage('No universes are available. Please contact an administrator.')
      setStatusType('error')
    } else if (playerData?.error?.code === 'player_not_found') {
      // No character exists in this universe - redirect to login/registration
      setStatusMessage('No character found in this universe. Redirecting to character creation...')
      setStatusType('info')
      
      setTimeout(() => {
        const loginUrl = universeId ? `/login?universe_id=${universeId}` : '/login'
        router.push(loginUrl)
      }, 2000)
    }
    
    // Also check for network errors (original error handling)
    if (playerError?.error?.code === 'universe_not_found') {
      const redirectUniverse = playerError.error.redirect_universe
      const redirectUniverseName = playerError.error.redirect_universe_name
      
      if (redirectUniverse) {
        setStatusMessage(`The universe you were in no longer exists. Redirecting to "${redirectUniverseName}"...`)
        setStatusType('info')
        
        // Redirect to the available universe
        setTimeout(() => {
          router.push(`/game?universe_id=${redirectUniverse}`)
        }, 2000)
      }
    } else if (playerError?.error?.code === 'no_universes') {
      setStatusMessage('No universes are available. Please contact an administrator.')
      setStatusType('error')
    }
  }, [playerError, playerData, router, universeId])
  const currentSector = playerData?.player?.current_sector_number
  const playerUniverseId = playerData?.player?.universe_id
  const sectorKey = currentSector !== undefined ? `/api/sector?number=${currentSector}&universe_id=${playerUniverseId || universeId || ''}` : null
  const { data: sectorData, error: sectorError, mutate: mutateSector } = useSWR(
    sectorKey,
    fetcher,
    { revalidateOnFocus: false, revalidateOnReconnect: false, dedupingInterval: 10000 }
  )

  // Handle sector errors (might indicate universe issues)
  useEffect(() => {
    if (sectorError && !playerError) {
      console.error('Sector error:', sectorError)
      setStatusMessage('Unable to load sector data. The universe may have been deleted.')
      setStatusType('error')
    }
  }, [sectorError, playerError])

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
          
          // Reset quantity to 1 after successful trade to avoid validation errors
          // This will be handled by the ActionsPanel component
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
          // Close the planet overlay after successful claim
          setPlanetOverlayOpen(false)
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

  // Helper functions for header
  const universeName = "Alpha"
  const handleUniverseChange = (newUniverseId: string) => {
    // TODO: Implement universe switching
    console.log('Switch to universe:', newUniverseId)
  }
  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  // Enemy ship scan handler
  const handleScanShip = async (shipId: string) => {
    const finalUniverseId = playerUniverseId || universeId
    
    if (!finalUniverseId) {
      return { success: false, error: 'No universe ID available' }
    }
    
    try {
      const response = await apiCall('/api/ship/scan', {
        method: 'POST',
        body: JSON.stringify({
          target_ship_id: shipId,
          universe_id: finalUniverseId
        })
      })
      
      const result = await response?.json()
      
      if (result.error) {
        return { success: false, error: result.error.message }
      }
      
      return { success: true, data: result }
    } catch (error) {
      console.error('Scan ship error:', error)
      return { success: false, error: 'Failed to scan ship' }
    }
  }

  // Enemy ship attack handler
  const handleAttackShip = (shipId: string, scannedData?: any) => {
    // Close enemy ship overlay and open combat comparison
    setEnemyShipOverlayOpen(false)
    setCombatComparisonOpen(true)
    
    // Update selected enemy ship with scanned data if available
    if (scannedData && selectedEnemyShip) {
      setSelectedEnemyShip({
        ...selectedEnemyShip,
        ...scannedData
      })
    }
  }

  // Confirm attack handler
  const handleConfirmAttack = async () => {
    const finalUniverseId = playerUniverseId || universeId
    
    if (!finalUniverseId || !selectedEnemyShip) {
      return
    }
    
    try {
      // Close comparison overlay and open combat overlay
      setCombatComparisonOpen(false)
      setCombatOverlayOpen(true)
      setIsCombatComplete(false)
      
      // Call combat API
      const response = await apiCall('/api/combat/initiate', {
        method: 'POST',
        body: JSON.stringify({
          target_ship_id: selectedEnemyShip.id,
          universe_id: finalUniverseId
        })
      })
      
      const result = await response?.json()
      
      if (result.error) {
        console.error('Combat error:', result.error)
        setCombatOverlayOpen(false)
        return
      }
      
      // Set combat data
      setCombatResult(result.combat_result)
      setCombatSteps(result.combat_result.combat_steps)
      setIsCombatComplete(true)
      
      // Refresh player data to show updated turns
      mutatePlayer()
      
    } catch (error) {
      console.error('Combat initiation error:', error)
      setCombatOverlayOpen(false)
    }
  }

  return (
    <div className={styles.container}>
      <GameLayout>
        {{
          header: (
            <GameHeader
              playerName={player?.handle || 'Loading...'}
              currentSector={player?.current_sector_number || 0}
              turns={player?.turns || 0}
              turnsUsed={player?.turns_spent || 0}
              credits={player?.credits || 0}
              engineLevel={playerData?.ship?.engine_lvl || 0}
              lastTurnTs={player?.last_turn_ts}
              turnCap={playerData?.player?.turn_cap}
              universeName={universeName}
              universeId={playerUniverseId || universeId}
              onUniverseChange={handleUniverseChange}
              onRefresh={refreshData}
              onLogout={handleLogout}
            />
          ),

          leftPanel: (
            <LeftCommandsPanel
              tradeRoutes={tradeRoutes}
              onCommandClick={(command) => {
                switch(command) {
                  case 'ship': router.push('/ship'); break;
                  case 'leaderboard': setLeaderboardOpen(true); break;
                  case 'trade-routes': setTradeRouteOpen(true); break;
                  case 'planets': setPlanetsOpen(true); break;
                  case 'admin': router.push('/admin'); break;
                  case 'favorite-sector': 
                    apiCall('/api/favorite', { method:'POST', body: JSON.stringify({ sectorNumber: sector?.number, flag: true })})
                      .then(res => res?.json())
                      .then(() => { setStatusMessage('Favorited'); setStatusType('success') })
                      .catch(() => {});
                    break;
                }
              }}
              onTradeRouteClick={(routeId) => setTradeRouteOpen(true)}
              onTradeRouteExecute={executeTradeRoute}
              currentSector={sector?.number || 0}
              playerTurns={player?.turns || 0}
              onTravelToSector={(sectorNum, type) => {
                setTravelTarget({ sector: sectorNum, type })
                setTravelModalOpen(true)
              }}
            />
          ),

          centerPanel: (
            <>
              <CenterViewport
                sector={sector}
                planets={planets}
                port={port}
                onPlanetClick={(index) => {
                  setSelectedPlanetIndex(index)
                  setPlanetOverlayOpen(true)
                }}
                onPortClick={() => {
                  if (port?.kind === 'special') {
                    setSpecialPortOverlayOpen(true)
                  } else {
                    setPortOverlayOpen(true)
                  }
                }}
              />
              {/* Ships section - part of center, not footer */}
              {sectorData?.ships && sectorData.ships.filter((ship: any) => ship.id !== playerData?.ship?.id).length > 0 && (
                <ShipsFooter
                  sectorNumber={sector?.number || 0}
                  ships={sectorData.ships}
                  currentPlayerShipId={playerData?.ship?.id}
                  onShipClick={(ship) => {
                    setSelectedEnemyShip(ship)
                    setEnemyShipOverlayOpen(true)
                  }}
                />
              )}
            </>
          ),

          rightPanel: (
            <RightPanels
              inventory={playerData?.inventory}
              inventoryLoading={!playerData}
              engineLevel={playerData?.ship?.engine_lvl}
              currentSector={player?.current_sector_number}
              turns={player?.turns}
              targetSector={targetSector}
              onTargetSectorChange={setTargetSector}
              onHyperspaceJump={handleHyperspace}
              hyperLoading={hyperLoading}
              onMapClick={openMap}
              onScanWarps={scanWarps}
              warps={sectorData?.warps || []}
              onWarpClick={handleMove}
              moveLoading={moveLoading}
              playerTurns={player?.turns}
            />
          )
        }}
      </GameLayout>

      {/* Status Bar - Fixed positioning */}
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
        onPurchaseComplete={() => {
          // Refresh player data to get updated ship credits
          mutatePlayer()
        }}
      />

      {planetOverlayOpen && planets.length > 0 && (
        <PlanetOverlay
          planets={planets}
          initialPlanetIndex={selectedPlanetIndex}
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

        <PlanetsOverlay
          open={planetsOpen}
          onClose={() => setPlanetsOpen(false)}
          universeId={playerUniverseId || universeId}
          onTravelToSector={(sector) => {
            setTravelTarget({ sector, type: 'warp' })
            setTravelModalOpen(true)
          }}
          onStatusMessage={(message, type) => {
            setStatusMessage(message)
            setStatusType(type)
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

          <EnemyShipOverlay
            open={enemyShipOverlayOpen}
            onClose={() => {
              setEnemyShipOverlayOpen(false)
              setSelectedEnemyShip(null)
            }}
            enemyShip={selectedEnemyShip}
            currentPlayerTurns={player?.turns || 0}
            onScanShip={handleScanShip}
            onAttackShip={handleAttackShip}
          />

          <CombatComparisonOverlay
            open={combatComparisonOpen}
            onClose={() => setCombatComparisonOpen(false)}
            playerShip={playerData?.ship}
            enemyShip={selectedEnemyShip}
            onConfirmAttack={handleConfirmAttack}
          />

          <CombatOverlay
            open={combatOverlayOpen}
            onClose={() => {
              setCombatOverlayOpen(false)
              setSelectedEnemyShip(null)
              setCombatResult(null)
              setCombatSteps([])
              setIsCombatComplete(false)
            }}
            playerShip={playerData?.ship}
            enemyShip={selectedEnemyShip}
            combatResult={combatResult}
            combatSteps={combatSteps}
            isCombatComplete={isCombatComplete}
          />

    </div>
  )
}

export default function Game() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <GameContent />
    </Suspense>
  )
}
