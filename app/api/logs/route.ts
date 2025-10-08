import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)
  const { searchParams } = new URL(request.url)
  const limit = Math.min(parseInt(searchParams.get('limit')||'50', 10), 200)
  const { data, error } = await supabaseAdmin
    .from('player_logs')
    .select('id, kind, ref_id, message, occurred_at')
    .eq('player_id', auth.userId)
    .order('occurred_at', { ascending: false })
    .limit(limit)
  if (error) return NextResponse.json({ error: { code:'rpc_error', message: error.message } }, { status:500 })
  return NextResponse.json({ ok:true, logs: data })
}


