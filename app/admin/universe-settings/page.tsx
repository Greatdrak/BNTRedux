'use client'

import { useState, useEffect, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import useSWR from 'swr'
import { supabase } from '@/lib/supabase-client'
import styles from './page.module.css'

interface UniverseSettings {
  universe_id: string
  game_version: string
  game_name: string
  avg_tech_level_mines: number
  avg_tech_emergency_warp_degrade: number
  max_avg_tech_federation_sectors: number
  tech_level_upgrade_bases: number
  number_of_sectors: number
  max_links_per_sector: number
  max_planets_per_sector: number
  planets_needed_for_sector_ownership: number
  igb_enabled: boolean
  igb_interest_rate_per_update: number
  igb_loan_rate_per_update: number
  planet_interest_rate: number
  colonists_limit: number
  colonist_production_rate: number
  colonists_per_fighter: number
  colonists_per_torpedo: number
  colonists_per_ore: number
  colonists_per_organics: number
  colonists_per_goods: number
  colonists_per_energy: number
  colonists_per_credits: number
  max_accumulated_turns: number
  max_traderoutes_per_player: number
  energy_per_sector_fighter: number
  sector_fighter_degradation_rate: number
  tick_interval_minutes: number
  turns_generation_interval_minutes: number
  turns_per_generation: number
  defenses_check_interval_minutes: number
  xenobes_play_interval_minutes: number
  igb_interest_accumulation_interval_minutes: number
  news_generation_interval_minutes: number
  planet_production_interval_minutes: number
  port_regeneration_interval_minutes: number
  ships_tow_from_fed_sectors_interval_minutes: number
  rankings_generation_interval_minutes: number
  sector_defenses_degrade_interval_minutes: number
  planetary_apocalypse_interval_minutes: number
  use_new_planet_update_code: boolean
  limit_captured_planets_max_credits: boolean
  captured_planets_max_credits: number
}

interface Universe {
  id: string
  name: string
}

const fetcher = async (url: string) => {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) {
    throw new Error('No authentication token')
  }
  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${session.access_token}`
    }
  })
  if (!response.ok) {
    throw new Error('Failed to fetch data')
  }
  return response.json()
}

export default function UniverseSettingsPage() {
  const router = useRouter()
  const [selectedUniverse, setSelectedUniverse] = useState<string>('')
  const [settings, setSettings] = useState<UniverseSettings | null>(null)
  const [loading, setLoading] = useState(false)
  const [status, setStatus] = useState('')
  const [activeTab, setActiveTab] = useState<'game' | 'economy' | 'scheduler' | 'advanced'>('game')
  const [tick, setTick] = useState(0)
  const { data: heartbeat, mutate: mutateHeartbeat } = useSWR<any>(
    selectedUniverse ? `/api/scheduler/status?universe_id=${selectedUniverse}` : null,
    fetcher,
    { refreshInterval: 30000 }
  )

  useEffect(() => {
    const id = setInterval(() => setTick((t) => (t + 1) % 1_000_000), 1000)
    return () => clearInterval(id)
  }, [])

  const countdown = useMemo(() => {
    const now = Math.floor(Date.now() / 1000)
    const toSec = (iso?: string | null) => (iso ? Math.max(0, Math.floor((new Date(iso).getTime() - now * 1000) / 1000)) : 0)
    return {
      turn: toSec(heartbeat?.next_turn_generation),
      cycle: toSec(heartbeat?.next_cycle_event),
      update: toSec(heartbeat?.next_update_event)
    }
  }, [heartbeat, tick])
  const fmt = (s: number) => {
    const pad = (n: number) => n.toString().padStart(2, '0')
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    const ss = s % 60
    return h > 0 ? `${pad(h)}:${pad(m)}:${pad(ss)}` : `${pad(m)}:${pad(ss)}`
  }

  // Fetch universes
  const { data: universesData, error: universesError } = useSWR<{ universes: Universe[] }>('/api/admin/universes', fetcher)

  // Fetch settings when universe is selected
  const { data: settingsData, error: settingsError, mutate: mutateSettings } = useSWR<{ settings: UniverseSettings }>(
    selectedUniverse ? `/api/admin/universe-settings?universe_id=${selectedUniverse}` : null,
    fetcher
  )

  useEffect(() => {
    if (settingsData?.settings) {
      setSettings(settingsData.settings)
    }
  }, [settingsData])

  const handleUniverseChange = (universeId: string) => {
    setSelectedUniverse(universeId)
    setSettings(null)
  }

  const handleSettingChange = (key: keyof UniverseSettings, value: any) => {
    if (settings) {
      setSettings({ ...settings, [key]: value })
    }
  }

  const handleSave = async () => {
    if (!selectedUniverse || !settings) return

    setLoading(true)
    setStatus('')

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')

      const response = await fetch('/api/admin/universe-settings', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          universe_id: selectedUniverse,
          settings: settings
        })
      })

      const result = await response.json()

      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus('Settings saved successfully!')
        mutateSettings()
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Save failed'}`)
    } finally {
      setLoading(false)
    }
  }

  const handleCreateDefaults = async () => {
    if (!selectedUniverse) return

    setLoading(true)
    setStatus('')

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) throw new Error('No session')

      const response = await fetch('/api/admin/universe-settings', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session.access_token}`
        },
        body: JSON.stringify({
          universe_id: selectedUniverse
        })
      })

      const result = await response.json()

      if (result.error) {
        setStatus(`Error: ${result.error.message}`)
      } else {
        setStatus('Default settings created successfully!')
        mutateSettings()
      }
    } catch (error) {
      setStatus(`Error: ${error instanceof Error ? error.message : 'Creation failed'}`)
    } finally {
      setLoading(false)
    }
  }

  if (universesError) {
    return (
      <div className={styles.container}>
        <div className={styles.error}>
          <h2>Error Loading Universes</h2>
          <p>{universesError.message}</p>
          <button onClick={() => router.push('/admin')} className={styles.backBtn}>
            Back to Admin
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1>Universe Settings</h1>
        <button onClick={() => router.push('/admin')} className={styles.backBtn}>
          Back to Admin
        </button>
      </div>

      <div className={styles.universeSelector}>
        <label htmlFor="universe-select">Select Universe:</label>
        <select
          id="universe-select"
          value={selectedUniverse}
          onChange={(e) => handleUniverseChange(e.target.value)}
          className={styles.select}
        >
          <option value="">Choose a universe...</option>
          {universesData?.universes?.map((universe) => (
            <option key={universe.id} value={universe.id}>
              {universe.name}
            </option>
          ))}
        </select>
      </div>

      {selectedUniverse && (
        <>
          {heartbeat && (
            <div className={styles.section}>
              <h3>Heartbeat</h3>
              <div className={styles.grid}>
                <div className={styles.field}><label>Next Turn</label><div>{fmt(countdown.turn)}</div></div>
                <div className={styles.field}><label>Next Rankings</label><div>{fmt(countdown.cycle)}</div></div>
                <div className={styles.field}><label>Next Port Regen</label><div>{fmt(countdown.update)}</div></div>
              </div>
            </div>
          )}
          {!settings && (
            <div className={styles.createDefaults}>
              <p>No settings found for this universe. Create default settings?</p>
              <button onClick={handleCreateDefaults} disabled={loading} className={styles.createBtn}>
                {loading ? 'Creating...' : 'Create Default Settings'}
              </button>
            </div>
          )}

          {settings && (
            <>
              <div className={styles.tabs}>
                <button
                  className={`${styles.tab} ${activeTab === 'game' ? styles.active : ''}`}
                  onClick={() => setActiveTab('game')}
                >
                  Game Mechanics
                </button>
                <button
                  className={`${styles.tab} ${activeTab === 'economy' ? styles.active : ''}`}
                  onClick={() => setActiveTab('economy')}
                >
                  Economy
                </button>
                <button
                  className={`${styles.tab} ${activeTab === 'scheduler' ? styles.active : ''}`}
                  onClick={() => setActiveTab('scheduler')}
                >
                  Scheduler
                </button>
                <button
                  className={`${styles.tab} ${activeTab === 'advanced' ? styles.active : ''}`}
                  onClick={() => setActiveTab('advanced')}
                >
                  Advanced
                </button>
              </div>

              <div className={styles.settingsPanel}>
                {activeTab === 'game' && (
                  <div className={styles.section}>
                    <h3>Game Mechanics</h3>
                    <div className={styles.grid}>
                      <div className={styles.field}>
                        <label>Game Version</label>
                        <input
                          type="text"
                          value={settings.game_version}
                          onChange={(e) => handleSettingChange('game_version', e.target.value)}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Game Name</label>
                        <input
                          type="text"
                          value={settings.game_name}
                          onChange={(e) => handleSettingChange('game_name', e.target.value)}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Number of Sectors</label>
                        <input
                          type="number"
                          value={settings.number_of_sectors}
                          onChange={(e) => handleSettingChange('number_of_sectors', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Max Links per Sector</label>
                        <input
                          type="number"
                          value={settings.max_links_per_sector}
                          onChange={(e) => handleSettingChange('max_links_per_sector', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Max Planets per Sector</label>
                        <input
                          type="number"
                          value={settings.max_planets_per_sector}
                          onChange={(e) => handleSettingChange('max_planets_per_sector', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Planets Needed for Sector Ownership</label>
                        <input
                          type="number"
                          value={settings.planets_needed_for_sector_ownership}
                          onChange={(e) => handleSettingChange('planets_needed_for_sector_ownership', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Avg Tech Level for Mines</label>
                        <input
                          type="number"
                          value={settings.avg_tech_level_mines}
                          onChange={(e) => handleSettingChange('avg_tech_level_mines', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Avg Tech Level for Emergency Warp Degrade</label>
                        <input
                          type="number"
                          value={settings.avg_tech_emergency_warp_degrade}
                          onChange={(e) => handleSettingChange('avg_tech_emergency_warp_degrade', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Max Avg Tech Level for Federation Sectors</label>
                        <input
                          type="number"
                          value={settings.max_avg_tech_federation_sectors}
                          onChange={(e) => handleSettingChange('max_avg_tech_federation_sectors', parseInt(e.target.value))}
                        />
                      </div>
                    </div>
                  </div>
                )}

                {activeTab === 'economy' && (
                  <div className={styles.section}>
                    <h3>Economy Settings</h3>
                    <div className={styles.grid}>
                      <div className={styles.field}>
                        <label>
                          <input
                            type="checkbox"
                            checked={settings.igb_enabled}
                            onChange={(e) => handleSettingChange('igb_enabled', e.target.checked)}
                          />
                          IGB Enabled
                        </label>
                      </div>
                      <div className={styles.field}>
                        <label>IGB Interest Rate per Update (%)</label>
                        <input
                          type="number"
                          step="0.001"
                          value={settings.igb_interest_rate_per_update}
                          onChange={(e) => handleSettingChange('igb_interest_rate_per_update', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>IGB Loan Rate per Update (%)</label>
                        <input
                          type="number"
                          step="0.001"
                          value={settings.igb_loan_rate_per_update}
                          onChange={(e) => handleSettingChange('igb_loan_rate_per_update', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Planet Interest Rate (%)</label>
                        <input
                          type="number"
                          step="0.001"
                          value={settings.planet_interest_rate}
                          onChange={(e) => handleSettingChange('planet_interest_rate', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists Limit</label>
                        <input
                          type="number"
                          value={settings.colonists_limit}
                          onChange={(e) => handleSettingChange('colonists_limit', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonist Production Rate</label>
                        <input
                          type="number"
                          step="0.001"
                          value={settings.colonist_production_rate}
                          onChange={(e) => handleSettingChange('colonist_production_rate', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Fighter</label>
                        <input
                          type="number"
                          value={settings.colonists_per_fighter}
                          onChange={(e) => handleSettingChange('colonists_per_fighter', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Torpedo</label>
                        <input
                          type="number"
                          value={settings.colonists_per_torpedo}
                          onChange={(e) => handleSettingChange('colonists_per_torpedo', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Ore</label>
                        <input
                          type="number"
                          value={settings.colonists_per_ore}
                          onChange={(e) => handleSettingChange('colonists_per_ore', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Organics</label>
                        <input
                          type="number"
                          value={settings.colonists_per_organics}
                          onChange={(e) => handleSettingChange('colonists_per_organics', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Goods</label>
                        <input
                          type="number"
                          value={settings.colonists_per_goods}
                          onChange={(e) => handleSettingChange('colonists_per_goods', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Energy</label>
                        <input
                          type="number"
                          value={settings.colonists_per_energy}
                          onChange={(e) => handleSettingChange('colonists_per_energy', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Colonists per Credits</label>
                        <input
                          type="number"
                          value={settings.colonists_per_credits}
                          onChange={(e) => handleSettingChange('colonists_per_credits', parseInt(e.target.value))}
                        />
                      </div>
                    </div>
                  </div>
                )}

                {activeTab === 'scheduler' && (
                  <div className={styles.section}>
                    <h3>Scheduler Settings (in minutes)</h3>
                    <div className={styles.grid}>
                      <div className={styles.field}>
                        <label>Tick Interval</label>
                        <input
                          type="number"
                          value={settings.tick_interval_minutes}
                          onChange={(e) => handleSettingChange('tick_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Turns Generation Interval</label>
                        <input
                          type="number"
                          value={settings.turns_generation_interval_minutes}
                          onChange={(e) => handleSettingChange('turns_generation_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Turns per Generation</label>
                        <input
                          type="number"
                          value={settings.turns_per_generation}
                          onChange={(e) => handleSettingChange('turns_per_generation', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Defenses Check Interval</label>
                        <input
                          type="number"
                          value={settings.defenses_check_interval_minutes}
                          onChange={(e) => handleSettingChange('defenses_check_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Xenobes Play Interval</label>
                        <input
                          type="number"
                          value={settings.xenobes_play_interval_minutes}
                          onChange={(e) => handleSettingChange('xenobes_play_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>IGB Interest Accumulation Interval</label>
                        <input
                          type="number"
                          value={settings.igb_interest_accumulation_interval_minutes}
                          onChange={(e) => handleSettingChange('igb_interest_accumulation_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>News Generation Interval</label>
                        <input
                          type="number"
                          value={settings.news_generation_interval_minutes}
                          onChange={(e) => handleSettingChange('news_generation_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Planet Production Interval</label>
                        <input
                          type="number"
                          value={settings.planet_production_interval_minutes}
                          onChange={(e) => handleSettingChange('planet_production_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Port Regeneration Interval</label>
                        <input
                          type="number"
                          value={settings.port_regeneration_interval_minutes}
                          onChange={(e) => handleSettingChange('port_regeneration_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Ships Tow from Fed Sectors Interval</label>
                        <input
                          type="number"
                          value={settings.ships_tow_from_fed_sectors_interval_minutes}
                          onChange={(e) => handleSettingChange('ships_tow_from_fed_sectors_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Rankings Generation Interval</label>
                        <input
                          type="number"
                          value={settings.rankings_generation_interval_minutes}
                          onChange={(e) => handleSettingChange('rankings_generation_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Sector Defenses Degrade Interval</label>
                        <input
                          type="number"
                          value={settings.sector_defenses_degrade_interval_minutes}
                          onChange={(e) => handleSettingChange('sector_defenses_degrade_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Planetary Apocalypse Interval</label>
                        <input
                          type="number"
                          value={settings.planetary_apocalypse_interval_minutes}
                          onChange={(e) => handleSettingChange('planetary_apocalypse_interval_minutes', parseInt(e.target.value))}
                        />
                      </div>
                    </div>
                  </div>
                )}

                {activeTab === 'advanced' && (
                  <div className={styles.section}>
                    <h3>Advanced Settings</h3>
                    <div className={styles.grid}>
                      <div className={styles.field}>
                        <label>Max Accumulated Turns</label>
                        <input
                          type="number"
                          value={settings.max_accumulated_turns}
                          onChange={(e) => handleSettingChange('max_accumulated_turns', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Max Trade Routes per Player</label>
                        <input
                          type="number"
                          value={settings.max_traderoutes_per_player}
                          onChange={(e) => handleSettingChange('max_traderoutes_per_player', parseInt(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Energy per Sector Fighter</label>
                        <input
                          type="number"
                          step="0.001"
                          value={settings.energy_per_sector_fighter}
                          onChange={(e) => handleSettingChange('energy_per_sector_fighter', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>Sector Fighter Degradation Rate (%)</label>
                        <input
                          type="number"
                          step="0.1"
                          value={settings.sector_fighter_degradation_rate}
                          onChange={(e) => handleSettingChange('sector_fighter_degradation_rate', parseFloat(e.target.value))}
                        />
                      </div>
                      <div className={styles.field}>
                        <label>
                          <input
                            type="checkbox"
                            checked={settings.use_new_planet_update_code}
                            onChange={(e) => handleSettingChange('use_new_planet_update_code', e.target.checked)}
                          />
                          Use New Planet Update Code
                        </label>
                      </div>
                      <div className={styles.field}>
                        <label>
                          <input
                            type="checkbox"
                            checked={settings.limit_captured_planets_max_credits}
                            onChange={(e) => handleSettingChange('limit_captured_planets_max_credits', e.target.checked)}
                          />
                          Limit Captured Planets Max Credits
                        </label>
                      </div>
                      <div className={styles.field}>
                        <label>Captured Planets Max Credits</label>
                        <input
                          type="number"
                          value={settings.captured_planets_max_credits}
                          onChange={(e) => handleSettingChange('captured_planets_max_credits', parseInt(e.target.value))}
                        />
                      </div>
                    </div>
                  </div>
                )}

                <div className={styles.actions}>
                  <button onClick={handleSave} disabled={loading} className={styles.saveBtn}>
                    {loading ? 'Saving...' : 'Save Settings'}
                  </button>
                </div>
              </div>
            </>
          )}
        </>
      )}

      {status && (
        <div className={styles.status}>
          {status}
        </div>
      )}
    </div>
  )
}


