import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// PUT /api/trade-routes/[id] - Update a trade route
export async function PUT(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const { id: routeId } = await params
    const body = await request.json()
    const { name, description, is_active, is_automated, max_iterations } = body
    
    // Validate route ID
    if (!routeId || typeof routeId !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_route_id', message: 'Invalid route ID' } },
        { status: 400 }
      )
    }
    
    // Verify route ownership
    const { data: routeData, error: routeError } = await supabaseAdmin
      .from('trade_routes')
      .select('id, player_id, players!inner(user_id)')
      .eq('id', routeId)
      .eq('players.user_id', userId)
      .single()
    
    if (routeError || !routeData) {
      return NextResponse.json(
        { error: { code: 'route_not_found', message: 'Route not found or access denied' } },
        { status: 404 }
      )
    }
    
    // Build update object
    const updateData: any = { updated_at: new Date().toISOString() }
    
    if (name !== undefined) {
      if (typeof name !== 'string' || name.trim().length === 0) {
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
      updateData.name = name.trim()
    }
    
    if (description !== undefined) {
      updateData.description = description?.trim() || null
    }
    
    if (is_active !== undefined) {
      updateData.is_active = Boolean(is_active)
    }
    
    if (is_automated !== undefined) {
      updateData.is_automated = Boolean(is_automated)
    }
    
    if (max_iterations !== undefined) {
      if (typeof max_iterations !== 'number' || max_iterations < 0) {
        return NextResponse.json(
          { error: { code: 'invalid_iterations', message: 'Max iterations must be a non-negative number' } },
          { status: 400 }
        )
      }
      updateData.max_iterations = max_iterations
    }
    
    // Update the route
    const { data, error } = await supabaseAdmin
      .from('trade_routes')
      .update(updateData)
      .eq('id', routeId)
      .select()
      .single()
    
    if (error) {
      console.error('Error updating trade route:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to update trade route' } },
        { status: 500 }
      )
    }
    
    return NextResponse.json({
      ok: true,
      route: data,
      message: 'Trade route updated successfully'
    })
    
  } catch (error) {
    console.error('Error in /api/trade-routes/[id] PUT:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}

// DELETE /api/trade-routes/[id] - Delete a trade route
export async function DELETE(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
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
    
    // Verify route ownership
    const { data: routeData, error: routeError } = await supabaseAdmin
      .from('trade_routes')
      .select('id, player_id, players!inner(user_id)')
      .eq('id', routeId)
      .eq('players.user_id', userId)
      .single()
    
    if (routeError || !routeData) {
      return NextResponse.json(
        { error: { code: 'route_not_found', message: 'Route not found or access denied' } },
        { status: 404 }
      )
    }
    
    // Delete the route (cascade will handle waypoints, executions, etc.)
    const { error } = await supabaseAdmin
      .from('trade_routes')
      .delete()
      .eq('id', routeId)
    
    if (error) {
      console.error('Error deleting trade route:', error)
      return NextResponse.json(
        { error: { code: 'server_error', message: 'Failed to delete trade route' } },
        { status: 500 }
      )
    }
    
    return NextResponse.json({
      ok: true,
      message: 'Trade route deleted successfully'
    })
    
  } catch (error) {
    console.error('Error in /api/trade-routes/[id] DELETE:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
