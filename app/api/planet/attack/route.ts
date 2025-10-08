import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// POST /api/planet/attack
// Attacker risks their ship against a defended planet
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const attackerUserId = authResult.userId
    const body = await request.json()
    const { planet_id } = body

    if (!planet_id) {
      return NextResponse.json({ error: 'planet_id is required' }, { status: 400 })
    }

    // Fetch target planet and its owner + sector
    const { data: planet, error: planetErr } = await supabaseAdmin
      .from('planets')
      .select(`
        id, name, sector_id, owner_player_id,
        ore, organics, goods, energy,
        fighters, torpedoes, shields,
        base_built
      `)
      .eq('id', planet_id)
      .single()

    if (planetErr || !planet) {
      return NextResponse.json({ error: 'Planet not found' }, { status: 404 })
    }

    if (!planet.owner_player_id) {
      return NextResponse.json({ error: 'Planet is unowned; use claim instead' }, { status: 400 })
    }

    // Determine universe from planet's sector
    const { data: sector, error: sectorErr } = await supabaseAdmin
      .from('sectors')
      .select('id, universe_id')
      .eq('id', planet.sector_id)
      .single()

    if (sectorErr || !sector) {
      return NextResponse.json({ error: 'Sector not found for planet' }, { status: 404 })
    }

    // Fetch attacker player and ship in same universe
    const { data: attackerPlayer, error: attackerErr } = await supabaseAdmin
      .from('players')
      .select(`
        id, turns, universe_id, current_sector,
        ships!inner (
          id, name,
          hull, hull_max, hull_lvl,
          shield, shield_lvl,
          engine_lvl, comp_lvl, sensor_lvl, power_lvl,
          beam_lvl, torp_launcher_lvl, cloak_lvl,
          armor, armor_max,
          cargo, fighters, torpedoes, colonists,
          energy, energy_max,
          credits, ore, organics, goods
        )
      `)
      .eq('user_id', attackerUserId)
      .eq('universe_id', sector.universe_id)
      .single()

    if (attackerErr || !attackerPlayer) {
      return NextResponse.json({ error: 'Attacking player not found' }, { status: 404 })
    }

    if ((attackerPlayer.turns || 0) < 1) {
      return NextResponse.json({ error: 'Insufficient turns' }, { status: 400 })
    }

    // Prevent attacking your own planet
    if (planet.owner_player_id === attackerPlayer.id) {
      return NextResponse.json({ error: 'Cannot attack your own planet' }, { status: 400 })
    }

    // Ensure attacker is in same sector as planet
    if (attackerPlayer.current_sector !== planet.sector_id) {
      return NextResponse.json({ error: 'You must be in the same sector to attack this planet' }, { status: 400 })
    }

    // Fetch defender owner ship (planet draws attack power from owner ship)
    const { data: defenderShip, error: defShipErr } = await supabaseAdmin
      .from('ships')
      .select(`
        id, name, player_id,
        hull_lvl, shield_lvl, engine_lvl, comp_lvl, sensor_lvl, power_lvl,
        beam_lvl, torp_launcher_lvl, cloak_lvl,
        fighters, torpedoes, energy, energy_max,
        armor, armor_max
      `)
      .eq('player_id', planet.owner_player_id)
      .single()

    if (defShipErr || !defenderShip) {
      return NextResponse.json({ error: 'Planet owner ship not found' }, { status: 404 })
    }

    // Deduct 1 turn up-front
    const { error: turnErr } = await supabaseAdmin
      .from('players')
      .update({ turns: (attackerPlayer.turns || 0) - 1 })
      .eq('id', attackerPlayer.id)

    if (turnErr) {
      return NextResponse.json({ error: 'Failed to deduct turn' }, { status: 500 })
    }

    // Compute combat pools
    // Planet torp/beam/shield capacity is limited by owner's ship tech levels
    const torpCapacity = Math.max(0, (defenderShip.torp_launcher_lvl || 0) * 100) // planet torp capacity derived from owner ship
    const beamCapacity = Math.max(0, (defenderShip.beam_lvl || 0) * 1000) // energy usable for beams
    const shieldCapacity = Math.max(0, (defenderShip.shield_lvl || 0) * 1000) // energy usable for shields

    // Planet resources available
    let planetFighters = planet.fighters || 0
    const planetTorpedoStock = planet.torpedoes || 0
    let planetEnergy = planet.energy || 0

    // Apply base bonus (+1 tech) if base built
    const techBonus = planet.base_built ? 1 : 0
    const effectiveBeamCap = Math.max(0, ((defenderShip.beam_lvl || 0) + techBonus) * 1000)
    const effectiveShieldCap = Math.max(0, ((defenderShip.shield_lvl || 0) + techBonus) * 1000)
    const effectiveTorpCap = Math.max(0, ((defenderShip.torp_launcher_lvl || 0) + techBonus) * 100)
    const planetTorpedoCap = Math.min(planetTorpedoStock, effectiveTorpCap)

    // Energy distribution: beams draw first up to cap, then shields with remaining energy up to cap
    const beamEnergy = Math.min(effectiveBeamCap, planetEnergy)
    const remainingEnergyAfterBeams = Math.max(0, planetEnergy - beamEnergy)
    const shieldEnergy = Math.min(effectiveShieldCap, remainingEnergyAfterBeams)

    // Attacker ship pools
    const attackerShip: any = Array.isArray(attackerPlayer.ships) ? attackerPlayer.ships[0] : (attackerPlayer as any).ships
    let a_fighters = attackerShip?.fighters || 0
    const a_torp_stock = attackerShip?.torpedoes || 0
    const a_torp_cap = Math.max(0, (attackerShip?.torp_launcher_lvl || 0) * 100)
    const a_torps_usable = Math.min(a_torp_stock, a_torp_cap)
    let a_energy = attackerShip?.energy || 0
    const a_beam_cap = Math.max(0, (attackerShip?.beam_lvl || 0) * 1000)
    const a_beams = Math.min(a_beam_cap, a_energy)
    let a_shields = Math.min(Math.max(0, (attackerShip?.shield_lvl || 0) * 1000), Math.max(0, a_energy - a_beams))
    let a_armor = attackerShip?.armor || 0

    // Defender planet pools (fighters unlimited by comp level per spec)
    let d_fighters = planetFighters
    let d_torps = planetTorpedoCap
    let d_beams = beamEnergy
    let d_shields = shieldEnergy
    let d_armor = (planet.shields || 0) // planets may have a shields stat representing armor-like buffer

    // Track beam energy usage precisely
    let a_beams_remaining = a_beams
    let d_beams_remaining = d_beams
    const d_shields_initial = d_shields

    // Resolve combat - Planet combat order (simplified per BNT classic without owner-on-planet steps)
    const steps: any[] = []
    let stepId = 1

    // Torpedo volley uses up to 2% of max torps from each side (attacker max is their current torps)
    // Strict torpedo usage: each side may use up to their usable torps this round
    // For single-round resolution, consume all usable torps (bounded by stock and level capacity)
    const a_torps_spent = a_torps_usable
    const d_torps_spent = d_torps
    const a_torp_damage = a_torps_spent * 10
    const d_torp_damage = d_torps_spent * 10

    // 1) Your beams vs planet fighters (up to half)
    if (a_beams_remaining > 0 && d_fighters > 0) {
      const destroyed = Math.min(a_beams_remaining, Math.floor(d_fighters / 2))
      a_beams_remaining -= destroyed
      d_fighters -= destroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'player', action: 'Beams vs Fighters', description: `Your beams destroyed ${destroyed} planet fighters`, damage: destroyed, target: 'fighters' })
    }
    // 2) Planet beams vs your fighters (up to half)
    if (d_beams_remaining > 0 && a_fighters > 0) {
      const destroyed = Math.min(d_beams_remaining, Math.floor(a_fighters / 2))
      a_fighters -= destroyed
      d_beams_remaining -= destroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Beams vs Fighters', description: `Planet beams destroyed ${destroyed} of your fighters`, damage: destroyed, target: 'fighters' })
    }

    // Beams vs shields
    // 3) Your beams vs planet shields
    if (a_beams_remaining > 0 && d_shields > 0) {
      const destroyed = Math.min(a_beams_remaining, d_shields)
      a_beams_remaining -= destroyed
      d_shields -= destroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'player', action: 'Beams vs Shields', description: `Your beams removed ${destroyed} shield points`, damage: destroyed, target: 'shield' })
    }
    // 4) Planet beams vs your shields
    if (d_beams_remaining > 0 && a_shields > 0) {
      const destroyed = Math.min(d_beams_remaining, a_shields)
      d_beams_remaining -= destroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Beams vs Shields', description: `Planet beams removed ${destroyed} of your shields`, damage: destroyed, target: 'shield' })
      a_shields -= destroyed
    }

    // Beams vs armor (planet uses shields as buffer-like armor here)
    // 5) Your beams vs owner armor (skipped in our game)
    // 6) Planet beams vs your armor (remaining beams)
    if (d_beams_remaining > 0) {
      a_armor -= d_beams_remaining
      steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Beams vs Armor', description: `Planet beams dealt ${d_beams_remaining} armor damage`, damage: d_beams_remaining, target: 'armor' })
      d_beams_remaining = 0
    }

    // Torpedoes
    // 7) Your torp damage takes out planet fighters (no half cap)
    if (a_torp_damage > 0) {
      const fightersDestroyed = Math.min(d_fighters, a_torp_damage)
      d_fighters -= fightersDestroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'player', action: 'Torpedoes vs Fighters', description: `Your torpedoes destroyed ${fightersDestroyed} planet fighters`, damage: fightersDestroyed, target: 'fighters' })
    }
    // 8) Planet torps take out up to half of your fighters
    if (d_torp_damage > 0 && a_fighters > 0) {
      const fightersDestroyed = Math.min(Math.floor(a_fighters / 2), d_torp_damage)
      a_fighters -= fightersDestroyed
      steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Torpedoes vs Fighters', description: `Planet torpedoes destroyed ${fightersDestroyed} of your fighters`, damage: fightersDestroyed, target: 'fighters' })
    }
    // 9) Planet torp damage goes against your armor (any remaining)
    if (d_torp_damage > 0) {
      const remaining = Math.max(0, d_torp_damage - 0) // already applied to fighters above up to min
      const toArmor = Math.max(0, remaining - 0)
      a_armor -= toArmor
      if (toArmor > 0) steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Torpedoes vs Armor', description: `Planet torpedoes dealt ${toArmor} armor damage`, damage: toArmor, target: 'armor' })
    }

    // Fighters
    // 10) Your fighters vs planet fighters
    if (a_fighters > 0 && d_fighters > 0) {
      const mutual = Math.min(a_fighters, d_fighters)
      a_fighters -= mutual
      d_fighters -= mutual
      steps.push({ id: stepId++, type: 'exchange', attacker: 'player', action: 'Fighters vs Fighters', description: `Both sides lost ${mutual} fighters` })
    }
    // 11) Your fighters vs planet shields
    if (a_fighters > 0 && d_shields > 0) {
      const shieldsRemoved = Math.min(a_fighters, d_shields)
      d_shields -= shieldsRemoved
      steps.push({ id: stepId++, type: 'damage', attacker: 'player', action: 'Fighters vs Shields', description: `Your fighters removed ${shieldsRemoved} shield points`, damage: shieldsRemoved, target: 'shield' })
    }
    // 12) Planet fighters vs your armor
    if (d_fighters > 0) {
      a_armor -= d_fighters
      steps.push({ id: stepId++, type: 'damage', attacker: 'enemy', action: 'Fighters vs Armor', description: `Planet fighters dealt ${d_fighters} armor damage`, damage: d_fighters, target: 'armor' })
    }

    // Outcome
    let winner: 'attacker' | 'defender' | 'draw' = 'draw'
    if (a_armor <= 0) winner = 'defender'
    else if (d_fighters <= 0 && d_shields <= 0) winner = 'attacker'

    // Victory side effects: if attacker wins, planet fighters are fully depleted
    if (winner === 'attacker') {
      d_fighters = 0
    }

    // Persist results: update planet and attacker ship resources/fighters/torps as consumed
    // For simplicity: consume attacker torps by 2% rule; reduce attacker fighters by losses; do not change attacker energy pools here
    const attackerTorpUse = a_torps_spent

    // Update attacker ship
    const shipUpdate = await supabaseAdmin
      .from('ships')
      .update({
        fighters: Math.max(0, a_fighters),
        torpedoes: Math.max(0, (attackerShip?.torpedoes || 0) - attackerTorpUse),
        armor: Math.max(0, a_armor)
      })
      .eq('id', attackerShip?.id)

    if (shipUpdate.error) {
      console.error('Failed to update attacker ship', shipUpdate.error)
    }

    // Update planet resources and defenses
    const planetTorpUse = d_torps_spent
    // Energy actually spent = beam usage + shields actually lost
    const planetBeamUsed = beamEnergy - d_beams_remaining
    const planetShieldsLost = d_shields_initial - d_shields
    const newPlanetEnergy = Math.max(0, planet.energy - Math.max(0, planetBeamUsed + planetShieldsLost))
    const planetUpdate = await supabaseAdmin
      .from('planets')
      .update({
        fighters: Math.max(0, d_fighters),
        torpedoes: Math.max(0, (planet.torpedoes || 0) - planetTorpUse),
        energy: newPlanetEnergy,
        shields: Math.max(0, d_armor)
      })
      .eq('id', planet.id)

    if (planetUpdate.error) {
      console.error('Failed to update planet after attack', planetUpdate.error)
    }

    // Build a combat_result compatible with ship vs ship overlay
    const initialPlanetShields = (planet.shields || 0)
    const combat_result = {
      winner: winner === 'attacker' ? 'player' : winner === 'defender' ? 'enemy' : 'draw',
      playerShip: {
        hull: attackerShip?.hull || 0,
        hull_max: attackerShip?.hull_max || 0,
        shield: Math.max(0, a_shields),
        fighters: Math.max(0, a_fighters),
        torpedoes: Math.max(0, a_torp_stock - attackerTorpUse),
        energy: attackerShip?.energy || 0,
        energy_max: attackerShip?.energy_max || 0,
        credits: attackerShip?.credits || 0,
        ore: attackerShip?.ore || 0,
        organics: attackerShip?.organics || 0,
        goods: attackerShip?.goods || 0,
        colonists: attackerShip?.colonists || 0
      },
      enemyShip: {
        hull: 0,
        hull_max: 0,
        shield: Math.max(0, d_shields),
        fighters: Math.max(0, d_fighters),
        torpedoes: Math.max(0, planetTorpedoStock - planetTorpUse),
        energy: Math.max(0, planet.energy - (beamEnergy + shieldEnergy)),
        energy_max: planet.energy,
        credits: 0,
        ore: planet.ore || 0,
        organics: planet.organics || 0,
        goods: planet.goods || 0,
        colonists: 0
      },
      turnsUsed: 1
    }

    // Logs for planet attack
    try {
      await supabaseAdmin.from('player_logs').insert([
        { player_id: attackerPlayer.id, kind:'planet_attacked', ref_id: planet.id, message:`You attacked a planet in sector ${(await supabaseAdmin.from('sectors').select('number').eq('id', planet.sector_id).single()).data?.number}.` },
        { player_id: planet.owner_player_id, kind:'planet_attacked', ref_id: planet.id, message:`Your planet was attacked.` }
      ])
    } catch {}

    return NextResponse.json({
      success: true,
      combat_result,
      result: {
        winner,
        steps,
        attacker: {
          fighters: Math.max(0, a_fighters),
          torpedoes_spent: attackerTorpUse,
          armor: Math.max(0, a_armor)
        },
        planet: {
          fighters: Math.max(0, d_fighters),
          torpedoes_spent: planetTorpUse,
          energy_spent: beamEnergy + shieldEnergy,
          armor_remaining: Math.max(0, d_armor)
        }
      }
    })
  } catch (error) {
    console.error('Error in /api/planet/attack:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}


