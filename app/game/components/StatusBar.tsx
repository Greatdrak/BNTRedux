'use client'

import styles from './StatusBar.module.css'

interface StatusBarProps {
  message?: string
  type?: 'success' | 'error' | 'info'
  loading?: boolean
}

export default function StatusBar({ message, type = 'info', loading }: StatusBarProps) {
  if (!message && !loading) {
    return null
  }

  return (
    <div className={`${styles.statusBar} ${styles[type]}`}>
      {loading ? (
        <span className={styles.loading}>Loading...</span>
      ) : (
        <span className={styles.message}>{message}</span>
      )}
    </div>
  )
}
