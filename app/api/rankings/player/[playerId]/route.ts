import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET /api/rankings/player/[playerId] - Get individual player ranking
export async function GET(
  request: NextRequest,
  { params }: { params: { playerId: string } }
) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const playerId = params.playerId
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')
    
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
    
    // Get player ranking
    const { data: ranking, error: rankingError } = await supabaseAdmin
      .from('player_rankings')
      .select(`
        *,
        players!inner(handle)
      `)
      .eq('player_id', playerId)
      .eq('universe_id', universeId)
      .single()
    
    if (rankingError || !ranking) {
      return NextResponse.json(
        { error: { code: 'player_not_found', message: 'Player ranking not found' } },
        { status: 404 }
      )
    }
    
    return NextResponse.json({
      ok: true,
      ranking: {
        rank: ranking.rank_position,
        handle: ranking.players.handle,
        total_score: ranking.total_score,
        economic_score: ranking.economic_score,
        territorial_score: ranking.territorial_score,
        military_score: ranking.military_score,
        exploration_score: ranking.exploration_score,
        last_updated: ranking.last_updated
      }
    })
    
  } catch (error) {
    console.error('Error in /api/rankings/player/[playerId]:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
