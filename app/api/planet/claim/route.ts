import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const { userId } = await verifyBearerToken(request)
    const { sectorNumber, name, universe_id } = await request.json()

    if (!sectorNumber || typeof sectorNumber !== 'number') {
      return NextResponse.json(
        { error: { code: 'invalid_request', message: 'sectorNumber is required' } },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin.rpc('game_planet_claim', {
      p_user_id: userId,
      p_sector_number: sectorNumber,
      p_name: name || 'Colony',
      p_universe_id: universe_id
    })

    if (error) {
      console.error('Planet claim error:', error)
      return NextResponse.json(
        { error: { code: 'claim_failed', message: error.message } },
        { status: 400 }
      )
    }

    return NextResponse.json({ ok: true, ...data })
  } catch (error) {
    console.error('Planet claim error:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
