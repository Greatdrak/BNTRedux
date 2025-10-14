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
    
    // Get attacker's current sector
    const { data: attackerPlayerData } = await supabaseAdmin
      .from('players')
      .select('current_sector')
      .eq('id', attackerPlayer.id)
      .single()
    
    if (!attackerPlayerData?.current_sector) {
      return NextResponse.json(
        { error: { code: 'invalid_location', message: 'Player location not found' } },
        { status: 400 }
      )
    }

    // Check sector rules - combat allowed?
    const { data: sectorPermission } = await supabaseAdmin
      .rpc('check_sector_permission', {
        p_sector_id: attackerPlayerData.current_sector,
        p_player_id: attackerPlayer.id,
        p_action: 'attack'
      })
    
    if (sectorPermission && !sectorPermission.allowed) {
      return NextResponse.json(
        { error: { code: sectorPermission.reason || 'sector_rules', message: sectorPermission.message || 'Combat is not allowed in this sector' } },
        { status: 403 }
      )
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
    
    // Simulate combat with strict caps
    const attackerShip: any = Array.isArray(attackerPlayer.ships) ? attackerPlayer.ships[0] : (attackerPlayer as any).ships
    const combatResult = await simulateCombat(attackerShip, targetShip)

    // Persist ship resource losses and apply salvage
    try {
      // Update attacker ship
      const attackerUpdate: any = {
        fighters: combatResult.playerShip.fighters,
        torpedoes: combatResult.playerShip.torpedoes,
        shield: combatResult.playerShip.shield,
        hull: combatResult.playerShip.hull
      }
      
      // Apply salvage if attacker won
      if (combatResult.winner === 'player' && combatResult.salvage) {
        attackerUpdate.credits = (attackerShip.credits || 0) + combatResult.salvage.credits
        attackerUpdate.ore = (attackerShip.ore || 0) + combatResult.salvage.ore
        attackerUpdate.organics = (attackerShip.organics || 0) + combatResult.salvage.organics
        attackerUpdate.goods = (attackerShip.goods || 0) + combatResult.salvage.goods
        attackerUpdate.colonists = (attackerShip.colonists || 0) + combatResult.salvage.colonists
      }
      
      await supabaseAdmin
        .from('ships')
        .update(attackerUpdate)
        .eq('id', attackerShip.id)

      // Update target ship
      const targetUpdate: any = {
        fighters: combatResult.enemyShip.fighters,
        torpedoes: combatResult.enemyShip.torpedoes,
        shield: combatResult.enemyShip.shield,
        hull: combatResult.enemyShip.hull
      }
      
      // Apply salvage if target won
      if (combatResult.winner === 'enemy' && combatResult.salvage) {
        targetUpdate.credits = (targetShip.credits || 0) + combatResult.salvage.credits
        targetUpdate.ore = (targetShip.ore || 0) + combatResult.salvage.ore
        targetUpdate.organics = (targetShip.organics || 0) + combatResult.salvage.organics
        targetUpdate.goods = (targetShip.goods || 0) + combatResult.salvage.goods
        targetUpdate.colonists = (targetShip.colonists || 0) + combatResult.salvage.colonists
      }
      
      await supabaseAdmin
        .from('ships')
        .update(targetUpdate)
        .eq('id', targetShip.id)

      // Handle destruction/respawn: loser gets reset to sector 0 with level 1
      const loser = combatResult.winner === 'player' ? targetShip : (combatResult.winner === 'enemy' ? attackerShip : null)
      const loserPlayerId = combatResult.winner === 'player' ? (targetShip as any).players?.id : (combatResult.winner === 'enemy' ? attackerPlayer.id : null)
      if (loser && loserPlayerId && (combatResult.winner === 'player' || combatResult.winner === 'enemy')) {
        // Find sector 0 in this universe
        const loserUniverseId = combatResult.winner === 'player' ? (targetShip as any).players?.universe_id : attackerPlayer.universe_id
        const { data: sec0 } = await supabaseAdmin
          .from('sectors')
          .select('id')
          .eq('number', 0)
          .eq('universe_id', loserUniverseId)
          .single()

        // Reset ship to level 1 base stats
        const shipIdToReset = combatResult.winner === 'player' ? targetShip.id : attackerShip.id
        await supabaseAdmin
          .from('ships')
          .update({
            hull_lvl: 1,
            shield_lvl: 1,
            engine_lvl: 1,
            comp_lvl: 1,
            sensor_lvl: 1,
            power_lvl: 1,
            beam_lvl: 1,
            torp_launcher_lvl: 1,
            cloak_lvl: 1,
            hull: 100,
            hull_max: 100,
            armor: 100,
            armor_max: 100,
            fighters: 0,
            torpedoes: 0,
            energy: 0,
            cargo: 0
          })
          .eq('id', shipIdToReset)

        // Move player to sector 0
        if (sec0?.id) {
          await supabaseAdmin
            .from('players')
            .update({ current_sector: sec0.id })
            .eq('id', loserPlayerId)
        }
      }
    } catch (persistErr) {
      console.error('Error persisting combat results:', persistErr)
    }

    // Logs: attacker and defender
    try {
      const winnerText = combatResult.winner === 'player' ? 'win' : (combatResult.winner === 'enemy' ? 'loss' : 'draw')
      
      // Build attacker message with credits gained if they won
      let attackerMessage = `You attacked ${ (targetShip as any).players?.handle || 'a ship' } - result: ${winnerText}.`
      if (combatResult.winner === 'player' && combatResult.salvage?.credits && combatResult.salvage.credits > 0) {
        attackerMessage += ` Gained ${combatResult.salvage.credits} credits in salvage.`
      }
      
      await supabaseAdmin.from('player_logs').insert([
        { player_id: attackerPlayer.id, kind: 'ship_attacked', ref_id: targetShip.id, message: attackerMessage },
        { player_id: (targetShip as any).players?.id, kind: 'ship_attacked', ref_id: attackerPlayer.ships?.[0]?.id, message: `Your ship was attacked by ${ (attackerPlayer as any).handle || 'a player' } - result: ${winnerText === 'win' ? 'loss' : (winnerText === 'loss' ? 'win' : 'draw') }.` },
      ])
    } catch {}

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

// Ship vs Ship combat with strict caps (single-round resolution)
async function simulateCombat(playerShip: any, enemyShip: any) {
  const combatSteps: any[] = []
  let stepId = 1
  
  // Initialize combat state
  let a_fighters = playerShip.fighters || 0
  const a_torp_stock = playerShip.torpedoes || 0
  const a_torp_cap = (playerShip.torp_launcher_lvl || 0) * 100
  const a_torp_usable = Math.min(a_torp_stock, a_torp_cap)
  let a_beams = calculateBeamPower(playerShip)
  let a_shields = calculateShieldPower(playerShip)
  let a_hull = playerShip.hull || 100  // Use hull, not armor
  let a_engines = playerShip.engine_lvl || 1
  let a_sensors = playerShip.sensor_lvl || 1
  
  let d_fighters = enemyShip.fighters || 0
  const d_torp_stock = enemyShip.torpedoes || 0
  const d_torp_cap = (enemyShip.torp_launcher_lvl || 0) * 100
  const d_torp_usable = Math.min(d_torp_stock, d_torp_cap)
  let d_beams = calculateBeamPower(enemyShip)
  let d_shields = calculateShieldPower(enemyShip)
  let d_hull = enemyShip.hull || 100  // Use hull, not armor
  let d_engines = enemyShip.engine_lvl || 1
  let d_cloak = enemyShip.cloak_lvl || 1
  
  // Torpedo damage = usable torps × 10
  let a_torp_damage = a_torp_usable * 10
  let d_torp_damage = d_torp_usable * 10
  
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
      winner: 'draw',
      combat_steps: combatSteps,
      playerShip: getShipState(playerShip, a_fighters, Math.max(0, (playerShip.torpedoes || 0) - a_torp_usable), a_beams, a_shields, a_hull),
      enemyShip: getShipState(enemyShip, d_fighters, Math.max(0, (enemyShip.torpedoes || 0) - d_torp_usable), d_beams, d_shields, d_hull),
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
      winner: 'draw',
      combat_steps: combatSteps,
      playerShip: getShipState(playerShip, a_fighters, Math.max(0, (playerShip.torpedoes || 0) - a_torp_usable), a_beams, a_shields, a_hull),
      enemyShip: getShipState(enemyShip, d_fighters, Math.max(0, (enemyShip.torpedoes || 0) - d_torp_usable), d_beams, d_shields, d_hull),
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
      playerShip: getShipState(playerShip, a_fighters, Math.max(0, (playerShip.torpedoes || 0) - a_torp_usable), a_beams, a_shields, a_hull),
      enemyShip: getShipState(enemyShip, d_fighters, Math.max(0, (enemyShip.torpedoes || 0) - d_torp_usable), d_beams, d_shields, d_hull),
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
  
  // Step 6: Beam Exchange vs Hull
  if (a_beams > 0 || d_beams > 0) {
    // Attacker beams vs defender hull
    if (a_beams > 0) {
      const hullDestroyed = a_beams // Beams can damage hull even if it's 0
      d_hull -= hullDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Beam Attack vs Hull',
        description: `Your beams destroyed ${hullDestroyed} enemy hull points`,
        damage: hullDestroyed,
        target: 'hull'
      })
    }
    
    // Defender beams vs attacker hull
    if (d_beams > 0) {
      const hullDestroyed = d_beams // Beams can damage hull even if it's 0
      a_hull -= hullDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Beam Attack vs Hull',
        description: `Enemy beams destroyed ${hullDestroyed} of your hull points`,
        damage: hullDestroyed,
        target: 'hull'
      })
    }
  }
  
  // Step 7: Torpedo Exchange (strict caps)
  let a_torp_damage2 = a_torp_usable * 10
  let d_torp_damage2 = d_torp_usable * 10

  // Attacker torpedoes vs defender fighters
  if (a_torp_damage2 > 0 && d_fighters > 0) {
    const fightersDestroyed = Math.min(a_torp_damage2, Math.floor(d_fighters / 2))
    d_fighters -= fightersDestroyed
    const remainingDamage = a_torp_damage2 - fightersDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'player',
      action: 'Torpedo Attack vs Fighters',
      description: `Your torpedoes destroyed ${fightersDestroyed} enemy fighters`,
      damage: fightersDestroyed,
      target: 'fighters'
    })
    
    // Remaining torpedo damage vs hull
    if (remainingDamage > 0) {
      const hullDestroyed = remainingDamage // Torpedoes can damage hull even if it's 0
      d_hull -= hullDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'player',
        action: 'Torpedo Attack vs Hull',
        description: `Your torpedoes destroyed ${hullDestroyed} enemy hull points`,
        damage: hullDestroyed,
        target: 'hull'
      })
    }
  }
  
  // Defender torpedoes vs attacker fighters
  if (d_torp_damage2 > 0 && a_fighters > 0) {
    const fightersDestroyed = Math.min(d_torp_damage2, Math.floor(a_fighters / 2))
    a_fighters -= fightersDestroyed
    const remainingDamage = d_torp_damage2 - fightersDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'enemy',
      action: 'Torpedo Attack vs Fighters',
      description: `Enemy torpedoes destroyed ${fightersDestroyed} of your fighters`,
      damage: fightersDestroyed,
      target: 'fighters'
    })
    
    // Remaining torpedo damage vs hull
    if (remainingDamage > 0) {
      const hullDestroyed = remainingDamage // Torpedoes can damage hull even if it's 0
      a_hull -= hullDestroyed
      
      combatSteps.push({
        id: stepId++,
        type: 'damage',
        attacker: 'enemy',
        action: 'Torpedo Attack vs Hull',
        description: `Enemy torpedoes destroyed ${hullDestroyed} of your hull points`,
        damage: hullDestroyed,
        target: 'hull'
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
  
  // Step 9: Remaining fighters attack hull
  if (a_fighters > 0) {
    const hullDestroyed = a_fighters // Fighters can damage hull even if it's 0
    d_hull -= hullDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'player',
      action: 'Fighter Attack vs Hull',
      description: `Your remaining ${a_fighters} fighters destroyed ${hullDestroyed} enemy hull points`,
      damage: hullDestroyed,
      target: 'hull'
    })
  }
  
  if (d_fighters > 0) {
    const hullDestroyed = d_fighters // Fighters can damage hull even if it's 0
    a_hull -= hullDestroyed
    
    combatSteps.push({
      id: stepId++,
      type: 'damage',
      attacker: 'enemy',
      action: 'Fighter Attack vs Hull',
      description: `Enemy's remaining ${d_fighters} fighters destroyed ${hullDestroyed} of your hull points`,
      damage: hullDestroyed,
      target: 'hull'
    })
  }
  
  // Step 10: Determine winner
  let winner: 'player' | 'enemy' | 'draw' = 'draw'
  
  if (a_hull <= 0 && d_hull <= 0) {
    winner = 'draw'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'player',
      action: 'Mutual Destruction',
      description: 'Both ships destroyed each other!'
    })
  } else if (a_hull <= 0) {
    winner = 'enemy'
    combatSteps.push({
      id: stepId++,
      type: 'result',
      attacker: 'enemy',
      action: 'Victory',
      description: 'Your ship has been destroyed!'
    })
  } else if (d_hull <= 0) {
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
  
  // Calculate salvage: 50% of credits + 25% of ship's net worth
  const salvage = winner === 'player' ? (() => {
    // 50% of enemy credits
    const creditSalvage = Math.floor((enemyShip.credits || 0) * 0.5)
    
    // Calculate ship's net worth based on tech levels
    const hullValue = (enemyShip.hull_lvl || 1) * 10000
    const shieldValue = (enemyShip.shield_lvl || 1) * 8000
    const engineValue = (enemyShip.engine_lvl || 1) * 6000
    const compValue = (enemyShip.comp_lvl || 1) * 5000
    const sensorValue = (enemyShip.sensor_lvl || 1) * 4000
    const powerValue = (enemyShip.power_lvl || 1) * 7000
    const beamValue = (enemyShip.beam_lvl || 1) * 9000
    const torpValue = (enemyShip.torp_launcher_lvl || 1) * 8000
    const cloakValue = (enemyShip.cloak_lvl || 1) * 3000
    
    const shipNetWorth = hullValue + shieldValue + engineValue + compValue + 
                        sensorValue + powerValue + beamValue + torpValue + cloakValue
    
    // 25% of ship's net worth as credits
    const shipValueSalvage = Math.floor(shipNetWorth * 0.25)
    
    return {
      credits: creditSalvage + shipValueSalvage,
      ore: Math.floor((enemyShip.ore || 0) * 0.1),
      organics: Math.floor((enemyShip.organics || 0) * 0.1),
      goods: Math.floor((enemyShip.goods || 0) * 0.1),
      colonists: Math.floor((enemyShip.colonists || 0) * 0.1),
      shipValueSalvage: shipValueSalvage,
      creditSalvage: creditSalvage
    }
  })() : null
  
  return {
    winner,
    combat_steps: combatSteps,
    playerShip: getShipState(playerShip, a_fighters, Math.max(0, (playerShip.torpedoes || 0) - a_torp_usable), a_beams, a_shields, a_hull),
    enemyShip: getShipState(enemyShip, d_fighters, Math.max(0, (enemyShip.torpedoes || 0) - d_torp_usable), d_beams, d_shields, d_hull),
    salvage,
    turnsUsed: 1
  }
}

// Helper function to calculate beam power based on energy and beam level
function calculateBeamPower(ship: any): number {
  const beamLevel = ship.beam_lvl || 0
  const energy = ship.energy || 0
  
  // Beams require energy - if energy is limited, beams are limited
  const maxBeams = beamLevel * 1000 // Example: level 5 = 5000 beams
  return Math.min(maxBeams, energy)
}

// Helper function to calculate shield power based on energy and shield level
function calculateShieldPower(ship: any): number {
  const shieldLevel = ship.shield_lvl || 0
  const energy = ship.energy || 0
  
  // Shields use energy after beams
  const beamPower = calculateBeamPower(ship)
  const remainingEnergy = Math.max(0, energy - beamPower)
  const maxShields = shieldLevel * 1000 // Example: level 5 = 5000 shields
  
  return Math.min(maxShields, remainingEnergy)
}

// Helper function to get final ship state
function getShipState(originalShip: any, fighters: number, torpedoes: number, beams: number, shields: number, hull: number) {
  return {
    hull: hull,
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
