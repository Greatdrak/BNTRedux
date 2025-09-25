'use client'

import styles from '../page.module.css'

interface GameLayoutProps {
  children: {
    header: React.ReactNode;
    leftPanel: React.ReactNode;
    centerPanel: React.ReactNode;
    rightPanel: React.ReactNode;
  };
}

export default function GameLayout({ children }: GameLayoutProps) {
  // console.log('GameLayout rendered with children:', Object.keys(children))
  return (
    <div className={styles.gameContainer}>
      {/* Header */}
      <header className={styles.gameHeader}>
        {children.header}
      </header>

      {/* Main Content Grid */}
      <main className={styles.gameMain}>
        {/* Left Panel */}
        <aside className={styles.leftPanel}>
          {children.leftPanel}
        </aside>

        {/* Center Panel */}
        <section className={styles.centerPanel}>
          {children.centerPanel}
        </section>

        {/* Right Panel */}
        <aside className={styles.rightPanel}>
          {children.rightPanel}
        </aside>
      </main>

      {/* No footer - ships are now part of center panel */}
    </div>
  )
}
