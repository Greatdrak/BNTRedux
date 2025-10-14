import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)
  
  const { searchParams } = new URL(request.url)
  const limit = Math.min(parseInt(searchParams.get('limit')||'50', 10), 200)
  const universeId = searchParams.get('universe_id')
  
  if (!universeId) {
    return NextResponse.json({ error: { code:'missing_universe', message: 'universe_id parameter required' } }, { status:400 })
  }
  
  // First get the player_id for this user in this universe
  const { data: player, error: playerError } = await supabaseAdmin
    .from('players')
    .select('id')
    .eq('user_id', auth.userId)
    .eq('universe_id', universeId)
    .single()
    
  if (playerError || !player) {
    return NextResponse.json({ error: { code:'player_not_found', message: 'Player not found in this universe' } }, { status:404 })
  }
  
  // Now get the logs for this player
  const { data, error } = await supabaseAdmin
    .from('player_logs')
    .select('id, kind, ref_id, message, occurred_at')
    .eq('player_id', player.id)
    .order('occurred_at', { ascending: false })
    .limit(limit)
    
  if (error) return NextResponse.json({ error: { code:'rpc_error', message: error.message } }, { status:500 })
  return NextResponse.json({ ok:true, logs: data })
}


