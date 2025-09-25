import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET /api/players - List all players for the authenticated user
export async function GET(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId

    // Get all players for this user across all universes
    const { data: players, error } = await supabaseAdmin
      .from('players')
      .select(`
        id,
        handle,
        universe_id,
        universes!inner(name)
      `)
      .eq('user_id', userId)

    if (error) {
      console.error('Error fetching players:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to fetch players' } },
        { status: 500 }
      )
    }

    // Transform the data to include universe name
    const transformedPlayers = players?.map(player => ({
      id: player.id,
      handle: player.handle,
      universe_id: player.universe_id,
      universe_name: player.universes?.[0]?.name
    })) || []

    return NextResponse.json({
      players: transformedPlayers
    })

  } catch (error) {
    console.error('Error in /api/players:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
