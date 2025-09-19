'use client'

import { useState, useEffect } from 'react'
import useSWR from 'swr'
import { createClient } from '@supabase/supabase-js'
import styles from './page.module.css'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

interface CronLog {
  id: string
  event_type: string
  event_name: string
  status: string
  message: string | null
  execution_time_ms: number | null
  triggered_at: string
  metadata: any
}

interface CronLogSummary {
  event_type: string
  event_name: string
  last_execution: string | null
  last_status: string | null
  last_message: string | null
  execution_count_24h: number
  avg_execution_time_ms: number | null
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
    throw new Error('Failed to fetch')
  }
  
  return response.json()
}

export default function CronLogsPage() {
  const [selectedUniverse, setSelectedUniverse] = useState<string>('')
  const [universes, setUniverses] = useState<Universe[]>([])

  // Fetch universes
  const { data: universesData, error: universesError } = useSWR('/api/admin/universes', fetcher)

  // Fetch cron logs for selected universe (last 50 logs to keep page manageable)
  const { data: cronLogsData, error: cronLogsError, mutate } = useSWR(
    selectedUniverse ? `/api/admin/cron-logs?universe_id=${selectedUniverse}&limit=50` : null,
    fetcher,
    { refreshInterval: 5000 } // Refresh every 5 seconds
  )

  useEffect(() => {
    if (universesData?.universes) {
      setUniverses(universesData.universes)
      if (universesData.universes.length > 0 && !selectedUniverse) {
        setSelectedUniverse(universesData.universes[0].id)
      }
    }
  }, [universesData, selectedUniverse])

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString()
  }

  const formatDuration = (ms: number | null) => {
    if (!ms) return '-'
    if (ms < 1000) return `${ms}ms`
    return `${(ms / 1000).toFixed(2)}s`
  }

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'success': return '✅'
      case 'error': return '❌'
      case 'skipped': return '⏭️'
      default: return '❓'
    }
  }

  const getEventIcon = (eventType: string) => {
    switch (eventType) {
      case 'heartbeat': return '💓'
      case 'turn_generation': return '🔄'
      case 'port_regeneration': return '🏭'
      case 'rankings': return '📊'
      case 'defenses_check': return '🛡️'
      case 'xenobes_play': return '👾'
      case 'igb_interest': return '💰'
      case 'news': return '📰'
      case 'planet_production': return '🪐'
      case 'ships_tow_fed': return '🚢'
      case 'sector_defenses_degrade': return '⚡'
      case 'apocalypse': return '💥'
      default: return '⚙️'
    }
  }

  if (universesError) {
    return (
      <div className={styles.container}>
        <h1>Cron Logs</h1>
        <div className={styles.error}>Error loading universes: {universesError.message}</div>
      </div>
    )
  }

  if (cronLogsError) {
    return (
      <div className={styles.container}>
        <h1>Cron Logs</h1>
        <div className={styles.error}>Error loading cron logs: {cronLogsError.message}</div>
      </div>
    )
  }

  const logs: CronLog[] = cronLogsData?.logs || []
  const summary: CronLogSummary[] = cronLogsData?.summary || []

  return (
    <div className={styles.container}>
      <h1>Cron Execution Logs</h1>
      
      <div className={styles.controls}>
        <div className={styles.universeSelector}>
          <label htmlFor="universe">Universe:</label>
          <select
            id="universe"
            value={selectedUniverse}
            onChange={(e) => setSelectedUniverse(e.target.value)}
          >
            <option value="">Select Universe</option>
            {universes.map((universe) => (
              <option key={universe.id} value={universe.id}>
                {universe.name}
              </option>
            ))}
          </select>
        </div>
        
        <button onClick={() => mutate()} className={styles.refreshButton}>
          🔄 Refresh
        </button>
      </div>

      {selectedUniverse && (
        <>
          {/* Summary Section */}
          <div className={styles.summarySection}>
            <h2>Event Summary</h2>
            <div className={styles.summaryGrid}>
              {summary.map((item) => (
                <div key={item.event_type} className={styles.summaryCard}>
                  <div className={styles.summaryHeader}>
                    <span className={styles.eventIcon}>{getEventIcon(item.event_type)}</span>
                    <span className={styles.eventName}>{item.event_name}</span>
                    <span className={styles.statusIcon}>{getStatusIcon(item.last_status || 'unknown')}</span>
                  </div>
                  <div className={styles.summaryDetails}>
                    <div className={styles.summaryRow}>
                      <span className={styles.label}>Last Run:</span>
                      <span className={styles.value}>
                        {item.last_execution ? formatTimestamp(item.last_execution) : 'Never'}
                      </span>
                    </div>
                    <div className={styles.summaryRow}>
                      <span className={styles.label}>24h Count:</span>
                      <span className={styles.value}>{item.execution_count_24h}</span>
                    </div>
                    <div className={styles.summaryRow}>
                      <span className={styles.label}>Avg Time:</span>
                      <span className={styles.value}>{formatDuration(item.avg_execution_time_ms)}</span>
                    </div>
                    {item.last_message && (
                      <div className={styles.summaryRow}>
                        <span className={styles.label}>Last Message:</span>
                        <span className={styles.value}>{item.last_message}</span>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Recent Logs Section */}
          <div className={styles.logsSection}>
            <h2>Recent Execution Logs</h2>
            <div className={styles.logsTable}>
              <div className={styles.logsHeader}>
                <div className={styles.logsHeaderCell}>Time</div>
                <div className={styles.logsHeaderCell}>Event</div>
                <div className={styles.logsHeaderCell}>Status</div>
                <div className={styles.logsHeaderCell}>Duration</div>
                <div className={styles.logsHeaderCell}>Message</div>
              </div>
              {logs.length === 0 ? (
                <div className={styles.emptyLogs}>No cron logs found for this universe</div>
              ) : (
                logs.map((log) => (
                  <div key={log.id} className={styles.logsRow}>
                    <div className={styles.logsCell}>
                      {formatTimestamp(log.triggered_at)}
                    </div>
                    <div className={styles.logsCell}>
                      <span className={styles.eventIcon}>{getEventIcon(log.event_type)}</span>
                      {log.event_name}
                    </div>
                    <div className={styles.logsCell}>
                      <span className={styles.statusIcon}>{getStatusIcon(log.status)}</span>
                      {log.status}
                    </div>
                    <div className={styles.logsCell}>
                      {formatDuration(log.execution_time_ms)}
                    </div>
                    <div className={styles.logsCell}>
                      {log.message || '-'}
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </>
      )}

      <div className={styles.footer}>
        <a href="/admin" className={styles.backLink}>← Back to Admin</a>
      </div>
    </div>
  )
}
