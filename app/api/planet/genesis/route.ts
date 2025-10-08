import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)
  const { action, sectorNumber, planetId, universe_id, name } = await request.json()

  if (!['create','destroy'].includes(action)) {
    return NextResponse.json({ error: { code:'invalid_action', message:'action must be create or destroy' } }, { status:400 })
  }

  // Load the player and current sector
  const { data: me, error: meError } = await supabaseAdmin
    .from('players')
    .select('id, user_id, current_sector')
    .eq('user_id', auth.userId)
    .eq('universe_id', universe_id)
    .single()
  if (meError || !me) return NextResponse.json({ error:{ code:'not_found', message:'Player not found' } }, { status:404 })

  if (action === 'destroy') {
    if (!planetId) return NextResponse.json({ error:{ code:'invalid_input', message:'planetId required' } }, { status:400 })
    // Verify ownership
    const { data: planet, error: pErr } = await supabaseAdmin
      .from('planets')
      .select('id, owner_player_id')
      .eq('id', planetId)
      .single()
    if (pErr || !planet) return NextResponse.json({ error:{ code:'not_found', message:'Planet not found' } }, { status:404 })
    if (planet.owner_player_id !== me.id) return NextResponse.json({ error:{ code:'forbidden', message:'You may only destroy your own planets' } }, { status:403 })
    // Destroy
    await supabaseAdmin.from('planets').delete().eq('id', planetId)
    await supabaseAdmin.from('player_logs').insert({ player_id: me.id, kind:'planet_destroyed', ref_id: planetId, message:'You detonated a Genesis Torpedo and destroyed your planet.' })
    return NextResponse.json({ ok:true, action:'destroy', planetId })
  }

  // Create path
  if (typeof sectorNumber !== 'number') return NextResponse.json({ error:{ code:'invalid_input', message:'sectorNumber required' } }, { status:400 })

  // Resolve sector id from number
  const { data: sector, error: sErr } = await supabaseAdmin
    .from('sectors')
    .select('id')
    .eq('universe_id', universe_id)
    .eq('number', sectorNumber)
    .single()
  if (sErr || !sector) return NextResponse.json({ error:{ code:'not_found', message:'Sector not found' } }, { status:404 })

  // Check universe max planets per sector
  const { data: settings } = await supabaseAdmin
    .from('universe_settings')
    .select('max_planets_per_sector')
    .eq('universe_id', universe_id)
    .single()
  // Check sector rules - planet creation allowed?
  const { data: sectorPermission } = await supabaseAdmin
    .rpc('check_sector_permission', {
      p_sector_id: sector.id,
      p_player_id: me.id,
      p_action: 'create_planet'
    })
  
  if (sectorPermission && !sectorPermission.allowed) {
    return NextResponse.json(
      { error: { code: sectorPermission.reason || 'sector_rules', message: sectorPermission.message || 'Planet creation is not allowed in this sector' } },
      { status: 403 }
    )
  }

  const { data: countRes } = await supabaseAdmin
    .from('planets')
    .select('id', { count: 'exact', head: true })
    .eq('sector_id', sector.id)
  const currentCount = (countRes as any)?.length || 0
  const maxPer = (settings as any)?.max_planets_per_sector ?? 5
  if (currentCount >= maxPer) return NextResponse.json({ error:{ code:'limit', message:'Sector planet limit reached' } }, { status:400 })

  // Create planet
  const { data: newPlanet, error: cErr } = await supabaseAdmin
    .from('planets')
    .insert({ sector_id: sector.id, owner_player_id: me.id, colonists: 0, name: name || 'New Planet' })
    .select('id')
    .single()
  if (cErr || !newPlanet) return NextResponse.json({ error:{ code:'create_failed', message:'Failed to create planet' } }, { status:500 })
  await supabaseAdmin.from('player_logs').insert({ player_id: me.id, kind:'planet_created', ref_id: newPlanet.id, message:`You created a planet in sector ${sectorNumber}.` })
  return NextResponse.json({ ok:true, action:'create', planetId: newPlanet.id })
}


