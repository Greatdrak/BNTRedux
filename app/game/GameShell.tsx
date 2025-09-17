'use client'

import theme from './retro-theme.module.css'
import styles from './GameShell.module.css'
import { ReactNode } from 'react'

interface GameShellProps {
  left: ReactNode
  center: ReactNode
  right: ReactNode
}

export default function GameShell({ left, center, right }: GameShellProps) {
  return (
    <div className={`${styles.container} ${theme.stack16}`}>
      <div className={styles.left}>{left}</div>
      <div className={styles.center}>{center}</div>
      <div className={styles.right}>{right}</div>
    </div>
  )
}


