import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId
    
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    // Get universe - either specified or default to first available
    let universe: any = null
    
    if (universeId) {
      // Get specific universe
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .eq('id', universeId)
        .single()
      universe = data
    } else {
      // Get first available universe (fallback for existing players)
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .order('created_at', { ascending: true })
        .limit(1)
        .single()
      universe = data
    }
    
    if (!universe) {
      return NextResponse.json({ error: { code: 'not_found', message: 'No universe found' } }, { status: 404 })
    }

    // Get player data - always filter by universe
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id, current_sector')
      .eq('user_id', userId)
      .eq('universe_id', universe.id)
      .maybeSingle()

    if (playerError || !player) {
      console.error('Player error:', playerError)
      return NextResponse.json({ error: { code: 'not_found', message: 'Player not found' } }, { status: 404 })
    }

    // Get ship data - use * to get all columns in case some are missing
    const { data: ship, error: shipError } = await supabaseAdmin
      .from('ships')
      .select('*')
      .eq('player_id', player.id)
      .single()

    if (shipError || !ship) {
      console.error('Ship error:', shipError)
      return NextResponse.json({ error: { code: 'not_found', message: 'Ship not found' } }, { status: 404 })
    }

    // Check if player is at a special port
    const { data: port } = await supabaseAdmin
      .from('ports')
      .select('kind')
      .eq('sector_id', player.current_sector)
      .eq('kind', 'special')
      .single()

    const atSpecialPort = !!port

    return NextResponse.json({
      name: ship.name || 'Ship',
      hull: ship.hull || 0,
      hull_max: ship.hull_max || 100,
      hull_lvl: ship.hull_lvl || 1,
      shield: ship.shield || 0,
      shield_max: ship.shield_max || 0,
      shield_lvl: ship.shield_lvl || 0,
      engine_lvl: ship.engine_lvl || 1,
      comp_lvl: ship.comp_lvl || 1,
      sensor_lvl: ship.sensor_lvl || 1,
      power_lvl: ship.power_lvl || 1,
      beam_lvl: ship.beam_lvl || 0,
      torp_launcher_lvl: ship.torp_launcher_lvl || 0,
      cloak_lvl: ship.cloak_lvl || 0,
      armor: ship.armor || 0,
      armor_max: ship.armor_max || 0,
      cargo: ship.cargo || 1000,
      fighters: ship.fighters || 0,
      torpedoes: ship.torpedoes || 0,
      credits: ship.credits || 0,
      // Device quantities
      device_space_beacons: ship.device_space_beacons || 0,
      device_warp_editors: ship.device_warp_editors || 0,
      device_genesis_torpedoes: ship.device_genesis_torpedoes || 0,
      // Device booleans
      device_emergency_warp: ship.device_emergency_warp || false,
      device_escape_pod: ship.device_escape_pod !== false, // default true
      device_fuel_scoop: ship.device_fuel_scoop || false,
      device_last_seen: ship.device_last_seen || false,
      atSpecialPort
    })

  } catch (error) {
    console.error('Error in /api/ship:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
