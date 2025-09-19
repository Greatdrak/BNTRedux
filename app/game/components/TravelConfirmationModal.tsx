'use client'

import { useState } from 'react'
import styles from './TravelConfirmationModal.module.css'

interface TravelConfirmationModalProps {
  open: boolean
  onClose: () => void
  onConfirm: () => void
  targetSector: number
  currentSector: number
  turnsRequired: number
  travelType: 'warp' | 'realspace'
}

export default function TravelConfirmationModal({
  open,
  onClose,
  onConfirm,
  targetSector,
  currentSector,
  turnsRequired,
  travelType
}: TravelConfirmationModalProps) {
  const [confirming, setConfirming] = useState(false)

  if (!open) return null

  const handleConfirm = async () => {
    setConfirming(true)
    try {
      await onConfirm()
      onClose()
    } catch (error) {
      console.error('Travel failed:', error)
    } finally {
      setConfirming(false)
    }
  }

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h2>🚀 Travel Confirmation</h2>
          <button className={styles.closeBtn} onClick={onClose}>×</button>
        </div>
        
        <div className={styles.content}>
          <div className={styles.travelInfo}>
            <div className={styles.route}>
              <span className={styles.sector}>Sector {currentSector}</span>
              <span className={styles.arrow}>→</span>
              <span className={styles.sector}>Sector {targetSector}</span>
            </div>
            
            <div className={styles.details}>
              <div className={styles.detailItem}>
                <span className={styles.label}>Travel Type:</span>
                <span className={styles.value}>
                  {travelType === 'warp' ? '🌌 Warp Drive' : '🚀 Realspace'}
                </span>
              </div>
              
              <div className={styles.detailItem}>
                <span className={styles.label}>Turns Required:</span>
                <span className={styles.value}>{turnsRequired}</span>
              </div>
            </div>
          </div>
          
          <div className={styles.warning}>
            <p>
              {travelType === 'realspace' 
                ? '⚠️ Realspace travel will consume turns and may encounter hazards.'
                : '🌌 Warp travel is faster but requires warp gates.'
              }
            </p>
          </div>
        </div>
        
        <div className={styles.actions}>
          <button 
            className={styles.cancelBtn}
            onClick={onClose}
            disabled={confirming}
          >
            Cancel
          </button>
          <button 
            className={styles.confirmBtn}
            onClick={handleConfirm}
            disabled={confirming}
          >
            {confirming ? 'Traveling...' : 'Confirm Travel'}
          </button>
        </div>
      </div>
    </div>
  )
}
