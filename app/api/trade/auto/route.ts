import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const auth = await verifyBearerToken(request)
    if ('error' in auth) return createAuthErrorResponse(auth)

    const userId = auth.userId
    const body = await request.json()
    const { portId, universe_id } = body || {}

    console.log('🔍 Auto-trade request:', { userId, portId, universe_id })

    if (!portId || typeof portId !== 'string') {
      console.log('❌ Invalid portId:', portId)
      return NextResponse.json({ error: { code: 'bad_request', message: 'Invalid portId' } }, { status: 400 })
    }

    console.log('📡 Calling game_trade_auto RPC with:', { p_user_id: userId, p_port: portId, p_universe_id: universe_id })

    const { data, error } = await supabaseAdmin.rpc('game_trade_auto', {
      p_user_id: userId,
      p_port: portId,
      p_universe_id: universe_id
    })

    if (error) {
      console.error('❌ game_trade_auto RPC error:', error)
      return NextResponse.json({ error: { code: 'rpc_failed', message: 'Auto-trade failed' } }, { status: 500 })
    }

    console.log('📊 game_trade_auto RPC result:', { data, error })

    if (data?.error) {
      console.log('❌ RPC returned error:', data.error)
      return NextResponse.json({ error: data.error }, { status: 400 })
    }

    console.log('✅ Auto-trade successful:', data)
    return NextResponse.json({ ok: true, ...data })
  } catch (e) {
    console.error('💥 POST /api/trade/auto error:', e)
    return NextResponse.json({ error: { code: 'internal', message: 'Internal server error' } }, { status: 500 })
  }
}


