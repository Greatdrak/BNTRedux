import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId
    const body = await request.json()
    const { universe_id } = body || {}

    // Load player info - filter by universe if provided
    let playerQuery = supabaseAdmin
      .from('players')
      .select('id, turns, current_sector')
      .eq('user_id', userId)
    
    if (universe_id) {
      playerQuery = playerQuery.eq('universe_id', universe_id)
    }
    
    const { data: player } = await playerQuery.single()
    if (!player) return NextResponse.json({ error: { code:'not_found', message:'Player not found' } }, { status:404 })
    if (player.turns < 1) return NextResponse.json({ error: { code:'insufficient_turns', message:'Not enough turns' } }, { status:400 })

    // Get outgoing warps
    const { data: warps } = await supabaseAdmin
      .from('warps')
      .select('to_sector')
      .eq('from_sector', player.current_sector)

    const destIds = (warps||[]).map(w => w.to_sector)
    if (destIds.length === 0) {
      await supabaseAdmin.from('players').update({ turns: player.turns - 1 }).eq('id', player.id)
      return NextResponse.json({ ok:true, sectors: [] })
    }

    const [{ data: sectors }, { data: ports }, { data: planets }] = await Promise.all([
      supabaseAdmin.from('sectors').select('id, number').in('id', destIds),
      supabaseAdmin.from('ports').select('sector_id, kind').in('sector_id', destIds),
      supabaseAdmin.from('planets').select('sector_id').in('sector_id', destIds)
    ])
    const kindBySector = new Map((ports||[]).map((p:any)=>[p.sector_id, p.kind]))
    
    // Count planets per sector
    const planetCountBySector = new Map()
    ;(planets||[]).forEach((p:any) => {
      planetCountBySector.set(p.sector_id, (planetCountBySector.get(p.sector_id) || 0) + 1)
    })

    // Consume 1 turn and mark scans for these sectors
    await supabaseAdmin.from('players').update({ turns: player.turns - 1 }).eq('id', player.id)
    for (const s of (sectors||[])) {
      await supabaseAdmin.from('scans').upsert({ player_id: player.id, sector_id: s.id, mode: 'single' })
    }

    return NextResponse.json({ 
      ok:true, 
      sectors: (sectors||[]).map((s:any)=> ({ 
        number: s.number, 
        port: kindBySector.has(s.id) ? { kind: kindBySector.get(s.id) } : null,
        planetCount: planetCountBySector.get(s.id) || 0
      })) 
    })
  } catch (err) {
    console.error('Error in /api/scan/warps:', err)
    return NextResponse.json({ error: { code:'internal', message:'Internal server error' } }, { status:500 })
  }
}


