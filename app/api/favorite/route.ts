import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId
    const body = await request.json()
    const { sectorNumber, flag } = body || {}

    if (typeof sectorNumber !== 'number') {
      return NextResponse.json(
        { error: { code: 'invalid_input', message: 'sectorNumber is required' } },
        { status: 400 }
      )
    }

    const { data: player } = await supabaseAdmin
      .from('players')
      .select('id, universe_id')
      .eq('user_id', userId)
      .single()

    const { data: sector } = await supabaseAdmin
      .from('sectors')
      .select('id')
      .eq('universe_id', player?.universe_id)
      .eq('number', sectorNumber)
      .single()

    if (!player || !sector) {
      return NextResponse.json(
        { error: { code: 'not_found', message: 'Player or sector not found' } },
        { status: 404 }
      )
    }

    if (flag) {
      await supabaseAdmin.from('favorites').upsert({ player_id: player.id, sector_id: sector.id })
    } else {
      await supabaseAdmin.from('favorites').delete().eq('player_id', player.id).eq('sector_id', sector.id)
    }

    const { data: favRows } = await supabaseAdmin
      .from('favorites')
      .select('sector_id')
      .eq('player_id', player.id)

    let numbers: number[] = []
    if (favRows && favRows.length) {
      const ids = favRows.map(r => r.sector_id)
      const { data: sectors } = await supabaseAdmin
        .from('sectors')
        .select('number')
        .in('id', ids)
      numbers = (sectors || []).map(s => s.number)
    }

    return NextResponse.json({ ok: true, favorites: numbers })
  } catch (err) {
    console.error('Error in /api/favorite:', err)
    return NextResponse.json(
      { error: { code: 'internal_server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}


