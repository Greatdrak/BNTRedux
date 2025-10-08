'use client'

import { useState, useEffect, useMemo } from 'react'
import styles from './ActionsPanel.module.css'

interface ActionsPanelProps {
  port?: {
    id: string
    kind: string
    stock: {
      ore: number
      organics: number
      goods: number
      energy: number
    }
    prices: {
      ore: number
      organics: number
      goods: number
      energy: number
    }
  }
  player?: {
    credits: number
  }
  shipCredits?: number
  ship?: {
    cargo: number
    hull_lvl?: number
    energy?: number
    energy_max?: number
    power_lvl?: number
  }
  inventory?: {
    ore: number
    organics: number
    goods: number
    energy: number
  }
  onTrade: (data: { action: string; resource: string; qty: number }) => void
  tradeLoading?: boolean
  lockAction?: 'buy' | 'sell'
  allowedResources?: Array<'ore' | 'organics' | 'goods' | 'energy'>
  defaultResource?: 'ore' | 'organics' | 'goods' | 'energy'
}

export default function ActionsPanel({ port, player, shipCredits, ship, inventory, onTrade, tradeLoading, lockAction, allowedResources, defaultResource }: ActionsPanelProps) {
  const [action, setAction] = useState<'buy' | 'sell'>(lockAction ?? 'buy')
  const [resource, setResource] = useState<'ore' | 'organics' | 'goods' | 'energy'>(defaultResource ?? 'ore')
  const [qty, setQty] = useState(1)
  const [transactionInProgress, setTransactionInProgress] = useState(false)

  const resources = [
    { key: 'ore', icon: '🪨', name: 'Ore' },
    { key: 'organics', icon: '🌿', name: 'Organics' },
    { key: 'goods', icon: '📦', name: 'Goods' },
    { key: 'energy', icon: '⚡', name: 'Energy' }
  ] as const

  const visibleResources = (allowedResources && allowedResources.length > 0)
    ? resources.filter(r => (allowedResources as any).includes(r.key))
    : resources

  useEffect(() => {
    if (lockAction) setAction(lockAction)
  }, [lockAction])

  useEffect(() => {
    if (defaultResource) setResource(defaultResource)
  }, [defaultResource])

  // Reset transaction in progress when trade loading finishes
  useEffect(() => {
    if (!tradeLoading && transactionInProgress) {
      setTransactionInProgress(false)
    }
  }, [tradeLoading, transactionInProgress])

  // Calculate max buy/sell quantities
  const getMaxBuy = () => {
    if (!port || !player || !ship || !inventory) return 0
    // Use dynamic pricing for max buy calculation
    const price = getCurrentPrice()
    const portStock = port.stock[resource]
    const creditsAffordable = Math.floor((shipCredits || 0) / price)
    
    // Energy has its own capacity separate from cargo
    if (resource === 'energy') {
      const currentEnergy = ship.energy || 0
      const maxEnergy = ship.energy_max || Math.floor(100 * Math.pow(1.5, ship.power_lvl || 1))
      const remainingEnergy = Math.max(0, maxEnergy - currentEnergy)
      return Math.max(0, Math.min(creditsAffordable, portStock, remainingEnergy))
    }
    
    // For other resources, check cargo space (excluding energy and colonists)
    const currentCargo = inventory.ore + inventory.organics + inventory.goods
    // Use BNT formula for cargo capacity: 100 * (1.5^hull_level)
    const shipCargoCapacity = Math.floor(100 * Math.pow(1.5, ship.hull_lvl || 1))
    const remainingCargo = Math.max(0, shipCargoCapacity - currentCargo)
    return Math.max(0, Math.min(creditsAffordable, portStock, remainingCargo))
  }

  const getMaxSell = () => {
    if (!inventory) return 0
    return inventory[resource]
  }

  const getCurrentPrice = () => {
    if (!port) return 0
    // Get base price and current stock for dynamic pricing
    const base = port.prices[resource]
    const stock = port.stock[resource]
    
    // Calculate dynamic price multiplier (0.8x to 1.5x based on stock)
    // Low stock = higher prices, high stock = lower prices
    const baseStock = 1000000000 // 1B base stock
    let multiplier = 1.0
    
    if (stock > 0) {
      const stockRatio = stock / baseStock
      const logFactor = Math.log10(Math.max(stockRatio, 0.1)) // Avoid log(0)
      multiplier = 1.5 - (logFactor + 1) * 0.35 // Scale to 0.8-1.5 range
      multiplier = Math.max(0.8, Math.min(1.5, multiplier))
    } else {
      multiplier = 1.5 // Max price when out of stock
    }
    
    const dynamicPrice = base * multiplier
    return action === 'buy' ? dynamicPrice * 0.90 : dynamicPrice * 1.10
  }

  const getTotalCost = () => {
    return qty * getCurrentPrice()
  }

  const getAfterBalance = () => {
    if (!player) return 0
    return action === 'buy' 
      ? (shipCredits || 0) - getTotalCost()
      : (shipCredits || 0) + getTotalCost()
  }

  const getValidationError = () => {
    if (!port) return "No port available"
    if (!player) return "Player data not loaded"
    if (!ship) return "Ship data not loaded"
    if (!inventory) return "Inventory data not loaded"
    if (qty <= 0) return "Quantity must be positive"
    
    if (action === 'buy') {
      const totalCost = getTotalCost()
      if (totalCost > (shipCredits || 0)) return `Insufficient credits (need ${totalCost.toLocaleString()}, have ${(shipCredits || 0).toLocaleString()})`
      if (qty > port.stock[resource]) return `Insufficient port stock (need ${qty.toLocaleString()}, port has ${port.stock[resource].toLocaleString()})`
      
      // Energy has its own capacity check
      if (resource === 'energy') {
        const currentEnergy = ship.energy || 0
        const maxEnergy = ship.energy_max || Math.floor(100 * Math.pow(1.5, ship.power_lvl || 1))
        const remainingEnergy = Math.max(0, maxEnergy - currentEnergy)
        if (qty > remainingEnergy) return `Insufficient energy capacity (need ${qty.toLocaleString()}, free ${remainingEnergy.toLocaleString()}). Upgrade Power at Special Port.`
      } else {
        // Cargo capacity for other resources (excluding energy)
        const currentCargo = inventory.ore + inventory.organics + inventory.goods
        const remainingCargo = Math.max(0, ship.cargo - currentCargo)
        if (qty > remainingCargo) return `Insufficient cargo (need ${qty.toLocaleString()}, free ${remainingCargo.toLocaleString()})`
      }
      return null // Valid
    } else {
      if (qty > inventory[resource]) return `Insufficient inventory (need ${qty.toLocaleString()}, have ${inventory[resource].toLocaleString()})`
      return null // Valid
    }
  }

  const validationError = useMemo(() => getValidationError(), [port, player, ship, inventory, qty, action, resource])
  const isTradeValid = () => validationError === null

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (isTradeValid() && !tradeLoading && !transactionInProgress) {
      setTransactionInProgress(true)
      try {
        await Promise.resolve(onTrade({ action, resource, qty }))
        // Reset quantity to 1 after successful trade to avoid validation errors
        setQty(1)
      } finally {
        // allow the SWR refresh to flip tradeLoading; as a safety, clear after short delay
        setTimeout(() => setTransactionInProgress(false), 300)
      }
    }
  }

  const handleMaxBuy = () => {
    const max = getMaxBuy()
    if (max > 0) {
      setQty(max)
    }
  }

  const handleMaxSell = () => {
    const max = getMaxSell()
    if (max > 0) {
      setQty(max)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      handleSubmit(e)
    } else if (e.key === 'Escape') {
      setQty(1)
    }
  }

  const formatNumber = (num: number) => {
    return new Intl.NumberFormat('en-US').format(num)
  }

  const formatPrice = (price: number) => {
    return new Intl.NumberFormat('en-US', { 
      minimumFractionDigits: 2, 
      maximumFractionDigits: 2 
    }).format(price)
  }

  return (
    <div className={styles.panel}>
      <h3>Trading</h3>
      
      
      {port ? (
        <form onSubmit={handleSubmit} className={styles.tradeForm}>
          {!lockAction && (
            <div className={styles.formGroup}>
              <label htmlFor="action">Action</label>
              <select
                id="action"
                value={action}
                onChange={(e) => setAction(e.target.value as 'buy' | 'sell')}
                className={styles.select}
              >
                <option value="buy">Buy</option>
                <option value="sell">Sell</option>
              </select>
            </div>
          )}
          
          <div className={styles.formGroup}>
            <label htmlFor="resource">Resource</label>
            <select
              id="resource"
              value={resource}
              onChange={(e) => setResource(e.target.value as any)}
              className={styles.select}
            >
              {visibleResources.map((res) => (
                <option key={res.key} value={res.key}>
                  {res.icon} {res.name}
                </option>
              ))}
            </select>
          </div>
          
          <div className={styles.formGroup}>
            <label htmlFor="qty">Quantity</label>
            <div className={styles.qtyContainer}>
              <input
                id="qty"
                type="number"
                min="1"
                value={qty}
                onChange={(e) => setQty(parseInt(e.target.value) || 1)}
                onKeyDown={handleKeyDown}
                className={styles.input}
              />
              <div className={styles.maxButtons}>
                <button
                  type="button"
                  onClick={handleMaxBuy}
                  disabled={action !== 'buy' || getMaxBuy() <= 0}
                  className={styles.maxBtn}
                >
                  Max Buy
                </button>
                <button
                  type="button"
                  onClick={handleMaxSell}
                  disabled={action !== 'sell' || getMaxSell() <= 0}
                  className={styles.maxBtn}
                >
                  Max Sell
                </button>
              </div>
            </div>
          </div>

          {/* Trade Preview */}
          <div className={styles.tradePreview}>
            <div className={styles.previewRow}>
              <span>Price:</span>
              <span>{formatPrice(getCurrentPrice())} cr</span>
            </div>
            <div className={styles.previewRow}>
              <span>Total:</span>
              <span>{formatNumber(getTotalCost())} cr</span>
            </div>
            <div className={styles.previewRow}>
              <span>After:</span>
              <span className={getAfterBalance() < 0 ? styles.negative : ''}>
                {formatNumber(getAfterBalance())} cr
              </span>
            </div>
          </div>

          {/* Validation Error Display */}
          {validationError && !(tradeLoading || transactionInProgress) && (
            <div className={styles.validationError}>
              {validationError}
            </div>
          )}
          
          <button
            type="submit"
            disabled={tradeLoading || transactionInProgress || !isTradeValid()}
            className={styles.submitBtn}
          >
            {tradeLoading || transactionInProgress ? 'Trading...' : `${action === 'buy' ? 'Buy' : 'Sell'} ${qty} ${resource}`}
          </button>
        </form>
      ) : (
        <div className={styles.noPort}>
          <p>No port available in this sector</p>
          <p className={styles.hint}>Find a sector with a port to trade</p>
        </div>
      )}
    </div>
  )
}
