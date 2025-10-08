import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase-client'
import PlanetCombatOverlay from './PlanetCombatOverlay'
import CombatOverlay from './CombatOverlay'
import styles from './PlanetOverlay.module.css'

interface Planet {
  id: string
  name: string
  owner: boolean
  ownerName?: string | null
  colonists?: number
  colonistsMax?: number
  stock?: {
    ore: number
    organics: number
    goods: number
    energy: number
    credits?: number
  }
  defenses?: {
    fighters: number
    torpedoes: number
    shields: number
  }
  lastProduction?: string
  lastColonistGrowth?: string
  productionAllocation?: {
    ore: number
    organics: number
    goods: number
    energy: number
    fighters: number
    torpedoes: number
  }
  base?: {
    built: boolean
    cost: number
    colonistsRequired: number
    resourcesRequired: number
  }
}

interface PlanetOverlayProps {
  planets: Planet[]
  initialPlanetIndex?: number
  player: {
    credits: number
    turns: number
    inventory: {
      ore: number
      organics: number
      goods: number
      energy: number
      colonists: number
      credits: number
    }
  }
  playerShip?: any
  onClose: () => void
  onClaim: (name: string) => void
  onStore: (resource: string, qty: number) => void
  onWithdraw: (resource: string, qty: number) => void
  onRefresh: () => void
}

