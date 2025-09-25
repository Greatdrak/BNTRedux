import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const { planetId, transfers } = await request.json()

    // Validate input
    if (!planetId || !transfers || !Array.isArray(transfers)) {
      return NextResponse.json({ success: false, error: 'Missing required fields' }, { status: 400 })
    }

    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    // Get the universe_id from the planet
    const { data: planetData } = await supabaseAdmin
      .from('planets')
      .select('sectors!inner(universe_id)')
      .eq('id', planetId)
      .single()
    
    const universeId = planetData?.sectors?.[0]?.universe_id
    if (!universeId) {
      return NextResponse.json({ success: false, error: 'Planet not found' }, { status: 404 })
    }

    // Get player data
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id, universe_id, user_id, handle')
      .eq('user_id', userId)
      .eq('universe_id', universeId)
      .single()

    if (playerError || !player) {
      return NextResponse.json({ success: false, error: 'Player not found' }, { status: 404 })
    }

    // Get current planet, ship, and player data
    const { data: planet } = await supabaseAdmin
      .from('planets')
      .select('ore, organics, goods, energy, fighters, torpedoes, credits, colonists')
      .eq('id', planetId)
      .eq('owner_player_id', player.id)
      .single()

    if (!planet) {
      return NextResponse.json({ success: false, error: 'Planet not found or not owned by player' }, { status: 404 })
    }

    const { data: ship } = await supabaseAdmin
      .from('ships')
      .select('ore, organics, goods, energy, fighters, torpedoes, colonists, credits')
      .eq('player_id', player.id)
      .single()

    if (!ship) {
      return NextResponse.json({ success: false, error: 'Ship not found' }, { status: 404 })
    }

    // Process transfers
    const planetUpdates: any = {}
    const shipUpdates: any = {}

    for (const transfer of transfers) {
      const { resource, quantity, toPlanet } = transfer
      
      if (quantity <= 0) continue

      if (toPlanet) {
        // Transfer from ship to planet
        const availableAmount = resource === 'credits' ? ship.credits : (ship as any)[resource]
        if (availableAmount < quantity) {
          return NextResponse.json({ 
            success: false, 
            error: `Not enough ${resource} on ship (have ${availableAmount}, need ${quantity})` 
          }, { status: 400 })
        }
        
        if (resource === 'credits') {
          shipUpdates.credits = (shipUpdates.credits || ship.credits) - quantity
          planetUpdates.credits = (planetUpdates.credits || planet.credits) + quantity
        } else {
          shipUpdates[resource] = (shipUpdates[resource] || (ship as any)[resource]) - quantity
          planetUpdates[resource] = (planetUpdates[resource] || (planet as any)[resource]) + quantity
        }
      } else {
        // Transfer from planet to ship
        const availableAmount = resource === 'credits' ? planet.credits : (planet as any)[resource]
        if (availableAmount < quantity) {
          return NextResponse.json({ 
            success: false, 
            error: `Not enough ${resource} on planet (have ${availableAmount}, need ${quantity})` 
          }, { status: 400 })
        }
        
        if (resource === 'credits') {
          planetUpdates.credits = (planetUpdates.credits || planet.credits) - quantity
          shipUpdates.credits = (shipUpdates.credits || ship.credits) + quantity
        } else {
          planetUpdates[resource] = (planetUpdates[resource] || (planet as any)[resource]) - quantity
          shipUpdates[resource] = (shipUpdates[resource] || (ship as any)[resource]) + quantity
        }
      }
    }

    // Update planet
    if (Object.keys(planetUpdates).length > 0) {
      const { error: planetError } = await supabaseAdmin
        .from('planets')
        .update(planetUpdates)
        .eq('id', planetId)
      
      if (planetError) {
        console.error('Planet update error:', planetError)
        return NextResponse.json({ success: false, error: 'Failed to update planet' }, { status: 500 })
      }
    }

    // Update ship
    if (Object.keys(shipUpdates).length > 0) {
      const { error: shipError } = await supabaseAdmin
        .from('ships')
        .update(shipUpdates)
        .eq('player_id', player.id)
      
      if (shipError) {
        console.error('Ship update error:', shipError)
        return NextResponse.json({ success: false, error: 'Failed to update ship' }, { status: 500 })
      }
    }

    return NextResponse.json({ 
      success: true, 
      message: 'Transfer completed successfully',
      transfers: transfers.length
    })

  } catch (error) {
    console.error('Transfer API error:', error)
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500 }
    )
  }
}
