import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

export async function POST(request: NextRequest) {
  try {
    const cronSecret = process.env.CRON_SECRET
    const xCronHeader = request.headers.get('x-cron')
    const xVercelCronHeader = request.headers.get('x-vercel-cron')
    
    // Check authorization
    if (xVercelCronHeader) {
      // Vercel cron job
    } else if (xCronHeader && cronSecret && xCronHeader === cronSecret) {
      // Custom cron with secret
    } else {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      )
    }
    
    // DEPRECATED: This endpoint is replaced by the heartbeat system
    // Use the new regen_turns_for_universe RPC instead
    const { data, error } = await supabaseAdmin
      .rpc('regen_turns_for_universe', { p_universe_id: null }) // null = all universes
    
    if (error) {
      console.error('Error updating turns:', error)
      return NextResponse.json(
        { error: 'Failed to update turns' },
        { status: 500 }
      )
    }
    
    // Update port stock dynamics (decay/regeneration)
    const { data: stockResult, error: stockError } = await supabaseAdmin
      .rpc('update_port_stock_dynamics')
    
    if (stockError) {
      console.error('Error updating port stock dynamics:', stockError)
      // Don't fail the entire cron job for stock update errors
    }
    
    return NextResponse.json({
      ok: true,
      players_updated: data?.players_updated || 0,
      total_turns_generated: data?.total_turns_generated || 0,
      stockUpdatedCount: stockResult || 0
    })
    
  } catch (error) {
    console.error('Error in /api/cron/regen:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
