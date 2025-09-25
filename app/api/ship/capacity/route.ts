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
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .eq('id', universeId)
        .single()
      universe = data
    } else {
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

    // Get player data
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universe.id)
      .maybeSingle()

    if (playerError || !player) {
      console.error('Player error:', playerError)
      return NextResponse.json({ error: { code: 'not_found', message: 'Player not found' } }, { status: 404 })
    }

    // Get ship data
    const { data: ship, error: shipError } = await supabaseAdmin
      .from('ships')
      .select('id')
      .eq('player_id', player.id)
      .single()

    if (shipError || !ship) {
      console.error('Ship error:', shipError)
      return NextResponse.json({ error: { code: 'not_found', message: 'Ship not found' } }, { status: 404 })
    }

    // Get capacity data using BNT formula RPC function
    const { data: capacityData, error: capacityError } = await supabaseAdmin
      .rpc('get_ship_capacity', {
        p_ship_id: ship.id
      })

    if (capacityError) {
      console.error('Capacity error:', capacityError)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to get capacity data' } }, { status: 500 })
    }

    return NextResponse.json(capacityData)

  } catch (error) {
    console.error('Error in /api/ship/capacity:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
