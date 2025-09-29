import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '../../../../lib/supabase-server'

export async function POST(request: NextRequest) {
  try {
    const { universe_id } = await request.json()

    if (!universe_id) {
      return NextResponse.json({ error: 'Universe ID is required' }, { status: 400 })
    }

    // Trigger enhanced AI actions
    const { data: result, error } = await supabaseAdmin.rpc('cron_run_ai_actions', {
      p_universe_id: universe_id
    })

    if (error) {
      console.error('Error triggering AI actions:', error)
      return NextResponse.json({ error: 'Failed to trigger AI actions' }, { status: 500 })
    }

    return NextResponse.json({
      success: true,
      result: result,
      message: 'AI actions triggered successfully'
    })

  } catch (error) {
    console.error('Error in /api/admin/trigger-ai-actions:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
