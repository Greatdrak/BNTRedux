'use client'

import styles from './PortPanel.module.css'

interface PortPanelProps {
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
}

export default function PortPanel({ port }: PortPanelProps) {
  if (!port) {
    return null
  }

  const resources = [
    { key: 'ore', icon: '🪨', name: 'Ore' },
    { key: 'organics', icon: '🌿', name: 'Organics' },
    { key: 'goods', icon: '📦', name: 'Goods' },
    { key: 'energy', icon: '⚡', name: 'Energy' }
  ] as const

  return (
    <div className={styles.panel}>
      <h3>Port ({port.kind})</h3>
      
      <div className={styles.resourceTable}>
        <div className={styles.tableHeader}>
          <span>Resource</span>
          <span>Stock</span>
          <span>Price</span>
        </div>
        
        {resources.map((resource) => (
          <div key={resource.key} className={styles.tableRow}>
            <span className={styles.resource}>
              <span className={styles.icon}>{resource.icon}</span>
              {resource.name}
            </span>
            <span className={styles.stock}>
              {port.stock[resource.key].toLocaleString()}
            </span>
            <span className={styles.price}>
              {port.prices[resource.key].toLocaleString()}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
