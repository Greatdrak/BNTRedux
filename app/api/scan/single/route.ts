import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId
    const body = await request.json()
    const { sectorNumber, universe_id } = body || {}

    // Get player - filter by universe if provided
    let playerQuery = supabaseAdmin
      .from('players')
      .select('id, universe_id, turns')
      .eq('user_id', userId)
    
    if (universe_id) {
      playerQuery = playerQuery.eq('universe_id', universe_id)
    }
    
    const { data: player } = await playerQuery.single()

    if (!player) return NextResponse.json({ error: { code:'not_found', message:'Player not found' } }, { status:404 })
    if (player.turns < 1) return NextResponse.json({ error: { code:'insufficient_turns', message:'Not enough turns' } }, { status:400 })

    const { data: sector } = await supabaseAdmin
      .from('sectors')
      .select('id, number')
      .eq('universe_id', player.universe_id)
      .eq('number', sectorNumber)
      .single()

    if (!sector) return NextResponse.json({ error: { code:'invalid_sector', message:'Sector not found' } }, { status:400 })

    await supabaseAdmin.from('scans').upsert({ player_id: player.id, sector_id: sector.id, mode: 'single' })
    
    // Track turn spent and decrement turns atomically
    await supabaseAdmin.rpc('track_turn_spent', { 
      p_player_id: player.id, 
      p_turns_spent: 1, 
      p_action_type: 'single_scan' 
    })
    await supabaseAdmin.from('players').update({ turns: player.turns - 1 }).eq('id', player.id)

    const { data: port } = await supabaseAdmin.from('ports').select('kind').eq('sector_id', sector.id).single()
    
    // Get planet count for scanned sector
    const { data: planets } = await supabaseAdmin
      .from('planets')
      .select('id')
      .eq('sector_id', sector.id)
    const planetCount = planets?.length || 0
    
    // Get ship count and ship details for scanned sector
    const { data: ships } = await supabaseAdmin
      .from('ships')
      .select(`
        id,
        name,
        players!inner(
          id,
          handle,
          is_ai,
          current_sector
        )
      `)
      .eq('players.current_sector', sector.id)
      .eq('players.universe_id', player.universe_id)
    
    const shipCount = ships?.length || 0

    // Player logs: notify owners that their ship was scanned
    try {
      const scannedPlayerIds = (ships||[])
        .map((s:any)=> s.players?.[0]?.id)
        .filter((pid:any)=> pid && pid !== player.id)
      const uniqueIds = Array.from(new Set(scannedPlayerIds))
      if (uniqueIds.length) {
        const inserts = uniqueIds.map(pid => ({
          player_id: pid,
          kind: 'ship_scanned',
          ref_id: null,
          message: `Your ship was scanned in sector ${sector.number}.`
        }))
        await supabaseAdmin.from('player_logs').insert(inserts)
      }
    } catch {}

    // Player logs: notify planet owners that their sector was scanned
    try {
      const { data: planetOwners } = await supabaseAdmin
        .from('planets')
        .select('owner_player_id')
        .eq('sector_id', sector.id)
        .not('owner_player_id', 'is', null)
      
      const ownerIds = planetOwners?.map(p => p.owner_player_id).filter(id => id !== player.id) || []
      const uniqueOwnerIds = Array.from(new Set(ownerIds))
      if (uniqueOwnerIds.length) {
        const inserts = uniqueOwnerIds.map(pid => ({
          player_id: pid,
          kind: 'planet_scanned',
          ref_id: null,
          message: `Your planet's sector ${sector.number} was scanned.`
        }))
        await supabaseAdmin.from('player_logs').insert(inserts)
      }
    } catch {}

    // Log the scan action for the player who performed it
    try {
      await supabaseAdmin.from('player_logs').insert({
        player_id: player.id,
        kind: 'scan_performed',
        ref_id: sector.id,
        message: `You scanned sector ${sector.number}. Found ${shipCount} ship(s), ${planetCount} planet(s).`
      })
    } catch {}
    const shipDetails = ships?.map(ship => ({
      id: ship.id,
      name: ship.name || 'Scout',
      player: {
        id: ship.players?.[0]?.id,
        handle: ship.players?.[0]?.handle,
        is_ai: ship.players?.[0]?.is_ai
      }
    })) || []
    
    return NextResponse.json({ 
      ok:true, 
      sector: { 
        number: sector.number, 
        port: port ? { kind: port.kind } : null,
        planetCount: planetCount,
        shipCount: shipCount,
        ships: shipDetails
      } 
    })
  } catch (err) {
    console.error('Error in /api/scan/single:', err)
    return NextResponse.json({ error: { code:'internal', message:'Internal server error' } }, { status:500 })
  }
}


