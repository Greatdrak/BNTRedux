import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase-client'
import styles from './PlanetOverlay.module.css'

interface PlanetOverlayProps {
  planet: {
    id: string
    name: string
    owner: boolean
    colonists?: number
    colonistsMax?: number
    stock?: {
      ore: number
      organics: number
      goods: number
      energy: number
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
  }
  player: {
    credits: number
    turns: number
    inventory: {
      ore: number
      organics: number
      goods: number
      energy: number
    }
  }
  onClose: () => void
  onClaim: (name: string) => void
  onStore: (resource: string, qty: number) => void
  onWithdraw: (resource: string, qty: number) => void
  onRefresh: () => void
}

export default function PlanetOverlay({ 
  planet, 
  player, 
  onClose, 
  onClaim, 
  onStore, 
  onWithdraw, 
  onRefresh 
}: PlanetOverlayProps) {
  const [claimName, setClaimName] = useState('Colony')
  const [storeResource, setStoreResource] = useState('ore')
  const [storeQty, setStoreQty] = useState(1)
  const [withdrawResource, setWithdrawResource] = useState('ore')
  const [withdrawQty, setWithdrawQty] = useState(1)
  const [loading, setLoading] = useState(false)
  const [activeTab, setActiveTab] = useState<'overview' | 'transfer'>('overview')
  const [planetStock, setPlanetStock] = useState({
    ore: planet.stock?.ore || 0,
    organics: planet.stock?.organics || 0,
    goods: planet.stock?.goods || 0,
    energy: planet.stock?.energy || 0
  })
  
  const [productionAllocation, setProductionAllocation] = useState({
    ore: planet.productionAllocation?.ore || 0,
    organics: planet.productionAllocation?.organics || 0,
    goods: planet.productionAllocation?.goods || 0,
    energy: planet.productionAllocation?.energy || 0,
    fighters: planet.productionAllocation?.fighters || 0,
    torpedoes: planet.productionAllocation?.torpedoes || 0
  })

  // Transfer state
  const [transferData, setTransferData] = useState<Record<string, { quantity: number, toPlanet: boolean }>>({})

  const resources = [
    { key: 'ore', label: 'Ore', icon: '🪨' },
    { key: 'organics', label: 'Organics', icon: '🌿' },
    { key: 'goods', label: 'Goods', icon: '📦' },
    { key: 'energy', label: 'Energy', icon: '⚡' }
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
  useEffect(() => {
    if (planet.stock) {
      setPlanetStock(planet.stock)
    }
  }, [planet.stock])
  
  // Update production allocation when planet data changes
  useEffect(() => {
    if (planet.productionAllocation) {
      setProductionAllocation(planet.productionAllocation)
    }
  }, [planet.productionAllocation])

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
          planetId: planet.id,
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
          planetId: planet.id,
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

  if (!planet.owner) {
    return (
      <div className={styles.overlay} onClick={onClose}>
        <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
          <div className={styles.header}>
            <h3>🪐 Planet: {planet.name}</h3>
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

  return (
    <div className={styles.overlay} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <h3>🪐 Planet: {planet.name}</h3>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>
        
        <div className={styles.tabs}>
          <button 
            className={`${styles.tab} ${activeTab === 'overview' ? styles.active : ''}`}
            onClick={() => setActiveTab('overview')}
          >
            Overview
          </button>
          <button 
            className={`${styles.tab} ${activeTab === 'transfer' ? styles.active : ''}`}
            onClick={() => setActiveTab('transfer')}
          >
            Transfer
          </button>
        </div>
        
        <div className={styles.content}>
          {activeTab === 'overview' && (
            <div className={styles.tabContent}>
              <div className={styles.planetInfo}>
                <h4>Planet Information</h4>
                <div className={styles.infoGrid}>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Name:</span>
                    <span className={styles.value}>{planet.name}</span>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Population:</span>
                    <span className={styles.value}>
                      {planet.colonists?.toLocaleString() || '0'} / {planet.colonistsMax?.toLocaleString() || '100M'} colonists
                    </span>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Defense Level:</span>
                    <span className={styles.value}>
                      {planet.defenses ? 
                        `${planet.defenses.fighters} fighters, ${planet.defenses.torpedoes} torpedoes, ${planet.defenses.shields} shields` : 
                        'No defenses'
                      }
                    </span>
                  </div>
                </div>
              </div>
              
              <div className={styles.stockSummary}>
                <h4>Resource Stock</h4>
                <div className={styles.stockGrid}>
                  {resources.map(res => (
                    <div key={res.key} className={styles.stockItem}>
                      <span className={styles.stockIcon}>{res.icon}</span>
                      <span className={styles.stockLabel}>{res.key}</span>
                      <span className={styles.stockValue}>{planetStock[res.key as keyof typeof planetStock].toLocaleString()}</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className={styles.section}>
                <h4>Production Allocation</h4>
                <p className={styles.sectionDescription}>
                  Allocate colonists to different production types. Remaining colonists generate credits.
                </p>
                
                <div className={styles.productionTable}>
                  <div className={styles.productionHeader}>
                    <div className={styles.productionCell}>Resource</div>
                    <div className={styles.productionCell}>Current %</div>
                    <div className={styles.productionCell}>New %</div>
                  </div>
                  
                  {productionItems.map((item) => (
                    <div key={item.key} className={styles.productionRow}>
                      <div className={styles.productionCell}>
                        {item.icon} {item.label}
                      </div>
                      <div className={styles.productionCell}>
                        {productionAllocation[item.key as keyof typeof productionAllocation]}%
                      </div>
                      <div className={styles.productionCell}>
                        <input
                          type="number"
                          min="0"
                          max="100"
                          value={productionAllocation[item.key as keyof typeof productionAllocation]}
                          onChange={(e) => {
                            const value = parseInt(e.target.value) || 0
                            setProductionAllocation(prev => ({
                              ...prev,
                              [item.key]: Math.min(100, Math.max(0, value))
                            }))
                          }}
                          className={styles.percentInput}
                        />
                      </div>
                    </div>
                  ))}
                  
                  <div className={styles.productionRow}>
                    <div className={styles.productionCell}>
                      💰 Credits (Remaining)
                    </div>
                    <div className={styles.productionCell}>
                      {100 - (productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes + productionAllocation.fighters + productionAllocation.torpedoes)}%
                    </div>
                    <div className={styles.productionCell}>
                      <span className={styles.creditsPercent}>
                        {100 - (productionAllocation.ore + productionAllocation.organics + productionAllocation.goods + productionAllocation.energy + productionAllocation.fighters + productionAllocation.torpedoes + productionAllocation.fighters + productionAllocation.torpedoes)}%
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

          {activeTab === 'transfer' && (
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
                        {player.inventory[resource.key as keyof typeof player.inventory].toLocaleString()}
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
                      {planet.colonists?.toLocaleString() || '0'}
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
                  
                  <div className={styles.transferRow}>
                    <div className={styles.transferCell}>
                      💰 Credits
                    </div>
                    <div className={styles.transferCell}>
                      {planetStock.credits?.toLocaleString() || '0'}
                    </div>
                    <div className={styles.transferCell}>
                      {player.inventory.credits?.toLocaleString() || '0'}
                    </div>
                    <div className={styles.transferCell}>
                      <input
                        type="number"
                        min="0"
                        className={styles.transferInput}
                        placeholder="0"
                        value={transferData['credits']?.quantity || ''}
                        onChange={(e) => {
                          const quantity = parseInt(e.target.value) || 0
                          setTransferData(prev => ({
                            ...prev,
                            credits: {
                              ...prev.credits,
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
                        checked={transferData['credits']?.toPlanet || false}
                        onChange={(e) => {
                          setTransferData(prev => ({
                            ...prev,
                            credits: {
                              ...prev.credits,
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
                        checked={transferData['credits']?.quantity > 0 && !transferData['credits']?.toPlanet}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setTransferData(prev => ({
                              ...prev,
                              credits: {
                                ...prev.credits,
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

          {activeTab === 'defenses' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Defense Systems</h4>
                <div className={styles.defenseGrid}>
                  <div className={styles.defenseItem}>
                    <span className={styles.defenseIcon}>🛸</span>
                    <span className={styles.defenseLabel}>Fighters</span>
                    <span className={styles.defenseValue}>{planet.defenses?.fighters || 0}</span>
                  </div>
                  <div className={styles.defenseItem}>
                    <span className={styles.defenseIcon}>🚀</span>
                    <span className={styles.defenseLabel}>Torpedoes</span>
                    <span className={styles.defenseValue}>{planet.defenses?.torpedoes || 0}</span>
                  </div>
                  <div className={styles.defenseItem}>
                    <span className={styles.defenseIcon}>🛡️</span>
                    <span className={styles.defenseLabel}>Shields</span>
                    <span className={styles.defenseValue}>{planet.defenses?.shields || 0}</span>
                  </div>
                </div>
                <div className={styles.placeholder}>
                  <p>🛡️ Defense management coming soon!</p>
                  <p>Future features will include:</p>
                  <ul>
                    <li>Deploy fighters from ship</li>
                    <li>Build torpedo launchers</li>
                    <li>Install shield generators</li>
                    <li>Defense upgrades</li>
                  </ul>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'production' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Production Status</h4>
                <div className={styles.productionInfo}>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Colonists:</span>
                    <span className={styles.productionValue}>
                      {planet.colonists?.toLocaleString() || '0'} / {planet.colonistsMax?.toLocaleString() || '100M'}
                    </span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Growth Rate:</span>
                    <span className={styles.productionValue}>0.5% per cycle</span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Last Growth:</span>
                    <span className={styles.productionValue}>
                      {planet.lastColonistGrowth ? 
                        new Date(planet.lastColonistGrowth).toLocaleString() : 
                        'Never'
                      }
                    </span>
                  </div>
                  <div className={styles.productionItem}>
                    <span className={styles.productionLabel}>Last Production:</span>
                    <span className={styles.productionValue}>
                      {planet.lastProduction ? 
                        new Date(planet.lastProduction).toLocaleString() : 
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
        </div>
      </div>
    </div>
  )
}
