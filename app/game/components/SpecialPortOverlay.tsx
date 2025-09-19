'use client'

import { useState, useEffect, useMemo } from 'react'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './SpecialPortOverlay.module.css'

interface SpecialPortOverlayProps {
  open: boolean
  onClose: () => void
  shipData?: {
    name: string
    hull: number
    hull_max: number
    hull_lvl: number
    shield: number
    shield_max: number
    shield_lvl: number
    engine_lvl: number
    comp_lvl: number
    sensor_lvl: number
    cargo: number
    fighters: number
    torpedoes: number
  }
  playerCredits?: number
  shipCredits?: number
  onUpgrade: (attr: string) => void
  upgradeLoading?: boolean
  universeId?: string
  onStatusMessage?: (message: string, type: 'success' | 'error' | 'info') => void
}

interface CapacityData {
  fighters: { current: number; max: number; level: number }
  torpedoes: { current: number; max: number; level: number }
  armor: { current: number; max: number; level: number }
  colonists: { current: number; max: number; level: number }
  energy: { current: number; max: number; level: number }
  devices: {
    space_beacons: { current: number; max: number; cost: number }
    warp_editors: { current: number; max: number; cost: number }
    genesis_torpedoes: { current: number; max: number; cost: number }
    mine_deflectors: { current: number; max: number; cost: number }
    emergency_warp: { current: boolean; max: number; cost: number }
    escape_pod: { current: boolean; max: number; cost: number }
    fuel_scoop: { current: boolean; max: number; cost: number }
    last_seen: { current: boolean; max: number; cost: number }
  }
}

