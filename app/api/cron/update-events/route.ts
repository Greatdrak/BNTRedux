import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

// POST /api/cron/update-events - Minor automated events (port regeneration, etc.)
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
    
    console.log('Starting update events system...')
    
    // Get all universes with their settings
    const { data: universes, error: universesError } = await supabaseAdmin
      .from('universes')
      .select(`
        id, 
        name,
        universe_settings!inner(
          update_interval_minutes,
          last_update_event
        )
      `)
    
    if (universesError) {
      console.error('Error fetching universes:', universesError)
      return NextResponse.json(
        { error: 'Failed to fetch universes' },
        { status: 500 }
      )
    }
    
    const results = {
      universesProcessed: 0,
      portsUpdated: 0,
      errors: [] as string[]
    }
    
    // Process each universe
    for (const universe of universes || []) {
      try {
        const settings = universe.universe_settings
        console.log(`Processing update events for universe: ${universe.name}`)
        
        // Check if it's time for update events
        const now = new Date()
        const lastUpdate = settings.last_update_event ? new Date(settings.last_update_event) : null
        const intervalMs = settings.update_interval_minutes * 60 * 1000
        
        if (lastUpdate && (now.getTime() - lastUpdate.getTime()) < intervalMs) {
          console.log(`Skipping ${universe.name} - not time for update events yet`)
          continue
        }
        
        // Update port stock dynamics (decay/regeneration)
        const { data: stockResult, error: stockError } = await supabaseAdmin
          .rpc('update_port_stock_dynamics', {
            p_universe_id: universe.id
          })
        
        if (stockError) {
          console.error(`Error updating port stock for universe ${universe.name}:`, stockError)
          results.errors.push(`Port stock update failed for ${universe.name}: ${stockError.message}`)
        } else {
          console.log(`Port stock updated for universe: ${universe.name}`)
          results.portsUpdated++
        }
        
        // Update the last update event timestamp
        await supabaseAdmin
          .rpc('update_scheduler_timestamp', {
            p_universe_id: universe.id,
            p_event_type: 'update_event',
            p_timestamp: now.toISOString()
          })
        
        results.universesProcessed++
        
      } catch (error) {
        console.error(`Error processing update events for universe ${universe.name}:`, error)
        results.errors.push(`Update events failed for ${universe.name}: ${error}`)
      }
    }
    
    console.log('Update events system completed:', results)
    
    return NextResponse.json({
      ok: true,
      message: 'Update events system completed',
      ...results
    })
    
  } catch (error) {
    console.error('Error in /api/cron/update-events:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}


