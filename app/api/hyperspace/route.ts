import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) return createAuthErrorResponse(authResult)

    const userId = authResult.userId
    const body = await request.json()
    const { toSectorNumber, universe_id } = body || {}

    if (typeof toSectorNumber !== 'number' || toSectorNumber < 1) {
      return NextResponse.json(
        { error: { code: 'invalid_input', message: 'Invalid target sector number' } },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin.rpc('game_hyperspace', {
      p_user_id: userId,
      p_target_sector_number: toSectorNumber,
      p_universe_id: universe_id,
    })

    if (error) {
      console.error('RPC error (game_hyperspace):', error)
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
    console.error('Error in /api/hyperspace:', err)
    return NextResponse.json(
      { error: { code: 'internal_server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}