export default function PlanetOverlay({ 
  planets, 
  initialPlanetIndex = 0,
  player, 
  playerShip,
  onClose, 
  onClaim, 
  onStore, 
  onWithdraw, 
  onRefresh 
}: PlanetOverlayProps) {
  const [currentPlanetIndex, setCurrentPlanetIndex] = useState(initialPlanetIndex)
  const [claimName, setClaimName] = useState('Colony')
  const [storeResource, setStoreResource] = useState('ore')
  const [storeQty, setStoreQty] = useState(1)
  const [withdrawResource, setWithdrawResource] = useState('ore')
  const [withdrawQty, setWithdrawQty] = useState(1)
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<'overview' | 'transfer' | 'production' | 'base'>('overview')
  const [showRenameForm, setShowRenameForm] = useState(false)
  const [statusMessage, setStatusMessage] = useState('')
  const [planetCombatOpen, setPlanetCombatOpen] = useState(false)
  const [planetCombatData, setPlanetCombatData] = useState<{ steps: any[]; winner: 'attacker' | 'defender' | 'draw' } | null>(null)
  const [useShipCombatOverlay, setUseShipCombatOverlay] = useState<{ open: boolean, combatResult: any, steps: any[] } | null>(null)
  const [canCapture, setCanCapture] = useState(false)
  
  // Get current planet from slideshow
  const currentPlanet = planets[currentPlanetIndex]
  const [renameName, setRenameName] = useState(currentPlanet?.name || 'Unnamed')
  const [planetStock, setPlanetStock] = useState({
    ore: currentPlanet?.stock?.ore || 0,
    organics: currentPlanet?.stock?.organics || 0,
    goods: currentPlanet?.stock?.goods || 0,
    energy: currentPlanet?.stock?.energy || 0,
    credits: currentPlanet?.stock?.credits || 0
  })
  
  const [productionAllocation, setProductionAllocation] = useState({
    ore: currentPlanet?.productionAllocation?.ore || 0,
    organics: currentPlanet?.productionAllocation?.organics || 0,
    goods: currentPlanet?.productionAllocation?.goods || 0,
    energy: currentPlanet?.productionAllocation?.energy || 0,
    fighters: currentPlanet?.productionAllocation?.fighters || 0,
    torpedoes: currentPlanet?.productionAllocation?.torpedoes || 0
  })

  // Transfer state
  const [transferData, setTransferData] = useState<Record<string, { quantity: number, toPlanet: boolean }>>({})

  // Update currentPlanetIndex when initialPlanetIndex changes
  useEffect(() => {
    setCurrentPlanetIndex(initialPlanetIndex)
  }, [initialPlanetIndex])

  // Update state when current planet changes
  useEffect(() => {
    if (currentPlanet) {
      setRenameName(currentPlanet.name || 'Unnamed')
      setPlanetStock({
        ore: currentPlanet.stock?.ore || 0,
        organics: currentPlanet.stock?.organics || 0,
        goods: currentPlanet.stock?.goods || 0,
        energy: currentPlanet.stock?.energy || 0,
        credits: currentPlanet.stock?.credits || 0
      })
      setProductionAllocation({
        ore: currentPlanet.productionAllocation?.ore || 0,
        organics: currentPlanet.productionAllocation?.organics || 0,
        goods: currentPlanet.productionAllocation?.goods || 0,
        energy: currentPlanet.productionAllocation?.energy || 0,
        fighters: currentPlanet.productionAllocation?.fighters || 0,
        torpedoes: currentPlanet.productionAllocation?.torpedoes || 0
      })
      setTransferData({})
    }
  }, [currentPlanetIndex, currentPlanet])

  // Slideshow navigation functions
  const goToPreviousPlanet = () => {
    setCurrentPlanetIndex((prev) => (prev > 0 ? prev - 1 : planets.length - 1))
  }

  const goToNextPlanet = () => {
    setCurrentPlanetIndex((prev) => (prev < planets.length - 1 ? prev + 1 : 0))
  }

  const resources = [
    { key: 'ore', label: 'Ore', icon: '🪨' },
    { key: 'organics', label: 'Organics', icon: '🌿' },
    { key: 'goods', label: 'Goods', icon: '📦' },
    { key: 'energy', label: 'Energy', icon: '⚡' },
    { key: 'credits', label: 'Credits', icon: '💰' }
  ]
  
  const productionItems = [
    { key: 'ore', label: 'Ore', icon: '🪨' },
    { key: 'organics', label: 'Organics', icon: '🌿' },
    { key: 'goods', label: 'Goods', icon: '📦' },
    { key: 'energy', label: 'Energy', icon: '⚡' },
    { key: 'fighters', label: 'Fighters', icon: '🛸' },
    { key: 'torpedoes', label: 'Torpedoes', icon: '🚀' }
  ]

  const handleClaim = async () => {
    if (!claimName.trim()) return
    setLoading(true)
    try {
      await onClaim(claimName.trim())
      onRefresh()
    } finally {
      setLoading(false)
    }
  }

  const handleStore = async () => {
    if (storeQty <= 0) return
    setLoading(true)
    try {
      await onStore(storeResource, storeQty)
      onRefresh()
    } finally {
      setLoading(false)
    }
  }

  const handleWithdraw = async () => {
    if (withdrawQty <= 0) return
    setLoading(true)
    try {
      await onWithdraw(withdrawResource, withdrawQty)
      onRefresh()
    } finally {
      setLoading(false)
    }
  }

  const getMaxStore = (resource: string) => {
    return player.inventory[resource as keyof typeof player.inventory] || 0
  }

  const getMaxWithdraw = (resource: string) => {
    return planetStock[resource as keyof typeof planetStock] || 0
  }

  // Update planet stock when planet data changes
  // These effects are now handled in the main useEffect above

  const handleProductionAllocationUpdate = async () => {
    setLoading(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        throw new Error('No authentication token')
      }

        const response = await fetch('/api/planet/production-allocation', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`
          },
          body: JSON.stringify({
            planetId: currentPlanet.id,
          orePercent: productionAllocation.ore,
          organicsPercent: productionAllocation.organics,
          goodsPercent: productionAllocation.goods,
          energyPercent: productionAllocation.energy,
          fightersPercent: productionAllocation.fighters,
          torpedoesPercent: productionAllocation.torpedoes
        })
      })

      const result = await response.json()
      if (result.success) {
        onRefresh()
      } else {
        alert(result.error || 'Failed to update production allocation')
      }
    } catch (error) {
      console.error('Production allocation update error:', error)
      alert('Failed to update production allocation')
    } finally {
      setLoading(false)
    }
  }

  const handleTransfer = async () => {
    setLoading(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        throw new Error('No authentication token')
      }

      // Build transfers array from transferData
      const transfers = Object.entries(transferData)
        .filter(([_, data]) => data.quantity > 0)
        .map(([resource, data]) => ({
          resource,
          quantity: data.quantity,
          toPlanet: data.toPlanet
        }))

      if (transfers.length === 0) {
        alert('No transfers specified')
        return
      }

        const response = await fetch('/api/planet/transfer', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`
          },
          body: JSON.stringify({
            planetId: currentPlanet.id,
          transfers
        })
      })

      const result = await response.json()
      if (result.success) {
        onRefresh()
        setTransferData({}) // Clear transfer data
        alert(`Successfully transferred ${result.transfers} items`)
      } else {
        alert(result.error || 'Failed to transfer resources')
      }
    } catch (error) {
      console.error('Transfer error:', error)
      alert('Failed to transfer resources')
    } finally {
      setLoading(false)
    }
  }

  const handleRename = async () => {
    if (!renameName.trim() || loading) return
    
    setLoading(true)
    setStatusMessage('')
    
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setStatusMessage('Error: Not authenticated')
        return
      }

        const response = await fetch('/api/planet/rename', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`
          },
          body: JSON.stringify({
            planetId: currentPlanet.id,
          newName: renameName.trim()
        })
      })

      const result = await response.json()

      if (result.success) {
        setStatusMessage(`Planet renamed to "${result.newName}"`)
        setShowRenameForm(false)
        onRefresh()
      } else {
        setStatusMessage(`Error: ${result.error}`)
      }
    } catch (error) {
      console.error('Rename error:', error)
      setStatusMessage('Error: Failed to rename planet')
    } finally {
      setLoading(false)
    }
  }

  const handleBuildBase = async () => {
    if (loading) return
    
    setLoading(true)
    setStatusMessage('')
    
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) {
        setStatusMessage('Error: Not authenticated')
        return
      }

        const response = await fetch('/api/planet/build-base', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`
          },
          body: JSON.stringify({
            planetId: currentPlanet.id
        })
      })

      const result = await response.json()

      if (result.success) {
        setStatusMessage(`Base built successfully! Cost: ${result.baseCost.toLocaleString()} credits, Resources consumed: ${result.resourcesConsumed.toLocaleString()} each`)
        onRefresh()
      } else {
        setStatusMessage(`Error: ${result.error}`)
      }
    } catch (error) {
      console.error('Build base error:', error)
      setStatusMessage('Error: Failed to build base')
    } finally {
      setLoading(false)
    }
  }

  // Ownership states
  const isOwnedByMe = !!currentPlanet?.owner
  const isUnowned = !currentPlanet?.ownerName
  const isOwnedByOther = !isOwnedByMe && !isUnowned

  if (isUnowned) {
    return (
      <div className={styles.overlay} onClick={onClose}>
        <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
          <div className={styles.header}>
            <h3>🪐 Planet: {currentPlanet?.name}</h3>
            <button className={styles.closeBtn} onClick={onClose}>×</button>
          </div>
          <div className={styles.content}>
            <div className={styles.section}>
              <h4>Unclaimed Planet</h4>
              <p>This planet is available for colonization. Establish a colony to store and manage resources.</p>
              
              <div className={styles.costInfo}>
                <h4>Costs:</h4>
                <ul>
                  <li>💰 10,000 credits</li>
                  <li>⏱️ 5 turns</li>
                </ul>
              </div>

              <div className={styles.formGroup}>
                <label htmlFor="planetName">Planet Name:</label>
                <input
                  id="planetName"
                  type="text"
                  value={claimName}
                  onChange={(e) => setClaimName(e.target.value)}
                  placeholder="Enter planet name"
                  maxLength={20}
                />
              </div>
              
              <button 
                className={styles.actionBtn}
                onClick={handleClaim}
                disabled={loading || !claimName.trim() || (player.inventory.credits || 0) < 10000 || player.turns < 5}
              >
                {loading ? 'Claiming...' : `Claim Planet (10,000 credits, 5 turns)`}
              </button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // Owned by me or by others
  return (
    <div className={styles.overlay} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <h3>🪐 Planet: {currentPlanet?.name}</h3>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>
        
        {planets.length > 1 && (
          <div className={styles.slideshowNav}>
            <button 
              className={styles.slideBtn}
              onClick={goToPreviousPlanet}
              disabled={loading}
            >
              ←
            </button>
            <span className={styles.slideIndicator}>
              {currentPlanetIndex + 1} / {planets.length}
            </span>
            <button 
              className={styles.slideBtn}
              onClick={goToNextPlanet}
              disabled={loading}
            >
              →
            </button>
          </div>
        )}
        
        <div className={styles.tabs}>
          <button 
            className={`${styles.tab} ${activeTab === 'overview' ? styles.active : ''}`}
            onClick={() => setActiveTab('overview')}
          >
            Overview
          </button>
          {isOwnedByMe && (
            <>
              <button 
                className={`${styles.tab} ${activeTab === 'transfer' ? styles.active : ''}`}
                onClick={() => setActiveTab('transfer')}
              >
                Transfer
              </button>
              <button 
                className={`${styles.tab} ${activeTab === 'production' ? styles.active : ''}`}
                onClick={() => setActiveTab('production')}
              >
                Production
              </button>
              <button 
                className={`${styles.tab} ${activeTab === 'base' ? styles.active : ''}`}
                onClick={() => setActiveTab('base')}
              >
                Base
              </button>
            </>
          )}
        </div>
        
        <div className={styles.content}>
          {activeTab === 'overview' && (
            <div className={styles.tabContent}>
              <div className={styles.planetInfo}>
                <h4>Planet Information</h4>
                <div className={styles.infoGrid}>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Name:</span>
                    <span className={styles.value}>{currentPlanet?.name}</span>
                    <button 
                      className={styles.renameBtn}
                      onClick={() => setShowRenameForm(!showRenameForm)}
                    >
                      Rename
                    </button>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Population:</span>
                    <span className={styles.value}>
                      {currentPlanet?.colonists?.toLocaleString() || '0'} / {currentPlanet?.colonistsMax?.toLocaleString() || '100M'} colonists
                    </span>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Base Status:</span>
                    <span className={styles.value}>
                      {currentPlanet?.base?.built ? '✅ Built (+1 Tech Bonus)' : '❌ Not Built'}
                    </span>
                  </div>
                </div>
                
                {showRenameForm && (
                  <div className={styles.renameForm}>
                    <h5>Rename Planet</h5>
                    <div className={styles.formGroup}>
                      <input
                        type="text"
                        value={renameName}
                        onChange={(e) => setRenameName(e.target.value)}
                        placeholder="Enter new planet name"
                        className={styles.nameInput}
                        maxLength={50}
                      />
                      <button 
                        className={styles.actionBtn}
                        onClick={handleRename}
                        disabled={loading || !renameName.trim()}
                      >
                        {loading ? 'Renaming...' : 'Rename'}
                      </button>
                      <button 
                        className={styles.secondaryBtn}
                        onClick={() => setShowRenameForm(false)}
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                )}
              </div>
              
              
              <div className={styles.stockSummary}>
                <h4>Planet Resources</h4>
                <div className={styles.stockGrid}>
                  {resources.map(res => (
                    <div key={res.key} className={styles.stockItem}>
                      <span className={styles.stockIcon}>{res.icon}</span>
                      <span className={styles.stockLabel}>{res.label}</span>
                      <span className={styles.stockValue}>{planetStock[res.key as keyof typeof planetStock].toLocaleString()}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className={styles.defensesSection}>
                <h4>Defenses</h4>
                <div className={styles.defensesGrid}>
                  <div className={styles.defenseItem}>
                    <span className={styles.defenseIcon}>🛸</span>
                    <span className={styles.defenseLabel}>Fighters</span>
                    <span className={styles.defenseValue}>{(currentPlanet?.defenses?.fighters || 0).toLocaleString()}</span>
                  </div>
                  <div className={styles.defenseItem}>
                    <span className={styles.defenseIcon}>🚀</span>
                    <span className={styles.defenseLabel}>Torpedoes</span>
                    <span className={styles.defenseValue}>{(currentPlanet?.defenses?.torpedoes || 0).toLocaleString()}</span>
                  </div>
                </div>
                <div className={styles.defenseNote}>
                  <p>💡 Shields are calculated dynamically in combat based on your ship's shield level + planet energy</p>
                </div>
              </div>

              {/* Attack action for planets owned by others */}
              {isOwnedByOther && (
                <div className={styles.actionsRow}>
                  <button
                    className={styles.actionBtn}
                    disabled={loading || player.turns < 1}
                    onClick={async () => {
                      setLoading(true)
                      try {
                        const { data: { session } } = await supabase.auth.getSession()
                        if (!session?.access_token) {
                          alert('Not authenticated')
                          return
                        }
                        const resp = await fetch('/api/planet/attack', {
                          method: 'POST',
                          headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${session.access_token}`
                          },
                          body: JSON.stringify({ planet_id: currentPlanet.id })
                        })
                        const result = await resp.json()
                        if (resp.ok && result.success) {
                          onRefresh()
                          if (result.combat_result && result.combat_result.turnsUsed === 1) {
                            setUseShipCombatOverlay({ open: true, combatResult: result.combat_result, steps: result.result.steps || [] })
                            // Enable capture only if attacker won and planet armor (enemy hull) is 0
                            const win = result.combat_result.winner === 'player'
                            const planetArmor = result.combat_result.enemyShip?.hull || 0
                            setCanCapture(win && planetArmor <= 0)
                          } else {
                            setPlanetCombatData({ steps: result.result.steps || [], winner: result.result.winner })
                            setPlanetCombatOpen(true)
                            setCanCapture(result.result.winner === 'attacker')
                          }
                        } else {
                          alert(result.error || 'Attack failed')
                        }
                      } catch (e) {
                        console.error('Attack error', e)
                        alert('Attack failed')
                      } finally {
                        setLoading(false)
                      }
                    }}
                  >
                    {loading ? 'Attacking...' : 'Attack Planet'}
                  </button>
                </div>
              )}

            </div>
          )}

          {isOwnedByMe && activeTab === 'transfer' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Transfer Resources</h4>
                <p className={styles.sectionDescription}>
                  Transfer resources between your ship and planet. Enter quantities and check "To Planet?" to transfer from ship to planet.
                </p>
                
                <div className={styles.transferTable}>
                  <div className={styles.transferHeader}>
                    <div className={styles.transferCell}>Resource</div>
                    <div className={styles.transferCell}>Planet</div>
                    <div className={styles.transferCell}>Ship</div>
                    <div className={styles.transferCell}>Transfer</div>
                    <div className={styles.transferCell}>To Planet?</div>
                    <div className={styles.transferCell}>All?</div>
                  </div>
                  
                  {resources.map((resource) => (
                    <div key={resource.key} className={styles.transferRow}>
                      <div className={styles.transferCell}>
                        {resource.icon} {resource.label}
                      </div>
                      <div className={styles.transferCell}>
                        {planetStock[resource.key as keyof typeof planetStock].toLocaleString()}
                      </div>
                      <div className={styles.transferCell}>
                        {resource.key === 'credits' 
                          ? player.credits.toLocaleString() 
                          : player.inventory[resource.key as keyof typeof player.inventory].toLocaleString()}
                      </div>
                      <div className={styles.transferCell}>
                        <input
                          type="number"
                          min="0"
                          className={styles.transferInput}
                          placeholder="0"
                          value={transferData[resource.key]?.quantity || ''}
                          onChange={(e) => {
                            const quantity = parseInt(e.target.value) || 0
                            setTransferData(prev => ({
                              ...prev,
                              [resource.key]: {
                                ...prev[resource.key],
                                quantity
                              }
                            }))
                          }}
                        />
                      </div>
                      <div className={styles.transferCell}>
                        <input 
                          type="checkbox" 
                          className={styles.transferCheckbox}
                          checked={transferData[resource.key]?.toPlanet || false}
                          onChange={(e) => {
                            setTransferData(prev => ({
                              ...prev,
                              [resource.key]: {
                                ...prev[resource.key],
                                toPlanet: e.target.checked
                              }
                            }))
                          }}
                        />
                      </div>
                      <div className={styles.transferCell}>
                        <input 
                          type="checkbox" 
                          className={styles.transferCheckbox}
                          checked={transferData[resource.key]?.quantity > 0 && !transferData[resource.key]?.toPlanet}
                          onChange={(e) => {
                            if (e.target.checked) {
                              setTransferData(prev => ({
                                ...prev,
                                [resource.key]: {
                                  ...prev[resource.key],
                                  toPlanet: false
                                }
                              }))
                            }
                          }}
                        />
                      </div>
                    </div>
                  ))}
                  
                  <div className={styles.transferRow}>
                    <div className={styles.transferCell}>
                      👥 Colonists
                    </div>
                    <div className={styles.transferCell}>
                      {currentPlanet?.colonists?.toLocaleString() || '0'}
                    </div>
                    <div className={styles.transferCell}>
                      {player.inventory.colonists?.toLocaleString() || '0'}
                    </div>
                    <div className={styles.transferCell}>
                      <input
                        type="number"
                        min="0"
                        className={styles.transferInput}
                        placeholder="0"
                        value={transferData['colonists']?.quantity || ''}
                        onChange={(e) => {
                          const quantity = parseInt(e.target.value) || 0
                          setTransferData(prev => ({
                            ...prev,
                            colonists: {
                              ...prev.colonists,
                              quantity
                            }
                          }))
                        }}
                      />
                    </div>
                    <div className={styles.transferCell}>
                      <input 
                        type="checkbox" 
                        className={styles.transferCheckbox}
                        checked={transferData['colonists']?.toPlanet || false}
                        onChange={(e) => {
                          setTransferData(prev => ({
                            ...prev,
                            colonists: {
                              ...prev.colonists,
                              toPlanet: e.target.checked
                            }
                          }))
                        }}
                      />
                    </div>
                    <div className={styles.transferCell}>
                      <input 
                        type="checkbox" 
                        className={styles.transferCheckbox}
                        checked={transferData['colonists']?.quantity > 0 && !transferData['colonists']?.toPlanet}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setTransferData(prev => ({
                              ...prev,
                              colonists: {
                                ...prev.colonists,
                                toPlanet: false
                              }
                            }))
                          }
                        }}
                      />
                    </div>
                  </div>
                  
                </div>
                
                <div className={styles.transferActions}>
                  <button 
                    className={styles.actionBtn} 
                    disabled={loading}
                    onClick={handleTransfer}
                  >
                    {loading ? 'Transferring...' : 'Transfer'}
                  </button>
                  <button 
                    className={styles.secondaryBtn} 
                    disabled={loading}
                    onClick={() => setTransferData({})}
                  >
                    Reset
                  </button>
                </div>
              </div>
            </div>
          )}


          {isOwnedByMe && activeTab === 'production' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Production Status</h4>
                <div className={styles.productionInfo}>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Colonists:</span>
                    <span className={styles.productionValue}>
                      {currentPlanet?.colonists?.toLocaleString() || '0'} / {currentPlanet?.colonistsMax?.toLocaleString() || '100M'}
                    </span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Growth Rate:</span>
                    <span className={styles.productionValue}>0.5% per cycle</span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Last Growth:</span>
                    <span className={styles.productionValue}>
                      {currentPlanet?.lastColonistGrowth ? 
                        new Date(currentPlanet.lastColonistGrowth).toLocaleString() : 
                        'Never'
                      }
                    </span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Last Production:</span>
                    <span className={styles.productionValue}>
                      {currentPlanet?.lastProduction ? 
                        new Date(currentPlanet.lastProduction).toLocaleString() : 
                        'Never'
                      }
                    </span>
                  </div>
                </div>
              </div>
              
              <div className={styles.section}>
                <h4>Production Allocation</h4>
                <p className={styles.sectionDescription}>
                  Allocate colonists to different production types. Remaining colonists generate credits.
                </p>
                
                <div className={styles.allocationGrid}>
                  {resources.map((resource) => (
                    <div key={resource.key} className={styles.allocationItem}>
                      <label className={styles.allocationLabel}>
                        {resource.icon} {resource.label}
                      </label>
                      <div className={styles.allocationInput}>
                        <input
                          type="number"
                          min="0"
                          max="100"
                          value={productionAllocation[resource.key as keyof typeof productionAllocation]}
                          onChange={(e) => {
                            const value = parseInt(e.target.value) || 0
                            setProductionAllocation(prev => ({
                              ...prev,
                              [resource.key]: Math.min(100, Math.max(0, value))
                            }))
                          }}
                          className={styles.percentInput}
                        />
                        <span className={styles.percentSymbol}>%</span>
                      </div>
                    </div>
                  ))}
                  
                  <div className={styles.allocationItem}>
                    <label className={styles.allocationLabel}>
                      💰 Credits (Remaining)
                    </label>
                    <div className={styles.allocationInput}>
                      <span className={styles.creditsPercent}>
                        {100 - (productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes)}%
                      </span>
                    </div>
                  </div>
                </div>
                
                <div className={styles.allocationSummary}>
                  <div className={styles.summaryItem}>
                    <span>Total Allocation:</span>
                    <span className={productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes > 100 ? styles.error : styles.success}>
                      {productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes}%
                    </span>
                  </div>
                </div>
                
                <button 
                  className={styles.actionBtn}
                  onClick={handleProductionAllocationUpdate}
                  disabled={loading || (productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes) > 100}
                >
                  {loading ? 'Updating...' : 'Update Production Allocation'}
                </button>
              </div>
            </div>
          )}

          {isOwnedByMe && activeTab === 'base' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Planet Base</h4>
                
                {currentPlanet?.base?.built ? (
                  <div className={styles.baseBuilt}>
                    <div className={styles.baseStatus}>
                      <h5>✅ Base Built</h5>
                      <p>Your planet base is operational and provides +1 tech bonus for torpedoes, shields, and beam weapons in combat.</p>
                    </div>
                  </div>
                ) : (
                  <div className={styles.baseBuilding}>
                    <div className={styles.baseInfo}>
                      <p>Build a base to gain +1 tech bonus for torpedoes, shields, and beam weapons in combat.</p>
                      
                      <div className={styles.baseRequirementsGrid}>
                        <div className={styles.baseRequirements}>
                          <h5>Requirements:</h5>
                          <ul>
                            <li>💰 {currentPlanet?.base?.cost.toLocaleString() || '50,000'} credits</li>
                            <li>👥 {currentPlanet?.base?.colonistsRequired.toLocaleString() || '10,000'} colonists</li>
                            <li>🪨 {currentPlanet?.base?.resourcesRequired.toLocaleString() || '10,000'} ore</li>
                            <li>🌿 {currentPlanet?.base?.resourcesRequired.toLocaleString() || '10,000'} organics</li>
                            <li>📦 {currentPlanet?.base?.resourcesRequired.toLocaleString() || '10,000'} goods</li>
                            <li>⚡ {currentPlanet?.base?.resourcesRequired.toLocaleString() || '10,000'} energy</li>
                          </ul>
                        </div>
                        
                        <div className={styles.baseStatus}>
                          <h5>Current Status:</h5>
                          <ul>
                            <li className={player.credits >= (currentPlanet?.base?.cost || 50000) ? styles.requirementMet : styles.requirementNotMet}>
                              💰 Ship Credits: {player.credits.toLocaleString()} / {(currentPlanet?.base?.cost || 50000).toLocaleString()}
                            </li>
                            <li className={(currentPlanet?.colonists || 0) >= (currentPlanet?.base?.colonistsRequired || 10000) ? styles.requirementMet : styles.requirementNotMet}>
                              👥 Colonists: {(currentPlanet?.colonists || 0).toLocaleString()} / {(currentPlanet?.base?.colonistsRequired || 10000).toLocaleString()}
                            </li>
                            <li className={(planetStock.ore || 0) >= (currentPlanet?.base?.resourcesRequired || 10000) ? styles.requirementMet : styles.requirementNotMet}>
                              🪨 Planet Ore: {(planetStock.ore || 0).toLocaleString()} / {(currentPlanet?.base?.resourcesRequired || 10000).toLocaleString()}
                            </li>
                            <li className={(planetStock.organics || 0) >= (currentPlanet?.base?.resourcesRequired || 10000) ? styles.requirementMet : styles.requirementNotMet}>
                              🌿 Planet Organics: {(planetStock.organics || 0).toLocaleString()} / {(currentPlanet?.base?.resourcesRequired || 10000).toLocaleString()}
                            </li>
                            <li className={(planetStock.goods || 0) >= (currentPlanet?.base?.resourcesRequired || 10000) ? styles.requirementMet : styles.requirementNotMet}>
                              📦 Planet Goods: {(planetStock.goods || 0).toLocaleString()} / {(currentPlanet?.base?.resourcesRequired || 10000).toLocaleString()}
                            </li>
                            <li className={(planetStock.energy || 0) >= (currentPlanet?.base?.resourcesRequired || 10000) ? styles.requirementMet : styles.requirementNotMet}>
                              ⚡ Planet Energy: {(planetStock.energy || 0).toLocaleString()} / {(currentPlanet?.base?.resourcesRequired || 10000).toLocaleString()}
                            </li>
                          </ul>
                        </div>
                      </div>
                      
                      <button 
                        className={styles.actionBtn}
                        onClick={handleBuildBase}
                        disabled={loading || 
                          player.credits < (currentPlanet?.base?.cost || 50000) ||
                          (currentPlanet?.colonists || 0) < (currentPlanet?.base?.colonistsRequired || 10000) ||
                          (planetStock.ore || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                          (planetStock.organics || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                          (planetStock.goods || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                          (planetStock.energy || 0) < (currentPlanet?.base?.resourcesRequired || 10000)
                        }
                      >
                        {loading ? 'Building...' : 'Build Base'}
                      </button>
                      
                      {(planetStock.ore || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                       (planetStock.organics || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                       (planetStock.goods || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ||
                       (planetStock.energy || 0) < (currentPlanet?.base?.resourcesRequired || 10000) ? (
                        <div className={styles.warningMessage}>
                          ⚠️ You need to transfer resources to the planet first using the Transfer tab. This will consume 1 turn per transfer.
                        </div>
                      ) : null}
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
        
        {statusMessage && (
          <div className={styles.statusMessage}>
            {statusMessage}
          </div>
        )}

        {/* Capture Planet CTA shown when defeated */}
        {isOwnedByOther && canCapture && (
          <div className={styles.actionsRow}>
            <button
              className={styles.actionBtn}
              disabled={loading}
              onClick={async () => {
                setLoading(true)
                try {
                  const { data: { session } } = await supabase.auth.getSession()
                  if (!session?.access_token) { alert('Not authenticated'); return }
                  const resp = await fetch('/api/planet/capture', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${session.access_token}` },
                    body: JSON.stringify({ planet_id: currentPlanet.id })
                  })
                  const j = await resp.json()
                  if (!resp.ok) { alert(j.error || 'Capture failed'); return }
                  setStatusMessage('Planet captured!')
                  setCanCapture(false)
                  onRefresh()
                } finally {
                  setLoading(false)
                }
              }}
            >
              Capture Planet
            </button>
          </div>
        )}
      </div>
      <PlanetCombatOverlay
        open={planetCombatOpen}
        onClose={() => setPlanetCombatOpen(false)}
        playerShip={playerShip || {}}
        planet={{ name: currentPlanet?.name || 'Planet', defenses: currentPlanet?.defenses as any, stock: currentPlanet?.stock as any }}
        steps={planetCombatData?.steps || []}
        winner={planetCombatData?.winner || 'draw'}
      />

      {useShipCombatOverlay?.open && (
        <CombatOverlay
          open={useShipCombatOverlay.open}
          onClose={() => setUseShipCombatOverlay(null)}
          playerShip={playerShip}
          enemyShip={{ name: currentPlanet?.name || 'Planet', hull_lvl: 1, shield: currentPlanet?.defenses?.shields || 0, fighters: currentPlanet?.defenses?.fighters || 0, torpedoes: currentPlanet?.defenses?.torpedoes || 0, energy: currentPlanet?.stock?.energy || 0 }}
          combatResult={useShipCombatOverlay.combatResult}
          combatSteps={useShipCombatOverlay.steps as any}
          isCombatComplete={true}
          enemyIsPlanet={true}
          planetId={currentPlanet?.id}
          onCapturePlanet={async () => {
            try {
              const { data: { session } } = await supabase.auth.getSession()
              if (!session?.access_token) return
              const resp = await fetch('/api/planet/capture', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${session.access_token}` },
                body: JSON.stringify({ planet_id: currentPlanet.id })
              })
              const j = await resp.json()
              if (!resp.ok) { alert(j.error || 'Capture failed'); return }
              setStatusMessage('Planet captured!')
              setCanCapture(false)
              onRefresh()
            } catch {}
          }}
        />
      )}
    </div>
  )
}
