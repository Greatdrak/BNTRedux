import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)
    const userId = authResult.userId

    // Require Special port in current sector
    const { data: playerRow } = await supabaseAdmin
      .from('players')
      .select('current_sector')
      .eq('user_id', userId)
      .single()

    const currentSector = playerRow?.current_sector
    if (!currentSector) {
      return NextResponse.json(
        { error: { code: 'not_found', message: 'Player not found' } },
        { status: 404 }
      )
    }

    const { data: port } = await supabaseAdmin
      .from('ports')
      .select('id, kind')
      .eq('sector_id', currentSector)
      .single()

    if (!port || port.kind !== 'special') {
      return NextResponse.json(
        { error: { code: 'port_not_special', message: 'Engine upgrades are only available at Special ports.' } },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin.rpc('game_engine_upgrade', {
      p_user_id: userId,
    })

    if (error) {
      console.error('RPC error (game_engine_upgrade):', error)
      return NextResponse.json(
        { error: { code: error.code || 'rpc_error', message: error.message } },
        { status: 500 }
      )
    }

    if (data?.error) {
      return NextResponse.json({ error: data.error }, { status: 400 })
    }

    return NextResponse.json(data)
  } catch (err) {
    console.error('Error in /api/engine/upgrade:', err)
    return NextResponse.json(
      { error: { code: 'internal_server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}


