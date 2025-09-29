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
    
    // Get attacker (player) data
    const { data: attackerPlayer, error: attackerError } = await supabaseAdmin
      .from('players')
      .select(`
        id,
        turns,
        universe_id,
        ships!inner (
          id,
          name,
          hull,
          hull_max,
          hull_lvl,
          shield,
          shield_lvl,
          engine_lvl,
          comp_lvl,
          sensor_lvl,
          power_lvl,
          beam_lvl,
          torp_launcher_lvl,
          cloak_lvl,
          armor,
          armor_max,
          cargo,
          fighters,
          torpedoes,
          colonists,
          energy,
          energy_max,
          credits,
          ore,
          organics,
          goods
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
        { error: { code: 'insufficient_turns', message: 'Insufficient turns to initiate combat' } },
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
        hull_lvl,
        shield,
        shield_lvl,
        engine_lvl,
        comp_lvl,
        sensor_lvl,
        power_lvl,
        beam_lvl,
        torp_launcher_lvl,
        cloak_lvl,
        armor,
        armor_max,
        cargo,
        fighters,
        torpedoes,
        colonists,
        energy,
        energy_max,
        credits,
        ore,
        organics,
        goods,
        players!inner (
          id,
          handle,
          universe_id,
          is_ai
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
    // TODO: Add proper sector validation when we have sector data
    
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
    
    // Simulate combat (placeholder for now)
    const combatResult = await simulateCombat(attackerPlayer.ships, targetShip)
    
    return NextResponse.json({
      success: true,
      combat_result: combatResult,
      turns_remaining: attackerPlayer.turns - 1
    })
    
  } catch (error) {
    console.error('Error in /api/combat/initiate:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}

// BNT Combat Simulation based on original game FAQ
async function simulateCombat(playerShip: any, enemyShip: any) {
  const combatSteps: any[] = []
  let stepId = 1
  
  // Initialize combat state
  let a_fighters = playerShip.fighters || 0
  let a_torpedoes = playerShip.torpedoes || 0
  let a_beams = calculateBeamPower(playerShip)
  let a_shields = calculateShieldPower(playerShip)
  let a_armor = playerShip.armor || 0
  let a_engines = playerShip.engine_lvl || 1
  let a_sensors = playerShip.sensor_lvl || 1
  
  let d_fighters = enemyShip.fighters || 0
  let d_torpedoes = enemyShip.torpedoes || 0
  let d_beams = calculateBeamPower(enemyShip)
  let d_shields = calculateShieldPower(enemyShip)
  let d_armor = enemyShip.armor || 0
  let d_engines = enemyShip.engine_lvl || 1
  let d_cloak = enemyShip.cloak_lvl || 1
  
  // Store original values for torpedo calculation (2% of max)
  const a_original_torpedoes = a_torpedoes
  const d_original_torpedoes = d_torpedoes
  
  // Step 1: Engine Check (Attacker vs Defender)
  const engineSuccess = (10 - d_engines + a_engines) * 5
  const engineRoll = Math.floor(Math.random() * 100) + 1
  
  if (engineRoll > engineSuccess) {
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'enemy',
      action: 'Target Outmaneuvered',
      description: `Engine check failed! (${engineSuccess}% chance, rolled ${engineRoll})`
    })
    
    return {
      winner: 'enemy',
      combat_steps: combatSteps,
      playerShip: getShipState(playerShip, a_fighters, a_torpedoes, a_beams, a_shields, a_armor),
      enemyShip: getShipState(enemyShip, d_fighters, d_torpedoes, d_beams, d_shields, d_armor),
      salvage: null,
      turnsUsed: 1
    }
  }
  
  combatSteps.push({
    id: stepId++,
    type: 'attack',
    attacker: 'player',
    action: 'Engine Check Passed',
    description: `Successfully closed distance! (${engineSuccess}% chance, rolled ${engineRoll})`
  })
  
  // Step 2: Sensor vs Cloak Check
  const sensorSuccess = (10 - d_cloak + a_sensors) * 5
  const sensorRoll = Math.floor(Math.random() * 100) + 1
  
  if (sensorRoll > sensorSuccess) {
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'enemy',
      action: 'Unable to Get Lock',
      description: `Sensor check failed! (${sensorSuccess}% chance, rolled ${sensorRoll})`
    })
    
    return {
      winner: 'enemy',
      combat_steps: combatSteps,
      playerShip: getShipState(playerShip, a_fighters, a_torpedoes, a_beams, a_shields, a_armor),
      enemyShip: getShipState(enemyShip, d_fighters, d_torpedoes, d_beams, d_shields, d_armor),
      salvage: null,
      turnsUsed: 1
    }
  }
  
  combatSteps.push({
    id: stepId++,
    type: 'attack',
    attacker: 'player',
    action: 'Target Lock Acquired',
    description: `Sensors locked onto target! (${sensorSuccess}% chance, rolled ${sensorRoll})`
  })
  
  // Step 3: Check for Emergency Warp Device
  if (enemyShip.device_emergency_warp) {
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'enemy',
      action: 'Emergency Warp',
      description: 'Enemy activated emergency warp device and escaped!'
    })
    
    return {
      winner: 'enemy',
      combat_steps: combatSteps,
      playerShip: getShipState(playerShip, a_fighters, a_torpedoes, a_beams, a_shields, a_armor),
      enemyShip: getShipState(enemyShip, d_fighters, d_torpedoes, d_beams, d_shields, d_armor),
      salvage: null,
      turnsUsed: 1
    }
  }
  
  // Step 4: Beam Exchange vs Fighters
  if (a_beams > 0 || d_beams > 0) {
    // Attacker beams vs defender fighters
    if (a_beams > 0 && d_fighters > 0) {
      const fightersDestroyed = Math.min(a_beams, Math.floor(d_fighters / 2))
      a_beams -= fightersDestroyed
      d_fighters -= fightersDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Beam Attack vs Fighters',
        description: `Your beams destroyed ${fightersDestroyed} enemy fighters`,
        damage: fightersDestroyed,
        target: 'fighters'
      })
    }
    
    // Defender beams vs attacker fighters
    if (d_beams > 0 && a_fighters > 0) {
      const fightersDestroyed = Math.min(d_beams, Math.floor(a_fighters / 2))
      d_beams -= fightersDestroyed
      a_fighters -= fightersDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Beam Attack vs Fighters',
        description: `Enemy beams destroyed ${fightersDestroyed} of your fighters`,
        damage: fightersDestroyed,
        target: 'fighters'
      })
    }
  }
  
  // Step 5: Beam Exchange vs Shields
  if (a_beams > 0 || d_beams > 0) {
    // Attacker beams vs defender shields
    if (a_beams > 0 && d_shields > 0) {
      const shieldsDestroyed = Math.min(a_beams, d_shields)
      a_beams -= shieldsDestroyed
      d_shields -= shieldsDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Beam Attack vs Shields',
        description: `Your beams destroyed ${shieldsDestroyed} enemy shield points`,
        damage: shieldsDestroyed,
        target: 'shield'
      })
    }
    
    // Defender beams vs attacker shields
    if (d_beams > 0 && a_shields > 0) {
      const shieldsDestroyed = Math.min(d_beams, a_shields)
      d_beams -= shieldsDestroyed
      a_shields -= shieldsDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Beam Attack vs Shields',
        description: `Enemy beams destroyed ${shieldsDestroyed} of your shield points`,
        damage: shieldsDestroyed,
        target: 'shield'
      })
    }
  }
  
  // Step 6: Beam Exchange vs Armor
  if (a_beams > 0 || d_beams > 0) {
    // Attacker beams vs defender armor
    if (a_beams > 0) {
      const armorDestroyed = a_beams // Beams can damage armor even if it's 0
      d_armor -= armorDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Beam Attack vs Armor',
        description: `Your beams destroyed ${armorDestroyed} enemy armor points`,
        damage: armorDestroyed,
        target: 'armor'
      })
    }
    
    // Defender beams vs attacker armor
    if (d_beams > 0) {
      const armorDestroyed = d_beams // Beams can damage armor even if it's 0
      a_armor -= armorDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Beam Attack vs Armor',
        description: `Enemy beams destroyed ${armorDestroyed} of your armor points`,
        damage: armorDestroyed,
        target: 'armor'
      })
    }
  }
  
  // Step 7: Torpedo Exchange (2% of max torpedoes)
  const a_torp_damage = Math.floor(a_original_torpedoes * 0.02) * 10 // 10 damage per torp
  const d_torp_damage = Math.floor(d_original_torpedoes * 0.02) * 10
  
  // Attacker torpedoes vs defender fighters
  if (a_torp_damage > 0 && d_fighters > 0) {
    const fightersDestroyed = Math.min(a_torp_damage, Math.floor(d_fighters / 2))
    d_fighters -= fightersDestroyed
    const remainingDamage = a_torp_damage - fightersDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'player',
      action: 'Torpedo Attack vs Fighters',
      description: `Your torpedoes destroyed ${fightersDestroyed} enemy fighters`,
      damage: fightersDestroyed,
      target: 'fighters'
    })
    
    // Remaining torpedo damage vs armor
    if (remainingDamage > 0) {
      const armorDestroyed = remainingDamage // Torpedoes can damage armor even if it's 0
      d_armor -= armorDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Torpedo Attack vs Armor',
        description: `Your torpedoes destroyed ${armorDestroyed} enemy armor points`,
        damage: armorDestroyed,
        target: 'armor'
      })
    }
  }
  
  // Defender torpedoes vs attacker fighters
  if (d_torp_damage > 0 && a_fighters > 0) {
    const fightersDestroyed = Math.min(d_torp_damage, Math.floor(a_fighters / 2))
    a_fighters -= fightersDestroyed
    const remainingDamage = d_torp_damage - fightersDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'enemy',
      action: 'Torpedo Attack vs Fighters',
      description: `Enemy torpedoes destroyed ${fightersDestroyed} of your fighters`,
      damage: fightersDestroyed,
      target: 'fighters'
    })
    
    // Remaining torpedo damage vs armor
    if (remainingDamage > 0) {
      const armorDestroyed = remainingDamage // Torpedoes can damage armor even if it's 0
      a_armor -= armorDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Torpedo Attack vs Armor',
        description: `Enemy torpedoes destroyed ${armorDestroyed} of your armor points`,
        damage: armorDestroyed,
        target: 'armor'
      })
    }
  }
  
  // Step 8: Fighter Exchange
  const a_fighter_damage = a_fighters
  const d_fighter_damage = d_fighters
  
  // Fighter vs Fighter battle - both sides lose fighters equal to the smaller force
  const fighters_lost = Math.min(a_fighters, d_fighters)
  a_fighters -= fighters_lost
  d_fighters -= fighters_lost
  
  combatSteps.push({
    id: stepId++,
    type: 'damage',
    attacker: 'player',
    action: 'Fighter Exchange',
    description: `Fighter battle: You lost ${fighters_lost} fighters, enemy lost ${fighters_lost} fighters`
  })
  
  // Step 9: Remaining fighters attack armor
  if (a_fighters > 0) {
    const armorDestroyed = a_fighters // Fighters can damage armor even if it's 0
    d_armor -= armorDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'player',
      action: 'Fighter Attack vs Armor',
      description: `Your remaining ${a_fighters} fighters destroyed ${armorDestroyed} enemy armor points`,
      damage: armorDestroyed,
      target: 'armor'
    })
  }
  
  if (d_fighters > 0) {
    const armorDestroyed = d_fighters // Fighters can damage armor even if it's 0
    a_armor -= armorDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'enemy',
      action: 'Fighter Attack vs Armor',
      description: `Enemy's remaining ${d_fighters} fighters destroyed ${armorDestroyed} of your armor points`,
      damage: armorDestroyed,
      target: 'armor'
    })
  }
  
  // Step 10: Determine winner
  let winner: 'player' | 'enemy' | 'draw' = 'draw'
  
  if (a_armor <= 0 && d_armor <= 0) {
    winner = 'draw'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'player',
      action: 'Mutual Destruction',
      description: 'Both ships destroyed each other!'
    })
  } else if (a_armor <= 0) {
    winner = 'enemy'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'enemy',
      action: 'Victory',
      description: 'Your ship has been destroyed!'
    })
  } else if (d_armor <= 0) {
    winner = 'player'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'player',
      action: 'Victory',
      description: 'Enemy ship destroyed!'
    })
  } else {
    winner = 'draw'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'player',
      action: 'Stalemate',
      description: 'Both ships survived the battle'
    })
  }
  
  // Calculate salvage (placeholder - should be based on enemy ship value)
  const salvage = winner === 'player' ? {
    credits: Math.floor((enemyShip.credits || 0) * 0.1),
    ore: Math.floor((enemyShip.ore || 0) * 0.1),
    organics: Math.floor((enemyShip.organics || 0) * 0.1),
    goods: Math.floor((enemyShip.goods || 0) * 0.1),
    colonists: Math.floor((enemyShip.colonists || 0) * 0.1)
  } : null
  
  return {
    winner,
    combat_steps: combatSteps,
    playerShip: getShipState(playerShip, a_fighters, a_torpedoes, a_beams, a_shields, a_armor),
    enemyShip: getShipState(enemyShip, d_fighters, d_torpedoes, d_beams, d_shields, d_armor),
    salvage,
    turnsUsed: 1
  }
}

