import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId
    
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    // Get universe - either specified or default to first available
    let universe: any = null
    
    if (universeId) {
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .eq('id', universeId)
        .single()
      universe = data
    } else {
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .order('created_at', { ascending: true })
        .limit(1)
        .single()
      universe = data
    }
    
    if (!universe) {
      return NextResponse.json({ error: { code: 'not_found', message: 'No universe found' } }, { status: 404 })
    }

    // Get player data
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id, current_sector')
      .eq('user_id', userId)
      .eq('universe_id', universe.id)
      .maybeSingle()

    if (playerError || !player) {
      console.error('Player error:', playerError)
      return NextResponse.json({ error: { code: 'not_found', message: 'Player not found' } }, { status: 404 })
    }

    // Verify player is at a special port
    const { data: port } = await supabaseAdmin
      .from('ports')
      .select('kind')
      .eq('sector_id', player.current_sector)
      .eq('kind', 'special')
      .single()

    if (!port) {
      return NextResponse.json({ error: { code: 'invalid_location', message: 'Not at a special port' } }, { status: 400 })
    }

    // Parse request body
    const body = await request.json()
    const { purchases } = body

    if (!purchases || !Array.isArray(purchases)) {
      return NextResponse.json({ error: { code: 'invalid_request', message: 'Invalid purchases data' } }, { status: 400 })
    }

    // Call the RPC function to process purchases
    const { data: result, error: purchaseError } = await supabaseAdmin
      .rpc('purchase_special_port_items', {
        p_player_id: player.id,
        p_purchases: purchases
      })

    if (purchaseError) {
      console.error('Purchase error:', purchaseError)
      return NextResponse.json({ error: { code: 'purchase_failed', message: 'Purchase failed' } }, { status: 500 })
    }

    if (!result.success) {
      return NextResponse.json({ error: { code: 'purchase_failed', message: result.error } }, { status: 400 })
    }

    return NextResponse.json({
      success: true,
      total_cost: result.total_cost,
      remaining_credits: result.remaining_credits
    })

  } catch (error) {
    console.error('Error in /api/special-port/purchase:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
