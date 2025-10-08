import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// POST /api/trade-routes/[id]/waypoints - Add waypoint to route
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id: routeId } = await params
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { port_id, action_type, resource, quantity, notes } = body
    
    // Validate route ID
    if (!routeId || typeof routeId !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_route_id', message: 'Invalid route ID' } },
        { status: 400 }
      )
    }
    
    // Validate required fields
    if (!port_id || typeof port_id !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_port_id', message: 'Port ID is required' } },
        { status: 400 }
      )
    }
    
    if (!action_type || !['buy', 'sell', 'trade_auto'].includes(action_type)) {
      return NextResponse.json(
        { error: { code: 'invalid_action_type', message: 'Action type must be buy, sell, or trade_auto' } },
        { status: 400 }
      )
    }
    
    if (action_type !== 'trade_auto' && (!resource || !['ore', 'organics', 'goods', 'energy'].includes(resource))) {
      return NextResponse.json(
        { error: { code: 'invalid_resource', message: 'Resource is required for buy/sell actions' } },
        { status: 400 }
      )
    }
    
    if (quantity !== undefined && (typeof quantity !== 'number' || quantity < 0)) {
      return NextResponse.json(
        { error: { code: 'invalid_quantity', message: 'Quantity must be a non-negative number' } },
        { status: 400 }
      )
    }
    
    const { data, error } = await supabaseAdmin.rpc('add_route_waypoint', {
      p_user_id: userId,
      p_route_id: routeId,
      p_port_id: port_id,
      p_action_type: action_type,
      p_resource: resource || null,
      p_quantity: quantity || 0,
      p_notes: notes?.trim() || null
    })
    
    if (error) {
      console.error('Error adding waypoint:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to add waypoint' } },
        { status: 500 }
      )
    }
    
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/trade-routes/[id]/waypoints POST:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
