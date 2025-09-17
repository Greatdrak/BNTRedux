import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { toSectorNumber, universe_id } = body
    
    if (!toSectorNumber || typeof toSectorNumber !== 'number') {
      return NextResponse.json(
        { error: 'Invalid sector number' },
        { status: 400 }
      )
    }
    
    // Call the RPC function for atomic move operation
    const { data, error } = await supabaseAdmin.rpc('game_move', {
      p_user_id: userId,
      p_to_sector_number: toSectorNumber,
      p_universe_id: universe_id
    })
    
    if (error) {
      console.error('RPC error:', error)
      return NextResponse.json(
        { error: 'Move operation failed' },
        { status: 500 }
      )
    }
    
    // Check if RPC returned an error
    if (data.error) {
      return NextResponse.json(
        { error: data.error },
        { status: 400 }
      )
    }

    // Upsert visited for the player's new sector number
    try {
      const { data: me } = await supabaseAdmin
        .from('players')
        .select('id, current_sector')
        .eq('user_id', userId)
        .eq('universe_id', universe_id)
        .single()
      if (me?.id && me?.current_sector) {
        await supabaseAdmin.rpc('sql', {})
        await supabaseAdmin.from('visited').upsert({ player_id: me.id, sector_id: me.current_sector, last_seen: new Date().toISOString() })
      }
    } catch {}

    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/move:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
