import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId
    const body = await request.json()
    let { radius, universe_id } = body || {}
    radius = Math.max(1, Math.min(10, Number.isFinite(radius) ? radius : 5))

    // Get player - filter by universe if provided
    let playerQuery = supabaseAdmin
      .from('players')
      .select('id, universe_id, current_sector, turns')
      .eq('user_id', userId)
    
    if (universe_id) {
      playerQuery = playerQuery.eq('universe_id', universe_id)
    }
    
    const { data: player } = await playerQuery.single()

    if (!player) return NextResponse.json({ error: { code:'not_found', message:'Player not found' } }, { status:404 })
    if (player.turns < radius) return NextResponse.json({ error: { code:'insufficient_turns', message:'Not enough turns' } }, { status:400 })

    const { data: current } = await supabaseAdmin.from('sectors').select('number').eq('id', player.current_sector).single()
    const center = current?.number || 1
    const minNum = Math.max(1, center - radius)
    const maxNum = center + radius

    const { data: sectors } = await supabaseAdmin
      .from('sectors')
      .select('id, number')
      .eq('universe_id', player.universe_id)
      .gte('number', minNum)
      .lte('number', maxNum)

    const rows = sectors || []
    for (const row of rows) {
      await supabaseAdmin.from('scans').upsert({ player_id: player.id, sector_id: row.id, mode: 'full' })
    }
    await supabaseAdmin.from('players').update({ turns: player.turns - radius }).eq('id', player.id)

    const ids = rows.map(r => r.id)
    const { data: ports } = await supabaseAdmin.from('ports').select('sector_id, kind').in('sector_id', ids)
    const portBySector = new Map( (ports||[]).map((p:any)=>[p.sector_id, p.kind]) )

    // Get planet counts for scanned sectors
    const { data: planets } = await supabaseAdmin
      .from('planets')
      .select('sector_id')
      .in('sector_id', ids)
    const planetCountBySector = new Map()
    ;(planets||[]).forEach((p:any) => {
      planetCountBySector.set(p.sector_id, (planetCountBySector.get(p.sector_id) || 0) + 1)
    })

    return NextResponse.json({ 
      ok:true, 
      sectors: rows.map(r => ({ 
        number: r.number, 
        port: portBySector.has(r.id) ? { kind: portBySector.get(r.id) } : null,
        planetCount: planetCountBySector.get(r.id) || 0
      })) 
    })
  } catch (err) {
    console.error('Error in /api/scan/full:', err)
    return NextResponse.json({ error: { code:'internal', message:'Internal server error' } }, { status:500 })
  }
}


