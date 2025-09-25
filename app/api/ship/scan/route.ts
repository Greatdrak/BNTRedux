import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(
        { error: { code: authResult.error.code, message: authResult.error.message } },
        { status: 401 }
      )
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { target_ship_id, universe_id } = body
    
    if (!target_ship_id || !universe_id) {
      return NextResponse.json(
        { error: { code: 'missing_parameters', message: 'Target ship ID and universe ID are required' } },
        { status: 400 }
      )
    }
    
    // Get attacker (scanner) data
    const { data: attackerPlayer, error: attackerError } = await supabaseAdmin
      .from('players')
      .select(`
        id,
        turns,
        universe_id,
        ships!inner (
          id,
          sensor_lvl,
          credits
        )
      `)
      .eq('user_id', userId)
      .eq('universe_id', universe_id)
      .single()
    
    if (attackerError || !attackerPlayer) {
      return NextResponse.json(
        { error: { code: 'player_not_found', message: 'Player not found' } },
        { status: 404 }
      )
    }
    
    // Check if attacker has enough turns
    if (attackerPlayer.turns < 1) {
      return NextResponse.json(
        { error: { code: 'insufficient_turns', message: 'Insufficient turns to perform scan' } },
        { status: 400 }
      )
    }
    
    // Get target ship data
    const { data: targetShip, error: targetError } = await supabaseAdmin
      .from('ships')
      .select(`
        id,
        name,
        hull,
        hull_max,
        shield,
        shield_max,
        fighters,
        torpedoes,
        energy,
        energy_max,
        engine_lvl,
        comp_lvl,
        sensor_lvl,
        power_lvl,
        beam_lvl,
        torp_launcher_lvl,
        cloak_lvl,
        armor,
        armor_lvl,
        credits,
        ore,
        organics,
        goods,
        colonists,
        players!inner (
          handle,
          universe_id
        )
      `)
      .eq('id', target_ship_id)
      .eq('players.universe_id', universe_id)
      .single()
    
    if (targetError || !targetShip) {
      return NextResponse.json(
        { error: { code: 'target_not_found', message: 'Target ship not found' } },
        { status: 404 }
      )
    }
    
    // Check if target is in same sector (basic validation)
    // TODO: Add sector validation when we have sector data
    
    // Calculate scan success chance
    const attackerSensorLevel = attackerPlayer.ships?.[0]?.sensor_lvl || 1
    const targetCloakLevel = targetShip.cloak_lvl || 0
    
    // Determine scan result with automatic success for 5+ level advantage
    let scanType: 'failure' | 'partial' | 'full' = 'failure'
    let totalChance: number = 0
    
    // Automatic full success if sensor is 5+ levels higher than cloak
    if (attackerSensorLevel >= targetCloakLevel + 5) {
      scanType = 'full'
      totalChance = 100 // Set to 100 for automatic success
    } else {
      // Normal scan formula: sensor_lvl * 20 - cloak_lvl * 15 + random(1-30)
      const baseChance = (attackerSensorLevel * 20) - (targetCloakLevel * 15)
      const randomFactor = Math.floor(Math.random() * 30) + 1
      totalChance = baseChance + randomFactor
      
      if (totalChance >= 40) {
        scanType = 'full' // 100% data revealed
      } else if (totalChance >= 15) {
        scanType = 'partial' // 60% data revealed
      } else {
        scanType = 'failure' // 0% data revealed
      }
    }
    
    // Deduct turn from attacker
    const { error: turnError } = await supabaseAdmin
      .from('players')
      .update({ turns: attackerPlayer.turns - 1 })
      .eq('id', attackerPlayer.id)
    
    if (turnError) {
      console.error('Error deducting turn:', turnError)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to deduct turn' } },
        { status: 500 }
      )
    }
    
    // Prepare scan result data
    const scanResult = {
      success: true,
      scan_type: scanType,
      scan_chance: totalChance,
      attacker_sensor_level: attackerSensorLevel,
      target_cloak_level: targetCloakLevel,
      scanned_data: {
        id: targetShip.id,
        name: targetShip.name,
        player_handle: targetShip.players?.[0]?.handle,
        hull: targetShip.hull,
        hull_max: targetShip.hull_max,
        shield: targetShip.shield,
        shield_max: targetShip.shield_max,
        fighters: targetShip.fighters,
        torpedoes: targetShip.torpedoes,
        energy: targetShip.energy,
        energy_max: targetShip.energy_max,
        engine_lvl: targetShip.engine_lvl,
        comp_lvl: targetShip.comp_lvl,
        sensor_lvl: targetShip.sensor_lvl,
        power_lvl: targetShip.power_lvl,
        beam_lvl: targetShip.beam_lvl,
        torp_launcher_lvl: targetShip.torp_launcher_lvl,
        cloak_lvl: targetShip.cloak_lvl,
        armor: targetShip.armor,
        armor_lvl: targetShip.armor_lvl,
        credits: targetShip.credits,
        ore: targetShip.ore,
        organics: targetShip.organics,
        goods: targetShip.goods,
        colonists: targetShip.colonists
      }
    }
    
    return NextResponse.json(scanResult)
    
  } catch (error) {
    console.error('Error in /api/ship/scan:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
