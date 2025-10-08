import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// POST /api/trade-routes/[id]/calculate - Calculate route profitability
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id: routeId } = await params
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    
    // Validate route ID
    if (!routeId || typeof routeId !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_route_id', message: 'Invalid route ID' } },
        { status: 400 }
      )
    }
    
    const { data, error } = await supabaseAdmin.rpc('calculate_route_profitability', {
      p_user_id: userId,
      p_route_id: routeId
    })
    
    if (error) {
      console.error('Error calculating route profitability:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to calculate route profitability' } },
        { status: 500 }
      )
    }
    
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/trade-routes/[id]/calculate POST:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
