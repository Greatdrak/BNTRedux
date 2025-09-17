import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    const body = await request.json()
    const { name } = body

    if (!name || typeof name !== 'string') {
      return NextResponse.json({ error: { code: 'invalid_name', message: 'Ship name is required' } }, { status: 400 })
    }

    // Call the RPC function
    const { data, error } = await supabaseAdmin
      .rpc('game_ship_rename', {
        p_user_id: userId,
        p_name: name
      })

    if (error) {
      console.error('RPC error:', error)
      return NextResponse.json({ error: { code: 'rpc_failed', message: error.message || 'Rename operation failed' } }, { status: 500 })
    }

    // Check if RPC returned an error
    if (data && data.error) {
      return NextResponse.json({ error: data.error }, { status: 400 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Error in /api/ship/rename:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
