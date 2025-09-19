import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// POST /api/mines/deploy - Deploy mines using torpedoes
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    const body = await request.json()
    const { sector_number, universe_id, torpedoes_to_use = 1 } = body

    if (!sector_number || !universe_id) {
      return NextResponse.json({ error: { code: 'missing_params', message: 'sector_number and universe_id are required' } }, { status: 400 })
    }

    if (torpedoes_to_use < 1 || torpedoes_to_use > 10) {
      return NextResponse.json({ error: { code: 'invalid_count', message: 'torpedoes_to_use must be between 1 and 10' } }, { status: 400 })
    }

    // Get player and sector info
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universe_id)
      .single()

    if (playerError || !player) {
      return NextResponse.json({ error: { code: 'player_not_found', message: 'Player not found' } }, { status: 404 })
    }

    const { data: sector, error: sectorError } = await supabaseAdmin
      .from('sectors')
      .select('id')
      .eq('number', sector_number)
      .eq('universe_id', universe_id)
      .single()

    if (sectorError || !sector) {
      return NextResponse.json({ error: { code: 'sector_not_found', message: 'Sector not found' } }, { status: 404 })
    }

    // Deploy mines using the RPC function
    const { data: result, error } = await supabaseAdmin
      .rpc('deploy_mines', {
        p_player_id: player.id,
        p_sector_id: sector.id,
        p_universe_id: universe_id,
        p_torpedoes_to_use: torpedoes_to_use
      })

    if (error) {
      console.error('Error deploying mines:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to deploy mines' } }, { status: 500 })
    }

    if (result.error) {
      return NextResponse.json({ error: { code: 'deployment_failed', message: result.error } }, { status: 400 })
    }

    return NextResponse.json({ 
      success: true, 
      message: `Deployed ${torpedoes_to_use} torpedo mine(s) in sector ${sector_number}`,
      ...result
    })

  } catch (error) {
    console.error('Error in /api/mines/deploy:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}