export default function SpecialPortOverlay({ 
  open, 
  onClose, 
  shipData, 
  playerCredits = 0,
  shipCredits = 0,
  onUpgrade,
  upgradeLoading = false,
  universeId,
  onStatusMessage
}: SpecialPortOverlayProps) {
  // State for classic BNT Special Port features
  const [activeTab, setActiveTab] = useState<'upgrades' | 'devices'>('upgrades')
  const [deviceQuantities, setDeviceQuantities] = useState<Record<string, number>>({})
  const [totalCost, setTotalCost] = useState(0)
  const [purchaseLoading, setPurchaseLoading] = useState(false)
  const [statusMessage, setStatusMessage] = useState<{message: string, type: 'success' | 'error' | 'info'} | null>(null)

  // Authenticated fetcher for capacity data
  const capacityFetcher = async (url: string) => {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('No session')
    
    const response = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${session.access_token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error?.message || 'Failed to fetch capacity data')
    }
    
    return response.json()
  }

  // Fetch ship capacity data
  const { data: capacityData, error: capacityError, mutate: mutateCapacity } = useSWR<CapacityData>(
    universeId ? `/api/ship/capacity?universe_id=${universeId}` : null,
    capacityFetcher
  )

  // Auto-refresh capacity data when shipData changes (after upgrades)
  useEffect(() => {
    if (shipData && universeId) {
      mutateCapacity()
    }
  }, [shipData?.comp_lvl, shipData?.torp_launcher_lvl, shipData?.hull_lvl, shipData?.power_lvl, mutateCapacity, universeId])

  // Combined devices and items - using real capacity data (memoized to prevent React reconciliation issues)
  const devices = useMemo(() => {
    if (!capacityData) return []
    
    return [
      // Ship Items
      { name: 'Fighters', cost: 50, current: capacityData.fighters.current, max: capacityData.fighters.max, type: 'quantity', category: 'item' },
      { name: 'Armor Points', cost: 5, current: capacityData.armor.current, max: capacityData.armor.max, type: 'quantity', category: 'item' },
      { name: 'Torpedoes', cost: 25, current: capacityData.torpedoes.current, max: capacityData.torpedoes.max, type: 'quantity', category: 'item' },
      { name: 'Colonists', cost: 500, current: capacityData.colonists.current, max: capacityData.colonists.max, type: 'quantity', category: 'item' },
      { name: 'Energy', cost: 1, current: capacityData.energy.current, max: capacityData.energy.max, type: 'quantity', category: 'item' },
      // Special Devices
      { name: 'Genesis Torpedoes', cost: 1000000, current: capacityData.devices.genesis_torpedoes.current, max: capacityData.devices.genesis_torpedoes.max, type: 'quantity', category: 'device' },
      { name: 'Space Beacons', cost: 1000000, current: capacityData.devices.space_beacons.current, max: capacityData.devices.space_beacons.max, type: 'quantity', category: 'device' },
      { name: 'Emergency Warp Device', cost: 1000000, current: capacityData.devices.emergency_warp.current ? 1 : 0, max: 1, type: 'checkbox', category: 'device' },
      { name: 'Warp Editors', cost: 1000000, current: capacityData.devices.warp_editors.current, max: capacityData.devices.warp_editors.max, type: 'quantity', category: 'device' },
      { name: 'Mine Deflectors', cost: 1000, current: capacityData.devices.mine_deflectors.current, max: -1, type: 'quantity', category: 'device' },
      { name: 'Escape Pod', cost: 1000000, current: capacityData.devices.escape_pod.current ? 1 : 0, max: 1, type: 'checkbox', category: 'device' },
      { name: 'Fuel Scoop', cost: 100000, current: capacityData.devices.fuel_scoop.current ? 1 : 0, max: 1, type: 'checkbox', category: 'device' },
      { name: 'Last Ship Seen Device', cost: 10000000, current: capacityData.devices.last_seen.current ? 1 : 0, max: 1, type: 'checkbox', category: 'device' }
    ]
  }, [capacityData])

  const upgradeCosts = {
    engine: 500 * (shipData?.engine_lvl || 1),
    computer: 400 * (shipData?.comp_lvl || 1),
    sensors: 400 * (shipData?.sensor_lvl || 1),
    shields: 300 * (shipData?.shield_lvl || 1),
    hull: 2000 * (shipData?.hull_lvl || 1)
  }

  // Calculate total cost for devices and items
  useEffect(() => {
    let cost = 0
    
    // Combined devices and items costs
    devices.forEach(device => {
      const qty = deviceQuantities[device.name] || 0
      cost += qty * device.cost
    })
    
    setTotalCost(cost)
  }, [deviceQuantities, devices])

  const canAfford = (attr: string) => {
    return shipCredits >= upgradeCosts[attr as keyof typeof upgradeCosts]
  }

  const canAffordPurchase = () => {
    return shipCredits >= totalCost && totalCost > 0
  }

  const handleMaxPurchase = (deviceName: string) => {
    const device = devices.find(d => d.name === deviceName)
    if (!device) return
    
    const maxPurchaseable = device.max - device.current
    if (maxPurchaseable > 0) {
      setDeviceQuantities(prev => ({
        ...prev,
        [deviceName]: maxPurchaseable
      }))
    }
  }

  const handlePurchase = async () => {
    if (!universeId || !canAffordPurchase()) return

    setPurchaseLoading(true)
    try {
      const purchases = []
      
      // Add purchases with security validation
      devices.forEach(device => {
        const qty = deviceQuantities[device.name] || 0
        if (qty > 0) {
          // Security: Validate quantity doesn't exceed capacity
          const maxPurchaseable = device.max - device.current
          const actualQty = Math.min(qty, maxPurchaseable)
          
          if (actualQty > 0) {
            purchases.push({
              type: device.category === 'device' ? 'device' : device.name.toLowerCase(),
              name: device.name,
              quantity: actualQty,
              cost: device.cost
            })
          }
        }
      })

      const { data: { session } } = await supabase.auth.getSession()
      if (!session) {
        onStatusMessage?.('No session found. Please log in again.', 'error')
        return
      }

      const response = await fetch(`/api/special-port/purchase?universe_id=${universeId}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({ purchases })
      })

      if (!response.ok) {
        const error = await response.json()
        setStatusMessage({
          message: `Purchase failed: ${error.error?.message || 'Unknown error'}`,
          type: 'error'
        })
        return
      }

      const result = await response.json()
      
      // Create detailed success message
      const purchasedItems = purchases.map(p => `${p.quantity} ${p.name}`).join(', ')
      setStatusMessage({
        message: `Purchase successful! Bought: ${purchasedItems}. Total cost: ${result.total_cost.toLocaleString()} credits. Remaining credits: ${result.remaining_credits.toLocaleString()}`,
        type: 'success'
      })
      
      // Reset quantities
      setDeviceQuantities({})
      setTotalCost(0)
      
      // Refresh capacity data
      mutateCapacity()
      
    } catch (error) {
      console.error('Purchase error:', error)
      setStatusMessage({
        message: 'Purchase failed due to network error',
        type: 'error'
      })
    } finally {
      setPurchaseLoading(false)
    }
  }

  if (!open) return null

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <h2>SPECIAL PORT: SHIP UPGRADES</h2>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>

        <div className={styles.content}>
          {/* Credits Display */}
          <div className={styles.shipStatus}>
            <div className={styles.shipInfo}>
              <div className={styles.shipName}>{shipData?.name || 'Unknown Ship'}</div>
              <div className={styles.credits}>Credits: {shipCredits.toLocaleString()}</div>
            </div>
            <div className={styles.specialLinks}>
              <a href="#" className={styles.specialLink}>IGB Banking Terminal</a>
              <a href="#" className={styles.specialLink}>Place or view bounties</a>
            </div>
          </div>

          {/* Tab Navigation */}
          <div className={styles.tabNav}>
            <button 
              className={`${styles.tabBtn} ${activeTab === 'upgrades' ? styles.tabActive : ''}`}
              onClick={() => setActiveTab('upgrades')}
            >
              Ship Upgrades
            </button>
            <button 
              className={`${styles.tabBtn} ${activeTab === 'devices' ? styles.tabActive : ''}`}
              onClick={() => setActiveTab('devices')}
            >
              Devices & Items
            </button>
          </div>

          {/* Tab Content */}
          {activeTab === 'upgrades' && (
            <>
              {/* Ship Attributes */}
              <div className={styles.attributes}>
                <h3>Ship Attributes</h3>
                <div className={styles.attrGrid}>
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Hull</div>
                    <div className={styles.attrValue}>
                      {shipData?.hull || 0} / {shipData?.hull_max || 0}
                      <span className={styles.level}>Lv.{shipData?.hull_lvl || 1}</span>
                    </div>
                  </div>
                  
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Shields</div>
                    <div className={styles.attrValue}>
                      {shipData?.shield || 0} / {shipData?.shield_max || 0}
                      <span className={styles.level}>Lv.{shipData?.shield_lvl || 0}</span>
                    </div>
                  </div>
                  
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Engines</div>
                    <div className={styles.attrValue}>
                      Level {shipData?.engine_lvl || 1}
                    </div>
                  </div>
                  
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Computer</div>
                    <div className={styles.attrValue}>
                      Level {shipData?.comp_lvl || 1}
                    </div>
                  </div>
                  
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Sensors</div>
                    <div className={styles.attrValue}>
                      Level {shipData?.sensor_lvl || 1}
                    </div>
                  </div>
                  
                  <div className={styles.attrItem}>
                    <div className={styles.attrLabel}>Cargo</div>
                    <div className={styles.attrValue}>
                      {shipData?.cargo || 0} units
                    </div>
                  </div>
                </div>
              </div>

              {/* Upgrades */}
              <div className={styles.upgrades}>
                <h3>Available Upgrades</h3>
                <div className={styles.upgradeGrid}>
                  {Object.entries(upgradeCosts).map(([attr, cost]) => (
                    <div key={attr} className={styles.upgradeItem}>
                      <div className={styles.upgradeInfo}>
                        <div className={styles.upgradeName}>
                          {attr.charAt(0).toUpperCase() + attr.slice(1)}
                        </div>
                        <div className={styles.upgradeCost}>
                          {cost.toLocaleString()} cr
                        </div>
                      </div>
                      <button
                        className={`${styles.upgradeBtn} ${!canAfford(attr) ? styles.disabled : ''}`}
                        onClick={() => onUpgrade(attr)}
                        disabled={!canAfford(attr) || upgradeLoading}
                      >
                        {upgradeLoading ? 'Upgrading...' : 'Upgrade'}
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            </>
          )}

          {activeTab === 'devices' && (
            <div className={styles.horizontalLayout}>
              <div className={styles.devicesSection}>
                <h3>Devices</h3>
                <table className={styles.deviceTable}>
                  <thead>
                    <tr>
                      <th>Device</th>
                      <th>Cost</th>
                      <th>Current</th>
                      <th>Max</th>
                      <th>Quantity</th>
                      <th>Max</th>
                    </tr>
                  </thead>
                  <tbody>
                    {devices.filter(device => device.category === 'device').map((device) => (
                      <tr key={device.name}>
                        <td>{device.name}</td>
                        <td className={styles.cost}>{device.cost.toLocaleString()}</td>
                        <td>{device.current}</td>
                        <td className={styles.maxValue}>
                          {device.type === 'checkbox' ? (
                            device.current > 0 ? 'Owned' : 'Available'
                          ) : (
                            device.max === -1 ? 'Unlimited' : device.max === 0 ? 'Full' : device.max
                          )}
                        </td>
                        <td>
                          {device.type === 'checkbox' ? (
                            device.current > 0 ? (
                              <span>Owned</span>
                            ) : (
                              <input 
                                type="checkbox" 
                                className={styles.deviceCheckbox}
                                checked={deviceQuantities[device.name] > 0}
                                onChange={(e) => setDeviceQuantities({
                                  ...deviceQuantities,
                                  [device.name]: e.target.checked ? 1 : 0
                                })}
                              />
                            )
                          ) : (
                            device.current >= device.max && device.max > 0 ? (
                              <span>Full</span>
                            ) : (
                              <input 
                                type="number" 
                                className={styles.quantityInput}
                                value={deviceQuantities[device.name] || 0}
                                onChange={(e) => setDeviceQuantities({
                                  ...deviceQuantities,
                                  [device.name]: Math.max(0, parseInt(e.target.value) || 0)
                                })}
                                min="0"
                                max={device.max === -1 ? undefined : device.max - device.current}
                              />
                            )
                          )}
                        </td>
                        <td>
                          {device.type === 'quantity' && device.max > device.current && device.max > 0 && (
                            <button 
                              className={styles.maxBtn}
                              onClick={() => handleMaxPurchase(device.name)}
                              title={`Buy maximum (${device.max - device.current})`}
                            >
                              Max
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className={styles.itemsSection}>
                <h3>Items</h3>
                <table className={styles.deviceTable}>
                  <thead>
                    <tr>
                      <th>Item</th>
                      <th>Cost</th>
                      <th>Current</th>
                      <th>Max</th>
                      <th>Quantity</th>
                      <th>Max</th>
                    </tr>
                  </thead>
                  <tbody>
                    {devices.filter(device => device.category === 'item').map((device) => (
                      <tr key={device.name}>
                        <td>{device.name}</td>
                        <td className={styles.cost}>{device.cost.toLocaleString()}</td>
                        <td>{device.current}</td>
                        <td className={styles.maxValue}>
                          {device.type === 'checkbox' ? (
                            device.current > 0 ? 'Owned' : 'Available'
                          ) : (
                            device.max === -1 ? 'Unlimited' : device.max === 0 ? 'Full' : device.max
                          )}
                        </td>
                        <td>
                          {device.current >= device.max && device.max > 0 ? (
                            <span>Full</span>
                          ) : (
                            <input 
                              type="number" 
                              className={styles.quantityInput}
                              value={deviceQuantities[device.name] || 0}
                              onChange={(e) => setDeviceQuantities({
                                ...deviceQuantities,
                                [device.name]: Math.max(0, parseInt(e.target.value) || 0)
                              })}
                              min="0"
                              max={device.max === -1 ? undefined : device.max - device.current}
                            />
                          )}
                        </td>
                        <td>
                          {device.max > device.current && device.max > 0 && (
                            <button 
                              className={styles.maxBtn}
                              onClick={() => handleMaxPurchase(device.name)}
                              title={`Buy maximum (${device.max - device.current})`}
                            >
                              Max
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Purchase Section (for devices and items) */}
          {activeTab === 'devices' && (
            <div className={styles.purchaseSection}>
              <div className={styles.totalCost}>
                <span className={styles.totalCostLabel}>Total cost:</span>
                <span className={styles.totalCostValue}>{totalCost.toLocaleString()}</span>
              </div>
              <button 
                className={styles.buyButton}
                disabled={!canAffordPurchase() || purchaseLoading}
                onClick={handlePurchase}
              >
                {purchaseLoading ? 'Purchasing...' : 'Buy'}
              </button>
            </div>
          )}

          {/* Status Message */}
          {statusMessage && (
            <div className={`${styles.statusMessage} ${styles[statusMessage.type]}`}>
              {statusMessage.message}
            </div>
          )}

          {/* Special Links */}
          <div className={styles.bottomLinks}>
            <button className={styles.actionButton}>
              <span className={styles.buttonIcon}>🗑️</span>
              Dump Colonists
            </button>
            <button 
              className={styles.returnButton}
              onClick={onClose}
            >
              Return
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
