import { useState, useEffect } from 'react'
import styles from './PlanetOverlay.module.css'

interface PlanetOverlayProps {
  planet: {
    id: string
    name: string
    owner: boolean
  }
  player: {
    credits: number
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
  const [activeTab, setActiveTab] = useState<'overview' | 'resources' | 'defenses' | 'production'>('overview')
  const [planetStock, setPlanetStock] = useState({
    ore: 0,
    organics: 0,
    goods: 0,
    energy: 0
  })

  const resources = [
    { key: 'ore', label: '🪨 Ore', icon: '🪨' },
    { key: 'organics', label: '🌿 Organics', icon: '🌿' },
    { key: 'goods', label: '📦 Goods', icon: '📦' },
    { key: 'energy', label: '⚡ Energy', icon: '⚡' }
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

  // Simulate planet stock data (in real implementation, fetch from API)
  useEffect(() => {
    // Placeholder: simulate some planet stock
    setPlanetStock({
      ore: Math.floor(Math.random() * 1000),
      organics: Math.floor(Math.random() * 1000),
      goods: Math.floor(Math.random() * 1000),
      energy: Math.floor(Math.random() * 1000)
    })
  }, [planet.id])

  if (!planet.owner) {
    return (
      <div className={styles.overlay} onClick={onClose}>
        <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
          <div className={styles.header}>
            <h3>🪐 Planet: {planet.name}</h3>
            <button className={styles.closeBtn} onClick={onClose}>×</button>
          </div>
          <div className={styles.content}>
            <p>This planet is owned by another player.</p>
            <p>You cannot access its resources.</p>
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
            className={`${styles.tab} ${activeTab === 'resources' ? styles.active : ''}`}
            onClick={() => setActiveTab('resources')}
          >
            Resources
          </button>
          <button 
            className={`${styles.tab} ${activeTab === 'defenses' ? styles.active : ''}`}
            onClick={() => setActiveTab('defenses')}
          >
            Defenses
          </button>
          <button 
            className={`${styles.tab} ${activeTab === 'production' ? styles.active : ''}`}
            onClick={() => setActiveTab('production')}
          >
            Production
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
                    <span className={styles.label}>Status:</span>
                    <span className={styles.value}>Active Colony</span>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Population:</span>
                    <span className={styles.value}>1,250 colonists</span>
                  </div>
                  <div className={styles.infoItem}>
                    <span className={styles.label}>Defense Level:</span>
                    <span className={styles.value}>Basic</span>
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
            </div>
          )}

          {activeTab === 'resources' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Store Resources</h4>
                <div className={styles.formGroup}>
                  <label>Resource:</label>
                  <select 
                    value={storeResource} 
                    onChange={(e) => setStoreResource(e.target.value)}
                    disabled={loading}
                  >
                    {resources.map(res => (
                      <option key={res.key} value={res.key}>
                        {res.label}
                      </option>
                    ))}
                  </select>
                </div>
                <div className={styles.formGroup}>
                  <label>Quantity:</label>
                  <div className={styles.qtyContainer}>
                    <input
                      type="number"
                      min="1"
                      max={getMaxStore(storeResource)}
                      value={storeQty}
                      onChange={(e) => setStoreQty(parseInt(e.target.value) || 0)}
                      disabled={loading}
                    />
                    <button 
                      className={styles.maxBtn}
                      onClick={() => setStoreQty(getMaxStore(storeResource))}
                      disabled={loading || getMaxStore(storeResource) === 0}
                    >
                      Max
                    </button>
                  </div>
                </div>
                <button 
                  className={styles.actionBtn}
                  onClick={handleStore}
                  disabled={loading || storeQty <= 0 || getMaxStore(storeResource) < storeQty}
                >
                  {loading ? 'Storing...' : `Store ${storeQty} ${storeResource}`}
                </button>
              </div>

              <div className={styles.section}>
                <h4>Withdraw Resources</h4>
                <div className={styles.formGroup}>
                  <label>Resource:</label>
                  <select 
                    value={withdrawResource} 
                    onChange={(e) => setWithdrawResource(e.target.value)}
                    disabled={loading}
                  >
                    {resources.map(res => (
                      <option key={res.key} value={res.key}>
                        {res.label}
                      </option>
                    ))}
                  </select>
                </div>
                <div className={styles.formGroup}>
                  <label>Quantity:</label>
                  <div className={styles.qtyContainer}>
                    <input
                      type="number"
                      min="1"
                      max={getMaxWithdraw(withdrawResource)}
                      value={withdrawQty}
                      onChange={(e) => setWithdrawQty(parseInt(e.target.value) || 0)}
                      disabled={loading}
                    />
                    <button 
                      className={styles.maxBtn}
                      onClick={() => setWithdrawQty(getMaxWithdraw(withdrawResource))}
                      disabled={loading || getMaxWithdraw(withdrawResource) === 0}
                    >
                      Max
                    </button>
                  </div>
                </div>
                <button 
                  className={styles.actionBtn}
                  onClick={handleWithdraw}
                  disabled={loading || withdrawQty <= 0 || getMaxWithdraw(withdrawResource) < withdrawQty}
                >
                  {loading ? 'Withdrawing...' : `Withdraw ${withdrawQty} ${withdrawResource}`}
                </button>
              </div>
            </div>
          )}

          {activeTab === 'defenses' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Defense Systems</h4>
                <div className={styles.placeholder}>
                  <p>🛡️ Defense systems coming soon!</p>
                  <p>Future features will include:</p>
                  <ul>
                    <li>Shield generators</li>
                    <li>Weapon platforms</li>
                    <li>Defense turrets</li>
                    <li>Planetary shields</li>
                  </ul>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'production' && (
            <div className={styles.tabContent}>
              <div className={styles.section}>
                <h4>Production Facilities</h4>
                <div className={styles.placeholder}>
                  <p>🏭 Production facilities coming soon!</p>
                  <p>Future features will include:</p>
                  <ul>
                    <li>Mining operations</li>
                    <li>Manufacturing plants</li>
                    <li>Research labs</li>
                    <li>Automated production</li>
                  </ul>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
