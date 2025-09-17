import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// POST /api/trade-routes/[id]/execute - Execute a trade route
export async function POST(request: NextRequest, { params }: { params: { id: string } }) {
  try {
    console.log('Trade route execute API called')
    
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const routeId = params.id
    const body = await request.json()
    const { max_iterations = 1, universe_id } = body
    
    console.log('Executing trade route:', { userId, routeId, max_iterations, universe_id })
    
    // Validate route ID
    if (!routeId || typeof routeId !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_route_id', message: 'Invalid route ID' } },
        { status: 400 }
      )
    }
    
    if (typeof max_iterations !== 'number' || max_iterations < 1) {
      return NextResponse.json(
        { error: { code: 'invalid_iterations', message: 'Max iterations must be a positive number' } },
        { status: 400 }
      )
    }
    
    console.log('Calling execute_trade_route RPC...')
    const { data, error } = await supabaseAdmin.rpc('execute_trade_route', {
      p_user_id: userId,
      p_route_id: routeId,
      p_max_iterations: max_iterations,
      p_universe_id: universe_id
    })
    
    console.log('RPC result:', { data, error })
    
    if (error) {
      console.error('Error executing trade route:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to execute trade route' } },
        { status: 500 }
      )
    }
    
    console.log('Returning successful response:', data)
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/trade-routes/[id]/execute POST:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
