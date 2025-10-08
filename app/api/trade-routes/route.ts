import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET /api/trade-routes - Get player's trade routes
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    const userId = authResult.userId
    const { searchParams } = new URL(request.url)
    let universeId = searchParams.get('universe_id')

    if (universeId) {
      const { data: playerInUniverse } = await supabaseAdmin
        .from('players')
        .select('id')
        .eq('user_id', userId)
        .eq('universe_id', universeId)
        .maybeSingle()
      if (!playerInUniverse) {
        return NextResponse.json(
          { error: { code: 'forbidden', message: 'You do not have a character in this universe' } },
          { status: 403 }
        )
      }
    } else {
      const { data: playerRow } = await supabaseAdmin
        .from('players')
        .select('universe_id')
        .eq('user_id', userId)
        .order('created_at', { ascending: true })
        .limit(1)
        .maybeSingle()
      if (!playerRow) {
        return NextResponse.json(
          { error: { code: 'player_not_found', message: 'No character found for this user' } },
          { status: 404 }
        )
      }
      universeId = playerRow.universe_id
    }

    const { data, error } = await supabaseAdmin.rpc('get_player_trade_routes', {
      p_user_id: userId,
      p_universe_id: universeId
    })

    if (error) {
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to get trade routes' } },
        { status: 500 }
      )
    }

    return NextResponse.json(data)

  } catch (error) {
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}

// POST /api/trade-routes - Create a new trade route
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }

    const userId = authResult.userId
    const body = await request.json()
    const { universe_id, name, description, movement_type = 'warp' } = body

    if (!universe_id) {
      return NextResponse.json(
        { error: { code: 'missing_universe_id', message: 'Universe ID is required' } },
        { status: 400 }
      )
    }

    const { data: playerInUniverse } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universe_id)
      .maybeSingle()
    if (!playerInUniverse) {
      return NextResponse.json(
        { error: { code: 'forbidden', message: 'You do not have a character in this universe' } },
        { status: 403 }
      )
    }

    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return NextResponse.json(
        { error: { code: 'invalid_name', message: 'Route name is required' } },
        { status: 400 }
      )
    }

    if (name.length > 50) {
      return NextResponse.json(
        { error: { code: 'name_too_long', message: 'Route name must be 50 characters or less' } },
        { status: 400 }
      )
    }

    if (movement_type && !['warp', 'realspace'].includes(movement_type)) {
      return NextResponse.json(
        { error: { code: 'invalid_movement_type', message: 'Movement type must be warp or realspace' } },
        { status: 400 }
      )
    }

    const { data, error } = await supabaseAdmin.rpc('create_trade_route', {
      p_user_id: userId,
      p_universe_id: universe_id,
      p_name: name.trim(),
      p_description: description?.trim() || null,
      p_movement_type: movement_type
    })

    if (error) {
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to create trade route' } },
        { status: 500 }
      )
    }

    return NextResponse.json(data)

  } catch (error) {
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
