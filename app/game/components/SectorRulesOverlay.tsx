'use client'

import { useEffect, useState } from 'react'
import styles from './SectorRulesOverlay.module.css'

interface SectorRulesOverlayProps {
  open: boolean
  onClose: () => void
  sectorNumber: number
  universeId: string
  isOwner: boolean
  onRename?: (newName: string) => Promise<void>
  onUpdateRules?: (rules: any) => Promise<void>
  fetchFn?: (url: string) => Promise<Response>
}

export default function SectorRulesOverlay({
  open,
  onClose,
  sectorNumber,
  universeId,
  isOwner,
  onRename,
  onUpdateRules,
  fetchFn = fetch
}: SectorRulesOverlayProps) {
  const [loading, setLoading] = useState(true)
  const [sectorData, setSectorData] = useState<any>(null)
  const [editing, setEditing] = useState(false)
  const [newName, setNewName] = useState('')
  const [editedRules, setEditedRules] = useState<any>(null)

  useEffect(() => {
    if (!open) return
    
    setLoading(true)
    fetchFn(`/api/sector/rules?sectorNumber=${sectorNumber}&universe_id=${universeId}`)
      .then(r => r.json())
      .then(data => {
        setSectorData(data)
        setNewName(data.name || '')
        setEditedRules({
          allowAttacking: data.rules?.allowAttacking ?? true,
          allowTrading: data.rules?.allowTrading || 'yes',
          allowPlanetCreation: data.rules?.allowPlanetCreation || 'yes',
          allowSectorDefense: data.rules?.allowSectorDefense || 'yes'
        })
        setLoading(false)
      })
      .catch(err => {
        console.error('Failed to load sector rules:', err)
        setLoading(false)
      })
  }, [open, sectorNumber, universeId, fetchFn])

  if (!open) return null

  const isFederation = sectorNumber >= 0 && sectorNumber <= 10

  return (
    <div className={styles.overlay} onClick={onClose}>
      <div className={styles.modal} onClick={e => e.stopPropagation()}>
        <div className={styles.header}>
          <h2>Sector {sectorNumber} - {sectorData?.name || 'Loading...'}</h2>
          <button className={styles.closeBtn} onClick={onClose}>✕</button>
        </div>

        {loading ? (
          <div className={styles.loading}>Loading sector information...</div>
        ) : (
          <div className={styles.content}>
            {isFederation && (
              <div className={styles.federationBanner}>
                🛡️ Federation Safe Zone - Rules cannot be modified
              </div>
            )}

            {sectorData?.owned && (
              <div className={styles.ownerInfo}>
                <strong>Sector Owner:</strong> {sectorData.ownerHandle}
              </div>
            )}

            {!sectorData?.owned && !isFederation && (
              <div className={styles.unownedInfo}>
                This sector is unclaimed. Establish 3+ planetary bases to claim ownership.
              </div>
            )}

            <div className={styles.section}>
              <h3>Sector Name</h3>
              {isOwner && !isFederation && editing ? (
                <div className={styles.editName}>
                  <input 
                    type="text" 
                    value={newName} 
                    onChange={e => setNewName(e.target.value)}
                    maxLength={50}
                    placeholder="Sector name"
                  />
                  <button onClick={async () => {
                    if (onRename) await onRename(newName)
                    setEditing(false)
                  }}>Save</button>
                  <button onClick={() => {
                    setNewName(sectorData?.name || '')
                    setEditing(false)
                  }}>Cancel</button>
                </div>
              ) : (
                <div className={styles.nameDisplay}>
                  <span>{sectorData?.name || 'Uncharted Territory'}</span>
                  {isOwner && !isFederation && (
                    <button onClick={() => setEditing(true)}>Rename</button>
                  )}
                </div>
              )}
            </div>

            <div className={styles.section}>
              <h3>Sector Rules</h3>
              <div className={styles.rules}>
                <div className={styles.rule}>
                  <span className={styles.ruleLabel}>⚔️ Combat Allowed:</span>
                  <span className={editedRules?.allowAttacking ? styles.yes : styles.no}>
                    {editedRules?.allowAttacking ? 'Yes' : 'No'}
                  </span>
                </div>
                <div className={styles.rule}>
                  <span className={styles.ruleLabel}>🤝 Trading:</span>
                  <span className={styles.neutral}>{
                    editedRules?.allowTrading === 'yes' ? 'Open to All' :
                    editedRules?.allowTrading === 'allies_only' ? 'Allies Only' :
                    'Prohibited'
                  }</span>
                </div>
                <div className={styles.rule}>
                  <span className={styles.ruleLabel}>🌍 Planet Creation:</span>
                  <span className={styles.neutral}>{
                    editedRules?.allowPlanetCreation === 'yes' ? 'Open to All' :
                    editedRules?.allowPlanetCreation === 'allies_only' ? 'Allies Only' :
                    'Prohibited'
                  }</span>
                </div>
                <div className={styles.rule}>
                  <span className={styles.ruleLabel}>💣 Sector Defenses:</span>
                  <span className={styles.neutral}>{
                    editedRules?.allowSectorDefense === 'yes' ? 'Open to All' :
                    editedRules?.allowSectorDefense === 'allies_only' ? 'Allies Only' :
                    'Prohibited'
                  }</span>
                </div>
              </div>

              {isOwner && !isFederation && (
                <div className={styles.editRules}>
                  <p>As the sector owner, you can customize these rules from the sector management panel.</p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

