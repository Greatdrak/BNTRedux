import { useState } from 'react'
import styles from './ClaimPlanetModal.module.css'

interface ClaimPlanetModalProps {
  onClose: () => void
  onClaim: (name: string) => void
}

export default function ClaimPlanetModal({ 
  onClose, 
  onClaim
}: ClaimPlanetModalProps) {
  const [planetName, setPlanetName] = useState('Colony')
  const [loading, setLoading] = useState(false)

  const handleClaim = async () => {
    if (!planetName.trim()) return
    setLoading(true)
    try {
      await onClaim(planetName.trim())
    } finally {
      setLoading(false)
    }
  }

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleClaim()
    } else if (e.key === 'Escape') {
      onClose()
    }
  }

  return (
    <div className={styles.overlay} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <h3>🪐 Claim Planet</h3>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>
        
        <div className={styles.content}>
          <p>Establish a colony in this sector to store and manage resources.</p>
          
          

          <div className={styles.formGroup}>
            <label htmlFor="planetName">Planet Name:</label>
            <input
              id="planetName"
              type="text"
              value={planetName}
              onChange={(e) => setPlanetName(e.target.value)}
              onKeyDown={handleKeyPress}
              placeholder="Enter planet name..."
              disabled={loading}
              autoFocus
            />
          </div>

          <div className={styles.actions}>
            <button 
              className={styles.cancelBtn}
              onClick={onClose}
              disabled={loading}
            >
              Cancel
            </button>
            <button 
              className={styles.claimBtn}
              onClick={handleClaim}
              disabled={loading || !planetName.trim()}
            >
              {loading ? 'Claiming...' : 'Claim Planet'}
            </button>
          </div>
          
        </div>
      </div>
    </div>
  )
}
