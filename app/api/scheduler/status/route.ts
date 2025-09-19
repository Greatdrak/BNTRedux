import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/scheduler/status - Get heartbeat and next-due info for a universe
export async function GET(request: NextRequest) {
  try {
    // Allow both authenticated and bearer (players and admin). If no auth, still allow read-only.
    // We won't block if unauthenticated; universe status is not sensitive.
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    // Pull settings with last_* timestamps
    const { data, error } = await supabaseAdmin
      .from('universe_settings')
      .select('*')
      .eq('universe_id', universeId)
      .limit(1)
      .maybeSingle()

    if (error || !data) {
      return NextResponse.json({ error: { code: 'not_found', message: 'Scheduler status not found' } }, { status: 404 })
    }
    
    // Calculate time until next events
    const now = new Date()
    const nextTurnGen = data.last_turn_generation && data.turns_generation_interval_minutes
      ? new Date(new Date(data.last_turn_generation).getTime() + data.turns_generation_interval_minutes * 60 * 1000)
      : null
    const nextUpdate = data.last_port_regeneration && data.port_regeneration_interval_minutes
      ? new Date(new Date(data.last_port_regeneration).getTime() + data.port_regeneration_interval_minutes * 60 * 1000)
      : null
    const nextCycle = data.last_rankings && data.rankings_generation_interval_minutes
      ? new Date(new Date(data.last_rankings).getTime() + data.rankings_generation_interval_minutes * 60 * 1000)
      : null

    const timeUntilTurnGen = nextTurnGen ? Math.max(0, Math.floor((nextTurnGen.getTime() - now.getTime()) / 1000)) : 0
    const timeUntilCycle = nextCycle ? Math.max(0, Math.floor((nextCycle.getTime() - now.getTime()) / 1000)) : 0
    const timeUntilUpdate = nextUpdate ? Math.max(0, Math.floor((nextUpdate.getTime() - now.getTime()) / 1000)) : 0

    return NextResponse.json({
      universe_id: universeId,
      next_turn_generation: nextTurnGen?.toISOString() ?? null,
      next_cycle_event: nextCycle?.toISOString() ?? null,
      next_update_event: nextUpdate?.toISOString() ?? null,
      time_until_turn_generation_seconds: timeUntilTurnGen,
      time_until_cycle_seconds: timeUntilCycle,
      time_until_update_seconds: timeUntilUpdate,
      last: {
        tick: data.last_tick,
        turn_generation: data.last_turn_generation,
        defenses_check: data.last_defenses_check,
        xenobes_play: data.last_xenobes_play,
        igb_interest: data.last_igb_interest,
        news: data.last_news,
        planet_production: data.last_planet_production,
        port_regeneration: data.last_port_regeneration,
        ships_tow_fed: data.last_ships_tow_fed,
        rankings: data.last_rankings,
        sector_defenses_degrade: data.last_sector_defenses_degrade,
        apocalypse: data.last_apocalypse
      },
      status: {
        turn_generation: timeUntilTurnGen === 0 ? 'ready' : 'waiting',
        cycle_event: timeUntilCycle === 0 ? 'ready' : 'waiting',
        update_event: timeUntilUpdate === 0 ? 'ready' : 'waiting'
      }
    })

  } catch (error) {
    console.error('Error in /api/scheduler/status:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}


