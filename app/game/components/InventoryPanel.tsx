'use client'

import styles from './InventoryPanel.module.css'

interface InventoryPanelProps {
  inventory?: {
    ore: number
    organics: number
    goods: number
    energy: number
  }
  loading?: boolean
}

export default function InventoryPanel({ inventory, loading }: InventoryPanelProps) {
  if (loading) return <div className={styles.card} aria-label="Loading inventory..." />

  const resources = [
    { key: 'ore', icon: '🪨', name: 'Ore' },
    { key: 'organics', icon: '🌿', name: 'Organics' },
    { key: 'goods', icon: '📦', name: 'Goods' },
    { key: 'energy', icon: '⚡', name: 'Energy' },
    // @ts-expect-error colonists may be added later
    { key: 'colonists', icon: '👩‍🚀', name: 'Colonists' }
  ] as const

  return (
    <div className={styles.card}>
      <h3 className={styles.title}>Cargo</h3>
      <div className={styles.list}>
        {resources.map((resource) => (
          <div key={resource.key} className={styles.item}>
            <span className={styles.icon}>{resource.icon}</span>
            <span className={styles.name}>{resource.name}</span>
            <span className={styles.quantity}>
              {Number((inventory as any)?.[resource.key] ?? 0).toLocaleString()}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
