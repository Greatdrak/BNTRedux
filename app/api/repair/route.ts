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
    const { hull } = body
    
    // Validate input
    if (!hull || typeof hull !== 'number' || hull <= 0) {
      return NextResponse.json(
        { error: { code: 'invalid_hull', message: 'Hull repair amount must be positive' } },
        { status: 400 }
      )
    }
    
    // Ensure player is at a Special port
    const { data: playerRow } = await supabaseAdmin
      .from('players')
      .select('current_sector')
      .eq('user_id', userId)
      .single()

    const currentSector = playerRow?.current_sector
    if (!currentSector) {
      return NextResponse.json(
        { error: { code: 'not_found', message: 'Player or current sector not found' } },
        { status: 404 }
      )
    }

    const { data: port } = await supabaseAdmin
      .from('ports')
      .select('id, kind')
      .eq('sector_id', currentSector)
      .single()

    if (!port || port.kind !== 'special') {
      return NextResponse.json(
        { error: { code: 'port_not_special', message: 'Equipment and repairs are only available at Special ports.' } },
        { status: 400 }
      )
    }

    // Call the RPC function for atomic repair operation
    const { data, error } = await supabaseAdmin.rpc('game_repair', {
      p_user_id: userId,
      p_hull: hull
    })
    
    if (error) {
      console.error('RPC error:', error)
      return NextResponse.json(
        { error: { code: 'repair_failed', message: 'Repair operation failed' } },
        { status: 500 }
      )
    }
    
    // Check if RPC returned an error
    if (data.error) {
      return NextResponse.json(
        { error: { code: 'repair_error', message: data.error } },
        { status: 400 }
      )
    }
    
    return NextResponse.json(data)
    
  } catch (error) {
    console.error('Error in /api/repair:', error)
    return NextResponse.json(
      { error: { code: 'internal_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
