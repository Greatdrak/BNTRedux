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
    
    // Add +1 turn to players with turns < turn_cap
    const { data, error } = await supabaseAdmin
      .from('players')
      .update({ 
        turns: supabaseAdmin.sql`LEAST(turns + 1, turn_cap)`,
        last_turn_ts: new Date().toISOString()
      })
      .lt('turns', supabaseAdmin.sql`turn_cap`)
      .select('id')
    
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
      updatedCount: data?.length || 0,
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
