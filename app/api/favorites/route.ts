import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId

    const { data: player } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .single()

    if (!player) return NextResponse.json({ favorites: [] })

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

    return NextResponse.json({ favorites: numbers })
  } catch (err) {
    console.error('Error in /api/favorites:', err)
    return NextResponse.json(
      { error: { code: 'internal_server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}


