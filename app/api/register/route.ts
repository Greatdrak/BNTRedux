import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// POST /api/register - Create a new player in a specific universe
export async function POST(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { universe_id, handle } = body
    
    // Validate inputs
    if (!universe_id) {
      return NextResponse.json({ error: { code: 'missing_universe', message: 'Universe ID is required' } }, { status: 400 })
    }
    
    if (!handle || handle.trim().length === 0) {
      return NextResponse.json({ error: { code: 'missing_handle', message: 'Player handle is required' } }, { status: 400 })
    }
    
    // Validate handle format
    const cleanHandle = handle.trim()
    if (cleanHandle.length < 3 || cleanHandle.length > 20) {
      return NextResponse.json({ error: { code: 'invalid_handle', message: 'Handle must be 3-20 characters' } }, { status: 400 })
    }
    
    if (!/^[a-zA-Z0-9_-]+$/.test(cleanHandle)) {
      return NextResponse.json({ error: { code: 'invalid_handle', message: 'Handle can only contain letters, numbers, underscores, and hyphens' } }, { status: 400 })
    }
    
    // Check if universe exists
    const { data: universe } = await supabaseAdmin
      .from('universes')
      .select('id, name')
      .eq('id', universe_id)
      .single()
    
    if (!universe) {
      return NextResponse.json({ error: { code: 'universe_not_found', message: 'Universe not found' } }, { status: 404 })
    }
    
    // Check if player already exists in this universe
    const { data: existingPlayer } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universe_id)
      .maybeSingle()
    
    if (existingPlayer) {
      return NextResponse.json({ error: { code: 'player_exists', message: 'Player already exists in this universe' } }, { status: 400 })
    }
    
    // Check if handle is already taken in this universe
    const { data: handleExists } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('universe_id', universe_id)
      .eq('handle', cleanHandle)
      .maybeSingle()
    
    if (handleExists) {
      return NextResponse.json({ error: { code: 'handle_taken', message: 'Handle is already taken in this universe' } }, { status: 400 })
    }
    
    // Get sector 0 (Sol Hub) in the universe
    const { data: sector0 } = await supabaseAdmin
      .from('sectors')
      .select('id')
      .eq('universe_id', universe_id)
      .eq('number', 0)
      .single()
    
    if (!sector0) {
      return NextResponse.json({ error: { code: 'sector_not_found', message: 'Sol Hub (Sector 0) not found in universe' } }, { status: 500 })
    }
    
    // Create player
    const { data: newPlayer, error: playerError } = await supabaseAdmin
      .from('players')
      .insert({
        user_id: userId,
        universe_id: universe_id,
        handle: cleanHandle,
        credits: 1000,
        turns: 60,
        turn_cap: 120,
        current_sector: sector0.id
      })
      .select()
      .single()
    
    if (playerError) {
      console.error('Error creating player:', playerError)
      return NextResponse.json({ error: { code: 'player_creation_failed', message: 'Failed to create player' } }, { status: 500 })
    }
    
    // Create ship
    const { data: newShip, error: shipError } = await supabaseAdmin
      .from('ships')
      .insert({
        player_id: newPlayer.id,
        name: 'Scout',
        hull: 100,
        shield: 0,
        cargo: 1000,
        fighters: 0,
        torpedoes: 0,
        engine_lvl: 1,
        hull_lvl: 1,
        shield_lvl: 0,
        comp_lvl: 1,
        sensor_lvl: 1
      })
      .select()
      .single()
    
    if (shipError) {
      console.error('Error creating ship:', shipError)
      return NextResponse.json({ error: { code: 'ship_creation_failed', message: 'Failed to create ship' } }, { status: 500 })
    }
    
    // Create inventory
    const { error: inventoryError } = await supabaseAdmin
      .from('inventories')
      .insert({
        player_id: newPlayer.id,
        ore: 0,
        organics: 0,
        goods: 0,
        energy: 0
      })
    
    if (inventoryError) {
      console.error('Error creating inventory:', inventoryError)
      return NextResponse.json({ error: { code: 'inventory_creation_failed', message: 'Failed to create inventory' } }, { status: 500 })
    }
    
    // Return success
    return NextResponse.json({
      ok: true,
      player: {
        id: newPlayer.id,
        handle: newPlayer.handle,
        universe_id: newPlayer.universe_id,
        universe_name: universe.name,
        credits: newPlayer.credits,
        turns: newPlayer.turns,
        turn_cap: newPlayer.turn_cap,
        current_sector: newPlayer.current_sector,
        current_sector_number: 0
      },
      ship: {
        name: newShip.name,
        hull: newShip.hull,
        hull_max: newShip.hull_max,
        hull_lvl: newShip.hull_lvl,
        shield: newShip.shield,
        shield_max: newShip.shield_max,
        shield_lvl: newShip.shield_lvl,
        engine_lvl: newShip.engine_lvl,
        comp_lvl: newShip.comp_lvl,
        sensor_lvl: newShip.sensor_lvl,
        cargo: newShip.cargo,
        fighters: newShip.fighters,
        torpedoes: newShip.torpedoes
      },
      inventory: {
        ore: 0,
        organics: 0,
        goods: 0,
        energy: 0
      }
    })
    
  } catch (error) {
    console.error('Error in /api/register:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
