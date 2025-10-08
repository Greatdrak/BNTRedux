import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// POST /api/planet/capture
// Capture a defeated planet (post-combat only). Requires: planet_id
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { userId } = authResult
    const body = await request.json()
    const { planet_id } = body
    if (!planet_id) {
      return NextResponse.json({ error: 'planet_id is required' }, { status: 400 })
    }

    // Fetch planet
    const { data: planet, error: planetErr } = await supabaseAdmin
      .from('planets')
      .select('id, owner_player_id, shields, sector_id')
      .eq('id', planet_id)
      .single()

    if (planetErr || !planet) {
      return NextResponse.json({ error: 'Planet not found' }, { status: 404 })
    }

    // Planet must be owned by someone else or unowned, but be "defeated" (armor/shields depleted)
    if ((planet.shields || 0) > 0) {
      return NextResponse.json({ error: 'Planet not yet defeated. Attack until shields are depleted.' }, { status: 400 })
    }

    // Determine universe and current player id in that universe
    const { data: sector, error: sectorErr } = await supabaseAdmin
      .from('sectors')
      .select('universe_id')
      .eq('id', planet.sector_id)
      .single()

    if (sectorErr || !sector) {
      return NextResponse.json({ error: 'Sector not found for planet' }, { status: 404 })
    }

    const { data: player, error: playerErr } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', sector.universe_id)
      .single()

    if (playerErr || !player) {
      return NextResponse.json({ error: 'Player not found in this universe' }, { status: 404 })
    }

    // Assign ownership to this player
    const { error: updateErr } = await supabaseAdmin
      .from('planets')
      .update({ owner_player_id: player.id })
      .eq('id', planet_id)

    if (updateErr) {
      return NextResponse.json({ error: 'Failed to capture planet' }, { status: 500 })
    }

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('Error in /api/planet/capture:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}


