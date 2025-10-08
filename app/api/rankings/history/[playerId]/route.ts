import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET /api/rankings/history/[playerId] - Get ranking history for a player
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ playerId: string }> }
) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const { playerId } = await params
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')
    const limit = parseInt(searchParams.get('limit') || '100')
    
    if (!universeId) {
      return NextResponse.json(
        { error: { code: 'missing_universe_id', message: 'Universe ID is required' } },
        { status: 400 }
      )
    }
    
    // Verify user has access to this universe
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universeId)
      .single()
    
    if (playerError || !player) {
      return NextResponse.json(
        { error: { code: 'access_denied', message: 'Access denied to this universe' } },
        { status: 403 }
      )
    }
    
    // Get ranking history
    const { data: history, error: historyError } = await supabaseAdmin
      .from('ranking_history')
      .select('*')
      .eq('player_id', playerId)
      .eq('universe_id', universeId)
      .order('recorded_at', { ascending: false })
      .limit(limit)
    
    if (historyError) {
      console.error('Error getting ranking history:', historyError)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to get ranking history' } },
        { status: 500 }
      )
    }
    
    return NextResponse.json({
      ok: true,
      history: history || []
    })
    
  } catch (error) {
    console.error('Error in /api/rankings/history/[playerId]:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
