import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)

  const { sectorNumber, name, universe_id } = await request.json()

  if (typeof sectorNumber !== 'number') {
    return NextResponse.json({ error: { code: 'invalid_input', message: 'sectorNumber required' } }, { status: 400 })
  }

  if (!name || typeof name !== 'string') {
    return NextResponse.json({ error: { code: 'invalid_input', message: 'name required' } }, { status: 400 })
  }

  // Get player ID
  const { data: player } = await supabaseAdmin
    .from('players')
    .select('id')
    .eq('user_id', auth.userId)
    .eq('universe_id', universe_id)
    .single()

  if (!player) {
    return NextResponse.json({ error: { code: 'not_found', message: 'Player not found' } }, { status: 404 })
  }

  // Get sector ID
  const { data: sector } = await supabaseAdmin
    .from('sectors')
    .select('id')
    .eq('universe_id', universe_id)
    .eq('number', sectorNumber)
    .single()

  if (!sector) {
    return NextResponse.json({ error: { code: 'not_found', message: 'Sector not found' } }, { status: 404 })
  }

  // Call rename function
  const { data: result, error } = await supabaseAdmin.rpc('rename_sector', {
    p_sector_id: sector.id,
    p_player_id: player.id,
    p_new_name: name
  })

  if (error) {
    console.error('Sector rename error:', error)
    return NextResponse.json({ error: { code: 'rename_failed', message: error.message } }, { status: 500 })
  }

  if (!result?.success) {
    return NextResponse.json({ error: { code: result?.error || 'rename_failed', message: result?.message || 'Failed to rename sector' } }, { status: 403 })
  }

  return NextResponse.json({ success: true, name: result.name })
}

