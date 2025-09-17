import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const { userId } = await verifyBearerToken(request)
    const { planetId, resource, qty } = await request.json()

    if (!planetId || !resource || !qty) {
      return NextResponse.json(
        { error: { code: 'invalid_request', message: 'planetId, resource, and qty are required' } },
        { status: 400 }
      )
    }

    if (!['ore', 'organics', 'goods', 'energy'].includes(resource)) {
      return NextResponse.json(
        { error: { code: 'invalid_resource', message: 'Resource must be ore, organics, goods, or energy' } },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin.rpc('game_planet_store', {
      p_user_id: userId,
      p_planet: planetId,
      p_resource: resource,
      p_qty: qty
    })

    if (error) {
      console.error('Planet store error:', error)
      return NextResponse.json(
        { error: { code: 'store_failed', message: error.message } },
        { status: 400 }
      )
    }

    return NextResponse.json({ ok: true, ...data })
  } catch (error) {
    console.error('Planet store error:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
