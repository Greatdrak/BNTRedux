import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    const body = await request.json()
    const { portId, action, resource, qty, universe_id } = body
    
    console.log('🔍 TRADE DEBUG:', { userId, portId, action, resource, qty, universe_id })
    
    // Validate input
    if (!portId || typeof portId !== 'string') {
      return NextResponse.json({ error: { code: 'bad_request', message: 'Invalid portId' } }, { status: 400 })
    }
    
    if (!action || !['buy', 'sell'].includes(action)) {
      return NextResponse.json({ error: { code: 'bad_request', message: 'Invalid action' } }, { status: 400 })
    }
    
    if (!resource || !['ore', 'organics', 'goods', 'energy'].includes(resource)) {
      return NextResponse.json({ error: { code: 'bad_request', message: 'Invalid resource' } }, { status: 400 })
    }
    
    if (!qty || typeof qty !== 'number' || qty <= 0) {
      return NextResponse.json({ error: { code: 'bad_request', message: 'Invalid quantity' } }, { status: 400 })
    }
    
    // Call the RPC function for atomic trade operation
    // Commodity rules enforcement
    // Load port to check kind
    const { data: portData, error: portErr } = await supabaseAdmin
      .from('ports')
      .select('id, kind')
      .eq('id', portId)
      .single()

    console.log('🔍 PORT DEBUG:', { portData, portErr })

    if (portErr || !portData) {
      console.log('❌ PORT NOT FOUND:', portErr)
      return NextResponse.json({ error: { code: 'not_found', message: 'Port not found' } }, { status: 404 })
    }

    // Get port's sector for rule checking
    const { data: portSector } = await supabaseAdmin
      .from('ports')
      .select('sector_id')
      .eq('id', portId)
      .single()

    if (!portSector?.sector_id) {
      return NextResponse.json({ error: { code: 'invalid_port', message: 'Port sector not found' } }, { status: 404 })
    }

    // Get player ID for sector permission check
    const { data: playerData } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', universe_id)
      .single()

    if (!playerData) {
      return NextResponse.json({ error: { code: 'player_not_found', message: 'Player not found' } }, { status: 404 })
    }

    // Check sector rules - trading allowed?
    const { data: sectorPermission } = await supabaseAdmin
      .rpc('check_sector_permission', {
        p_sector_id: portSector.sector_id,
        p_player_id: playerData.id,
        p_action: 'trade'
      })
    
    if (sectorPermission && !sectorPermission.allowed) {
      return NextResponse.json(
        { error: { code: sectorPermission.reason || 'sector_rules', message: sectorPermission.message || 'Trading is not allowed in this sector' } },
        { status: 403 }
      )
    }

    if (portData.kind === 'special') {
      return NextResponse.json({ error: { code: 'invalid_port_kind', message: 'This is a Special port: no commodity trading.' } }, { status: 400 })
    }

    if (['ore','organics','goods','energy'].includes(portData.kind)) {
      // Ports SELL their native commodity and BUY everything else (including their own native commodity)
      if (action === 'buy' && resource !== portData.kind) {
        return NextResponse.json({ error: { code: 'resource_not_allowed', message: "Can only buy the port's native commodity" } }, { status: 400 })
      }
      // REMOVED: The sell restriction - ports CAN buy their own native commodity
    }

    console.log('🔍 CALLING game_trade RPC with:', {
      p_user_id: userId,
      p_port_id: portId,
      p_action: action,
      p_resource: resource,
      p_qty: qty,
      p_universe_id: universe_id
    })

    const { data, error } = await supabaseAdmin.rpc('game_trade', {
      p_user_id: userId,
      p_port_id: portId,
      p_action: action,
      p_resource: resource,
      p_qty: qty,
      p_universe_id: universe_id
    })
    
    console.log('🔍 game_trade RPC RESULT:', { data, error })
    
    if (error) {
      console.error('❌ RPC error:', error)
      return NextResponse.json({ error: { code: 'rpc_failed', message: 'Trade operation failed' } }, { status: 500 })
    }
    
    // Check if RPC returned an error
    if (data.error) {
      console.log('❌ RPC returned error:', data.error)
      return NextResponse.json({ error: data.error }, { status: 400 })
    }
    
    console.log('✅ TRADE SUCCESS:', data)
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/trade:', error)
    return NextResponse.json({ error: { code: 'internal', message: 'Internal server error' } }, { status: 500 })
  }
}