// Helper function to calculate beam power based on energy and beam level
function calculateBeamPower(ship: any): number {
  const beamLevel = ship.beam_lvl || 0
  const energy = ship.energy || 0
  const powerLevel = ship.power_lvl || 0
  
  // Beams require energy - if energy is limited, beams are limited
  const maxBeams = beamLevel * 1000 // Example: level 5 = 5000 beams
  return Math.min(maxBeams, energy)
}

// Helper function to calculate shield power based on energy and shield level
function calculateShieldPower(ship: any): number {
  const shieldLevel = ship.shield_lvl || 0
  const energy = ship.energy || 0
  const powerLevel = ship.power_lvl || 0
  
  // Shields use energy after beams
  const beamPower = calculateBeamPower(ship)
  const remainingEnergy = Math.max(0, energy - beamPower)
  const maxShields = shieldLevel * 1000 // Example: level 5 = 5000 shields
  
  return Math.min(maxShields, remainingEnergy)
}

// Helper function to get final ship state
function getShipState(originalShip: any, fighters: number, torpedoes: number, beams: number, shields: number, armor: number) {
  return {
    hull: originalShip.hull || 100,
    hull_max: originalShip.hull_max || 100,
    shield: shields,
    fighters: fighters,
    torpedoes: torpedoes,
    energy: originalShip.energy || 100,
    energy_max: originalShip.energy_max || 100,
    credits: originalShip.credits || 0,
    ore: originalShip.ore || 0,
    organics: originalShip.organics || 0,
    goods: originalShip.goods || 0,
    colonists: originalShip.colonists || 0
  }
}
