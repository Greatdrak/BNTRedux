import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET /api/rankings - Get leaderboard for a universe
export async function GET(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')
    const limit = parseInt(searchParams.get('limit') || '50')
    
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
    
    // Get leaderboard
    console.log('Fetching leaderboard for universe:', universeId)
    const { data, error } = await supabaseAdmin.rpc('get_leaderboard', {
      p_universe_id: universeId,
      p_limit: limit
    })
    
    if (error) {
      console.error('Error getting leaderboard:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to get leaderboard' } },
        { status: 500 }
      )
    }
    
    console.log('Leaderboard RPC response:', data)
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/rankings:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}

// POST /api/rankings - Trigger ranking calculation for a universe
export async function POST(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { universe_id } = body
    
    if (!universe_id) {
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
      .eq('universe_id', universe_id)
      .single()
    
    if (playerError || !player) {
      return NextResponse.json(
        { error: { code: 'access_denied', message: 'Access denied to this universe' } },
        { status: 403 }
      )
    }
    
    // Update rankings
    console.log('Updating rankings for universe:', universe_id)
    const { data, error } = await supabaseAdmin.rpc('update_universe_rankings', {
      p_universe_id: universe_id
    })
    
    if (error) {
      console.error('Error updating rankings:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to update rankings' } },
        { status: 500 }
      )
    }
    
    console.log('Ranking update response:', data)
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/rankings POST:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
