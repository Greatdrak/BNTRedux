import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId

    const { searchParams } = new URL(request.url)
    const centerParam = searchParams.get('center')
    const radiusParam = searchParams.get('radius')
    const universeId = searchParams.get('universe_id')
    
    // Allow wider bands (up to universe size ~500)
    let radius = radiusParam ? parseInt(radiusParam) : 10
    if (!Number.isFinite(radius)) radius = 10
    radius = Math.max(1, Math.min(500, radius))

    // Get player - filter by universe if provided
    let playerQuery = supabaseAdmin
      .from('players')
      .select('id, universe_id, current_sector')
      .eq('user_id', userId)
    
    if (universeId) {
      playerQuery = playerQuery.eq('universe_id', universeId)
    }
    
    const { data: player } = await playerQuery.single()

    if (!player) return NextResponse.json({ sectors: [] })

    const { data: current } = await supabaseAdmin.from('sectors').select('number').eq('id', player.current_sector).single()
    const center = centerParam ? parseInt(centerParam) : (current?.number || 0)

    const minNum = Math.max(0, center - radius)
    const maxNum = center + radius

    const { data: sectors } = await supabaseAdmin
      .from('sectors')
      .select('id, number')
      .eq('universe_id', player.universe_id)
      .gte('number', minNum)
      .lte('number', maxNum)

    const rows = sectors || []
    const ids = rows.map(r => r.id)

    const [{ data: visited }, { data: scanned }, { data: ports }, { data: planets }] = await Promise.all([
      supabaseAdmin.from('visited').select('sector_id').eq('player_id', player.id).in('sector_id', ids),
      supabaseAdmin.from('scans').select('sector_id').eq('player_id', player.id).in('sector_id', ids),
      supabaseAdmin.from('ports').select('sector_id, kind').in('sector_id', ids),
      supabaseAdmin.from('planets').select('sector_id, owner_player_id').in('sector_id', ids)
    ])

    const visitedSet = new Set((visited||[]).map((r:any)=>r.sector_id))
    const scannedSet = new Set((scanned||[]).map((r:any)=>r.sector_id))
    const portBySector = new Map((ports||[]).map((p:any)=>[p.sector_id, p.kind]))
    const planetBySector = new Map((planets||[]).map((p:any)=>[p.sector_id, p.owner_player_id === player.id]))

    return NextResponse.json({
      sectors: rows.map(r => ({
        number: r.number,
        visited: visitedSet.has(r.id),
        scanned: scannedSet.has(r.id),
        portKind: portBySector.get(r.id) || null,
        hasPlanet: planetBySector.has(r.id),
        planetOwned: planetBySector.get(r.id) || false
      }))
    })
  } catch (err) {
    console.error('Error in /api/map:', err)
    return NextResponse.json(
      { error: { code: 'internal_server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}


