import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
        const { planetId, orePercent, organicsPercent, goodsPercent, energyPercent, fightersPercent, torpedoesPercent } = await request.json()

    // Validate input
    if (!planetId || orePercent === undefined || organicsPercent === undefined || goodsPercent === undefined || energyPercent === undefined || fightersPercent === undefined || torpedoesPercent === undefined) {
      return NextResponse.json({ success: false, error: 'Missing required fields' }, { status: 400 })
    }

    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    // Get player data
    console.log('Looking for player with user_id:', userId)
    
    // First, let's see all players for this user
    const { data: allPlayers } = await supabaseAdmin
      .from('players')
      .select('id, universe_id, user_id, handle')
      .eq('user_id', userId)
    
    console.log('All players for this user:', allPlayers)
    
    // Get the universe_id from the planet
    const { data: planetData } = await supabaseAdmin
      .from('planets')
      .select('sectors!inner(universe_id)')
      .eq('id', planetId)
      .single()
    
    const universeId = planetData?.sectors?.[0]?.universe_id
    console.log('Planet universe_id:', universeId)
    
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id, universe_id, user_id, handle')
      .eq('user_id', userId)
      .eq('universe_id', universeId)
      .single()

    console.log('Player query result:', { player, playerError })

    if (playerError || !player) {
      console.error('Player not found for user_id:', userId)
      return NextResponse.json({ success: false, error: 'Player not found' }, { status: 404 })
    }

    // Call the RPC function to update production allocation
    const params = {
      p_planet_id: planetId,
      p_ore_percent: orePercent,
      p_organics_percent: organicsPercent,
      p_goods_percent: goodsPercent,
      p_energy_percent: energyPercent,
      p_fighters_percent: fightersPercent,
      p_torpedoes_percent: torpedoesPercent,
      p_player_id: player.id
    }
    
    console.log('Calling update_planet_production_allocation with params:', params)
    
    const { data, error } = await supabaseAdmin.rpc('update_planet_production_allocation', params)

    if (error) {
      console.error('Production allocation update error:', error)
      console.error('Error details:', {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint
      })
      return NextResponse.json({ success: false, error: error.message }, { status: 500 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Production allocation API error:', error)
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500 }
    )
  }
}
