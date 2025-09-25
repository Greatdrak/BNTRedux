'use client'

import { useState, useEffect, useMemo } from 'react'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './PlanetsOverlay.module.css'

interface Planet {
  id: string
  name: string
  sector: number
  colonists: number
  colonists_max: number
  ore: number
  organics: number
  goods: number
  energy: number
  credits: number
  fighters: number
  torpedoes: number
  has_base: boolean
  production_allocation: any
}

interface PlanetsData {
  planets: Planet[]
  totals: {
    colonists: number
    ore: number
    organics: number
    goods: number
    energy: number
    credits: number
    fighters: number
    torpedoes: number
    bases: number
  }
  count: number
}

interface PlanetsOverlayProps {
  open: boolean
  onClose: () => void
  universeId?: string
  onTravelToSector?: (sector: number) => void
  onStatusMessage?: (message: string, type: 'success' | 'error' | 'info') => void
}

type SortField = 'sector' | 'name' | 'colonists' | 'ore' | 'organics' | 'goods' | 'energy' | 'credits' | 'fighters' | 'torpedoes' | 'has_base'
type SortDirection = 'asc' | 'desc'

export default function PlanetsOverlay({ 
  open, 
  onClose, 
  universeId,
  onTravelToSector,
  onStatusMessage 
}: PlanetsOverlayProps) {
  const [searchTerm, setSearchTerm] = useState('')
  const [sortField, setSortField] = useState<SortField>('sector')
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc')
  const [selectedPlanets, setSelectedPlanets] = useState<Set<string>>(new Set())
  const [collectLoading, setCollectLoading] = useState(false)

  // Authenticated fetcher for planets data
  const planetsFetcher = async (url: string) => {
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) throw new Error('No session')
    
    const response = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${session.access_token}`
      }
    })
    
    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error?.message || 'Failed to fetch planets')
    }
    
    return response.json()
  }

  // Fetch planets data
  const { data: planetsData, error: planetsError, mutate: mutatePlanets } = useSWR<PlanetsData>(
    universeId ? `/api/planets?universe_id=${universeId}` : null,
    planetsFetcher,
    { refreshInterval: 30000 } // Refresh every 30 seconds
  )

  // Filter and sort planets
  const filteredAndSortedPlanets = useMemo(() => {
    if (!planetsData?.planets) return []

    let filtered = planetsData.planets.filter(planet => 
      planet.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      planet.sector.toString().includes(searchTerm)
    )

    // Sort planets
    filtered.sort((a, b) => {
      let aVal: any = a[sortField]
      let bVal: any = b[sortField]

      if (sortField === 'has_base') {
        aVal = aVal ? 1 : 0
        bVal = bVal ? 1 : 0
      }

      if (typeof aVal === 'string') {
        aVal = aVal.toLowerCase()
        bVal = bVal.toLowerCase()
      }

      if (sortDirection === 'asc') {
        return aVal < bVal ? -1 : aVal > bVal ? 1 : 0
      } else {
        return aVal > bVal ? -1 : aVal < bVal ? 1 : 0
      }
    })

    return filtered
  }, [planetsData?.planets, searchTerm, sortField, sortDirection])

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc')
    } else {
      setSortField(field)
      setSortDirection('asc')
    }
  }

  const handleSelectPlanet = (planetId: string) => {
    const newSelected = new Set(selectedPlanets)
    if (newSelected.has(planetId)) {
      newSelected.delete(planetId)
    } else {
      newSelected.add(planetId)
    }
    setSelectedPlanets(newSelected)
  }

  const handleSelectAll = () => {
    if (selectedPlanets.size === filteredAndSortedPlanets.length) {
      setSelectedPlanets(new Set())
    } else {
      setSelectedPlanets(new Set(filteredAndSortedPlanets.map(p => p.id)))
    }
  }

  const handleCollectCredits = async () => {
    if (selectedPlanets.size === 0) {
      onStatusMessage?.('Please select planets to collect credits from', 'error')
      return
    }

    setCollectLoading(true)
    try {
      // TODO: Implement collect credits API
      onStatusMessage?.('Credit collection feature coming soon!', 'info')
    } catch (error) {
      onStatusMessage?.('Failed to collect credits', 'error')
    } finally {
      setCollectLoading(false)
    }
  }

  const handleTravelToSector = (sector: number) => {
    onTravelToSector?.(sector)
    onClose()
  }

  useEffect(() => {
    if (!open) return
    
    const onKey = (e: KeyboardEvent) => { 
      if (e.key === 'Escape') onClose() 
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!open) return null

  return (
    <div className={styles.backdrop} onClick={onClose}>
      <div className={styles.panel} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <div className={styles.title}>
            Planet Management
            {planetsData && (
              <span className={styles.count}>
                ({planetsData.count} planets)
              </span>
            )}
          </div>
          <button className={styles.close} onClick={onClose}>✕</button>
        </div>

        <div className={styles.content}>
          {/* Search and Controls */}
          <div className={styles.controls}>
            <div className={styles.searchContainer}>
              <input
                type="text"
                placeholder="Search planets by name or sector..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className={styles.searchInput}
              />
            </div>
            
            <div className={styles.actionButtons}>
              <button
                className={styles.collectButton}
                onClick={handleCollectCredits}
                disabled={selectedPlanets.size === 0 || collectLoading}
              >
                {collectLoading ? 'Collecting...' : `Collect Credits (${selectedPlanets.size})`}
              </button>
            </div>
          </div>

          {/* Planets Table */}
          <div className={styles.tableContainer}>
            <table className={styles.planetsTable}>
              <thead>
                <tr>
                  <th className={styles.checkboxCol}>
                    <input
                      type="checkbox"
                      checked={selectedPlanets.size === filteredAndSortedPlanets.length && filteredAndSortedPlanets.length > 0}
                      onChange={handleSelectAll}
                    />
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'sector' ? styles.sorted : ''}`}
                    onClick={() => handleSort('sector')}
                  >
                    Sector {sortField === 'sector' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'name' ? styles.sorted : ''}`}
                    onClick={() => handleSort('name')}
                  >
                    Name {sortField === 'name' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'colonists' ? styles.sorted : ''}`}
                    onClick={() => handleSort('colonists')}
                  >
                    Colonists {sortField === 'colonists' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'ore' ? styles.sorted : ''}`}
                    onClick={() => handleSort('ore')}
                  >
                    Ore {sortField === 'ore' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'organics' ? styles.sorted : ''}`}
                    onClick={() => handleSort('organics')}
                  >
                    Organics {sortField === 'organics' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'goods' ? styles.sorted : ''}`}
                    onClick={() => handleSort('goods')}
                  >
                    Goods {sortField === 'goods' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'energy' ? styles.sorted : ''}`}
                    onClick={() => handleSort('energy')}
                  >
                    Energy {sortField === 'energy' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'credits' ? styles.sorted : ''}`}
                    onClick={() => handleSort('credits')}
                  >
                    Credits {sortField === 'credits' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'fighters' ? styles.sorted : ''}`}
                    onClick={() => handleSort('fighters')}
                  >
                    Fighters {sortField === 'fighters' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'torpedoes' ? styles.sorted : ''}`}
                    onClick={() => handleSort('torpedoes')}
                  >
                    Torpedoes {sortField === 'torpedoes' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th 
                    className={`${styles.sortable} ${sortField === 'has_base' ? styles.sorted : ''}`}
                    onClick={() => handleSort('has_base')}
                  >
                    Base {sortField === 'has_base' && (sortDirection === 'asc' ? '↑' : '↓')}
                  </th>
                  <th className={styles.actionsCol}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {filteredAndSortedPlanets.map((planet) => (
                  <tr key={planet.id} className={styles.planetRow}>
                    <td className={styles.checkboxCol}>
                      <input
                        type="checkbox"
                        checked={selectedPlanets.has(planet.id)}
                        onChange={() => handleSelectPlanet(planet.id)}
                      />
                    </td>
                    <td className={styles.sectorCol}>
                      <button
                        className={styles.sectorLink}
                        onClick={() => handleTravelToSector(planet.sector)}
                        title={`Travel to Sector ${planet.sector}`}
                      >
                        {planet.sector}
                      </button>
                    </td>
                    <td className={styles.nameCol}>
                      <span className={planet.name === 'Unnamed' ? styles.unnamed : ''}>
                        {planet.name}
                      </span>
                    </td>
                    <td className={styles.numberCol}>
                      {planet.colonists.toLocaleString()}
                      {planet.colonists_max > 0 && (
                        <span className={styles.maxIndicator}>
                          /{planet.colonists_max.toLocaleString()}
                        </span>
                      )}
                    </td>
                    <td className={styles.numberCol}>{planet.ore.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.organics.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.goods.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.energy.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.credits.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.fighters.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planet.torpedoes.toLocaleString()}</td>
                    <td className={styles.baseCol}>
                      <span className={planet.has_base ? styles.hasBase : styles.noBase}>
                        {planet.has_base ? 'Yes' : 'No'}
                      </span>
                    </td>
                    <td className={styles.actionsCol}>
                      <button
                        className={styles.actionButton}
                        onClick={() => handleTravelToSector(planet.sector)}
                        title="Travel to this planet"
                      >
                        Travel
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              {planetsData && (
                <tfoot>
                  <tr className={styles.totalsRow}>
                    <td className={styles.checkboxCol}></td>
                    <td className={styles.sectorCol}>Totals</td>
                    <td className={styles.nameCol}></td>
                    <td className={styles.numberCol}>{planetsData.totals.colonists.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.ore.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.organics.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.goods.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.energy.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.credits.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.fighters.toLocaleString()}</td>
                    <td className={styles.numberCol}>{planetsData.totals.torpedoes.toLocaleString()}</td>
                    <td className={styles.baseCol}>{planetsData.totals.bases}</td>
                    <td className={styles.actionsCol}></td>
                  </tr>
                </tfoot>
              )}
            </table>
          </div>

          {planetsError && (
            <div className={styles.error}>
              Failed to load planets: {planetsError.message}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
