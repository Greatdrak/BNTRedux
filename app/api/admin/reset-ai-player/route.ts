import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '../../../../lib/supabase-server'

export async function POST(request: NextRequest) {
  try {
    const { player_id } = await request.json()

    if (!player_id) {
      return NextResponse.json({ error: 'Player ID is required' }, { status: 400 })
    }

    // Reset AI player memory and state
    const { error: memoryError } = await supabaseAdmin
      .from('ai_player_memory')
      .update({
        current_goal: 'explore',
        target_sector_id: null,
        trade_route: null,
        exploration_targets: [],
        last_profit: 0,
        consecutive_losses: 0,
        updated_at: new Date().toISOString()
      })
      .eq('player_id', player_id)

    if (memoryError) {
      console.error('Error resetting AI memory:', memoryError)
      return NextResponse.json({ error: 'Failed to reset AI memory' }, { status: 500 })
    }

    // Optionally reset ship position to a random sector
    const { data: universeData, error: universeError } = await supabaseAdmin
      .from('players')
      .select('universe_id')
      .eq('id', player_id)
      .single()

    if (!universeError && universeData) {
      const { data: randomSector, error: sectorError } = await supabaseAdmin
        .from('sectors')
        .select('id')
        .eq('universe_id', universeData.universe_id)
        .limit(1)
        .order('random()')
        .single()

      if (!sectorError && randomSector) {
        await supabaseAdmin
          .from('ships')
          .update({ sector_id: randomSector.id })
          .eq('player_id', player_id)
      }
    }

    return NextResponse.json({
      success: true,
      message: 'AI player reset successfully'
    })

  } catch (error) {
    console.error('Error in /api/admin/reset-ai-player:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
