import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '../../../../lib/supabase-server'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: 'Universe ID is required' }, { status: 400 })
    }

    // Get AI memories
    const { data: memories, error: memoriesError } = await supabaseAdmin
      .from('ai_player_memory')
      .select(`
        player_id,
        last_action,
        current_goal,
        target_sector_id,
        owned_planets,
        last_profit,
        consecutive_losses,
        players!inner(handle, universe_id)
      `)
      .eq('players.universe_id', universeId)

    if (memoriesError) {
      console.error('Error fetching AI memories:', memoriesError)
      return NextResponse.json({ error: 'Failed to fetch AI memories' }, { status: 500 })
    }

    // Get AI statistics
    const { data: statsData, error: statsError } = await supabaseAdmin.rpc('get_ai_statistics', {
      p_universe_id: universeId
    })

    if (statsError) {
      console.error('Error fetching AI statistics:', statsError)
      return NextResponse.json({ error: 'Failed to fetch AI statistics' }, { status: 500 })
    }

    // Format memories data
    const formattedMemories = memories?.map(memory => ({
      player_id: memory.player_id,
      player_name: memory.players?.handle || 'Unknown',
      last_action: memory.last_action,
      current_goal: memory.current_goal,
      target_sector_id: memory.target_sector_id,
      owned_planets: memory.owned_planets || 0,
      last_profit: memory.last_profit || 0,
      consecutive_losses: memory.consecutive_losses || 0
    })) || []

    return NextResponse.json({
      memories: formattedMemories,
      stats: statsData
    })

  } catch (error) {
    console.error('Error in /api/admin/ai-memory:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
