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

    // Get player data
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('*')
      .eq('user_id', userId)
      .single()

    if (playerError || !player) {
      return NextResponse.json({ 
        error: { code: 'not_found', message: 'Player not found' },
        debug: { playerError, userId }
      }, { status: 404 })
    }

    // Get ship data
    const { data: ship, error: shipError } = await supabaseAdmin
      .from('ships')
      .select('*')
      .eq('player_id', player.id)
      .single()

    if (shipError || !ship) {
      return NextResponse.json({ 
        error: { code: 'not_found', message: 'Ship not found' },
        debug: { shipError, playerId: player.id }
      }, { status: 404 })
    }

    // Check ship table structure
    const { data: columns } = await supabaseAdmin
      .from('information_schema.columns')
      .select('column_name, data_type')
      .eq('table_name', 'ships')
      .eq('table_schema', 'public')

    return NextResponse.json({
      success: true,
      player: {
        id: player.id,
        user_id: player.user_id,
        current_sector: player.current_sector
      },
      ship: ship,
      shipColumns: columns?.map(c => c.column_name) || [],
      debug: {
        playerExists: !!player,
        shipExists: !!ship,
        shipColumnsCount: columns?.length || 0
      }
    })

  } catch (error) {
    console.error('Error in /api/ship/debug:', error)
    return NextResponse.json({ 
      error: { code: 'server_error', message: 'Internal server error' },
      debug: { error: error instanceof Error ? error.message : 'Unknown error' }
    }, { status: 500 })
  }
}
