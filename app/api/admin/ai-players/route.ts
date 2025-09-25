import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET - List AI players for a universe
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: 'Universe ID required' }, { status: 400 })
    }

    // Get AI players
    const { data, error } = await supabaseAdmin.rpc('get_ai_players', {
      p_universe_id: universeId
    })

    if (error) {
      console.error('Error fetching AI players:', error)
      return NextResponse.json({ error: 'Failed to fetch AI players' }, { status: 500 })
    }

    return NextResponse.json({ aiPlayers: data })

  } catch (error) {
    console.error('Error in /api/admin/ai-players:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

// POST - Create AI players for a universe
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { universeId, count = 5 } = await request.json()

    if (!universeId) {
      return NextResponse.json({ error: 'Universe ID required' }, { status: 400 })
    }

    // Create AI players
    console.log('Creating AI players:', { universeId, count })
    const { data, error } = await supabaseAdmin.rpc('create_ai_players', {
      p_universe_id: universeId,
      p_count: count
    })

    console.log('AI players creation result:', { data, error })

    if (error) {
      console.error('Error creating AI players:', error)
      return NextResponse.json({ error: 'Failed to create AI players: ' + error.message }, { status: 500 })
    }

    if (data && data.error) {
      console.error('AI players creation failed:', data.error)
      return NextResponse.json({ error: data.error }, { status: 400 })
    }

    return NextResponse.json({ 
      success: true, 
      message: data.message,
      count: data.count 
    })

  } catch (error) {
    console.error('Error in /api/admin/ai-players:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

// DELETE - Remove AI players from a universe
export async function DELETE(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: 'Universe ID required' }, { status: 400 })
    }

    // First get AI player IDs
    const { data: aiPlayers, error: fetchError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('universe_id', universeId)
      .eq('is_ai', true)

    if (fetchError) {
      console.error('Error fetching AI players:', fetchError)
      return NextResponse.json({ error: 'Failed to fetch AI players' }, { status: 500 })
    }

    const aiPlayerIds = aiPlayers?.map(p => p.id) || []

    // Delete AI players and their ships
    const { error: deleteError } = await supabaseAdmin
      .from('ships')
      .delete()
      .in('player_id', aiPlayerIds)

    if (deleteError) {
      console.error('Error deleting AI ships:', deleteError)
      return NextResponse.json({ error: 'Failed to delete AI players' }, { status: 500 })
    }

    const { error: playersError } = await supabaseAdmin
      .from('players')
      .delete()
      .eq('universe_id', universeId)
      .eq('is_ai', true)

    if (playersError) {
      console.error('Error deleting AI players:', playersError)
      return NextResponse.json({ error: 'Failed to delete AI players' }, { status: 500 })
    }

    return NextResponse.json({ 
      success: true, 
      message: 'AI players removed successfully' 
    })

  } catch (error) {
    console.error('Error in /api/admin/ai-players:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

