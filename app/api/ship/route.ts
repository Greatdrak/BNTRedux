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

    // Get player data - filter by universe if provided
    let playerQuery = supabaseAdmin
      .from('players')
      .select('id, current_sector')
      .eq('user_id', userId)
    
    if (universeId) {
      playerQuery = playerQuery.eq('universe_id', universeId)
    }
    
    const { data: player, error: playerError } = await playerQuery.single()

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
      cargo: ship.cargo || 1000,
      fighters: ship.fighters || 0,
      torpedoes: ship.torpedoes || 0,
      atSpecialPort
    })

  } catch (error) {
    console.error('Error in /api/ship:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
