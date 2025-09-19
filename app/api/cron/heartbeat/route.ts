import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { getUniverseSettings } from '@/lib/universe-settings'

export async function POST(request: NextRequest) {
  try {
    const cronSecret = process.env.CRON_SECRET
    const xCronHeader = request.headers.get('x-cron')
    const xVercelCronHeader = request.headers.get('x-vercel-cron')

    if (!xVercelCronHeader && (!xCronHeader || !cronSecret || xCronHeader !== cronSecret)) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const nowIso = new Date().toISOString()

    // Load universes (settings read via RPC per-universe to avoid schema drift)
    const { data: universes, error: universesError } = await supabaseAdmin
      .from('universes')
      .select('id,name')

    if (universesError) {
      return NextResponse.json({ error: 'Failed to fetch universes' }, { status: 500 })
    }

    const results = { universesProcessed: 0, tasksRun: 0, errors: [] as string[] }

    // Helper: seconds until ISO time
    const secondsUntil = (iso: string | null) => {
      if (!iso) return 0
      const diff = new Date(iso).getTime() - Date.now()
      return Math.floor(diff / 1000)
    }

    for (const u of universes || []) {
      try {
        // Log heartbeat start
        await supabaseAdmin.rpc('log_cron_event', {
          p_universe_id: u.id,
          p_event_type: 'heartbeat',
          p_event_name: 'Cron Heartbeat',
          p_status: 'success',
          p_message: 'Heartbeat check started',
          p_execution_time_ms: null,
          p_metadata: { universe_name: u.name }
        })

        // Get universe settings to check individual event intervals
        const settings = await getUniverseSettings(u.id)
        const s: any = settings || {}
        
        // Debug: Show a few key timestamps
        console.log(`🔍 ${u.name} timestamps:`, {
          turn_gen: s.last_turn_generation,
          port_regen: s.last_port_regeneration_event,
          rankings: s.last_rankings_generation_event
        })
        

        // Helper to check if an event is due
        const isDue = (intervalMinutes: number | null, lastEvent: string | null) => {
          if (!intervalMinutes || intervalMinutes <= 0) return false
          
          // If lastEvent is null/undefined, the event has never run, so it's due immediately
          if (!lastEvent) {
            return true
          }
          
          const now = Date.now()
          const lastMs = new Date(lastEvent).getTime()
          return now - lastMs >= intervalMinutes * 60 * 1000
        }

        // Check all scheduled events and log each one
        const eventsToCheck = [
          { 
            key: 'turn_generation', 
            name: 'Turn Generation', 
            due: isDue(s.turns_generation_interval_minutes, s.last_turn_generation), 
            rpc: 'generate_turns_for_universe', 
            args: { p_turns_to_add: 4 },
            interval: s.turns_generation_interval_minutes
          },
          { 
            key: 'port_regeneration', 
            name: 'Port Regeneration', 
            due: isDue(s.port_regeneration_interval_minutes, s.last_port_regeneration_event), 
            rpc: 'update_port_stock_dynamics', 
            args: {},
            interval: s.port_regeneration_interval_minutes
          },
          { 
            key: 'rankings', 
            name: 'Rankings Update', 
            due: isDue(s.rankings_generation_interval_minutes, s.last_rankings_generation_event), 
            rpc: 'update_universe_rankings', 
            args: {},
            interval: s.rankings_generation_interval_minutes
          },
          { 
            key: 'defenses_check', 
            name: 'Defenses Check', 
            due: isDue(s.defenses_check_interval_minutes, s.last_defenses_check_event), 
            rpc: 'run_defenses_checks', 
            args: {},
            interval: s.defenses_check_interval_minutes
          },
          { 
            key: 'xenobes_play', 
            name: 'Xenobes Play', 
            due: isDue(s.xenobes_play_interval_minutes, s.last_xenobes_play_event), 
            rpc: 'run_xenobes_turn', 
            args: {},
            interval: s.xenobes_play_interval_minutes
          },
          { 
            key: 'igb_interest', 
            name: 'IGB Interest', 
            due: isDue(s.igb_interest_accumulation_interval_minutes, s.last_igb_interest_accumulation_event), 
            rpc: 'apply_igb_interest', 
            args: {},
            interval: s.igb_interest_accumulation_interval_minutes
          },
          { 
            key: 'news', 
            name: 'News Generation', 
            due: isDue(s.news_generation_interval_minutes, s.last_news_generation_event), 
            rpc: 'generate_universe_news', 
            args: {},
            interval: s.news_generation_interval_minutes
          },
          { 
            key: 'planet_production', 
            name: 'Planet Production', 
            due: isDue(s.planet_production_interval_minutes, s.last_planet_production_event), 
            rpc: 'run_planet_production', 
            args: {},
            interval: s.planet_production_interval_minutes
          },
          { 
            key: 'ships_tow_fed', 
            name: 'Ships Tow from Fed', 
            due: isDue(s.ships_tow_from_fed_sectors_interval_minutes, s.last_ships_tow_from_fed_sectors_event), 
            rpc: 'tow_ships_from_fed', 
            args: {},
            interval: s.ships_tow_from_fed_sectors_interval_minutes
          },
          { 
            key: 'sector_defenses_degrade', 
            name: 'Sector Defenses Degrade', 
            due: isDue(s.sector_defenses_degrade_interval_minutes, s.last_sector_defenses_degrade_event), 
            rpc: 'degrade_sector_defenses', 
            args: {},
            interval: s.sector_defenses_degrade_interval_minutes
          },
          { 
            key: 'apocalypse', 
            name: 'Planetary Apocalypse', 
            due: isDue(s.planetary_apocalypse_interval_minutes, s.last_planetary_apocalypse_event), 
            rpc: 'run_apocalypse_tick', 
            args: {},
            interval: s.planetary_apocalypse_interval_minutes
          }
        ]

        for (const event of eventsToCheck) {
          const startTime = Date.now()
          let status = 'skipped'
          let message = 'Not due'
          let metadata = {}


          if (event.due) {
            try {
              console.log(`🔄 ${event.name} for ${u.name} (interval: ${event.interval}min)`)
              const { data: rpcResult, error: rpcError } = await supabaseAdmin.rpc(event.rpc, { p_universe_id: u.id, ...event.args })
              
              if (rpcError) {
                status = 'error'
                message = rpcError.message
                console.error(`❌ ${event.name} failed for ${u.name}:`, rpcError.message)
              } else {
                status = 'success'
                metadata = rpcResult || {}
                results.tasksRun++
                
                // Log meaningful statistics based on event type
                if (event.key === 'turn_generation' && rpcResult) {
                  const stats = rpcResult[0] || rpcResult
                  message = `Generated ${stats.total_turns_generated} turns for ${stats.players_updated} players (${stats.players_at_cap} at cap)`
                  console.log(`✅ ${event.name}: ${message}`)
                } else if (event.key === 'port_regeneration' && rpcResult) {
                  const stats = rpcResult[0] || rpcResult
                  message = `Updated ${stats.ports_updated} ports (${stats.ports_regenerated} regenerated, ${stats.ports_decayed} decayed)`
                  console.log(`✅ ${event.name}: ${message}`)
                } else if (event.key === 'planet_production' && rpcResult) {
                  const stats = rpcResult[0] || rpcResult
                  message = `Processed ${stats.planets_processed} planets (${stats.colonists_grown} grew, ${stats.resources_produced} produced, ${stats.credits_produced} credits, ${stats.interest_generated} interest)`
                  console.log(`✅ ${event.name}: ${message}`)
                } else {
                  message = `${event.name} completed successfully`
                  console.log(`✅ ${event.name} completed`)
                }
                
                // Update scheduler timestamp
                await supabaseAdmin.rpc('update_scheduler_timestamp', { 
                  p_universe_id: u.id, 
                  p_event_type: event.key, 
                  p_timestamp: nowIso 
                })
              }
            } catch (error) {
              status = 'error'
              message = error instanceof Error ? error.message : 'Unknown error'
              console.error(`❌ ${event.name} exception for ${u.name}:`, error)
            }
          } else {
            message = `Not due (interval: ${event.interval || 0}min)`
          }

          const executionTime = Date.now() - startTime

          // Log the event execution
          await supabaseAdmin.rpc('log_cron_event', {
            p_universe_id: u.id,
            p_event_type: event.key,
            p_event_name: event.name,
            p_status: status,
            p_message: message,
            p_execution_time_ms: executionTime,
            p_metadata: { 
              universe_name: u.name, 
              interval_minutes: event.interval,
              due: event.due,
              ...metadata 
            }
          })
        }

        results.universesProcessed++
      } catch (err: any) {
        results.errors.push(`Universe ${u?.name || u?.id}: ${err?.message || err}`)
      }
    }

    return NextResponse.json({ ok: true, ...results })
  } catch (error) {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}


