import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

// POST /api/cron/cycle-events - Major game events (rankings, economy, production)
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
    
    console.log('Starting cycle events system...')
    
    // Get all universes with their settings
    const { data: universes, error: universesError } = await supabaseAdmin
      .from('universes')
      .select(`
        id, 
        name,
        universe_settings!inner(
          cycle_interval_minutes,
          last_cycle_event
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
      rankingsUpdated: 0,
      economyUpdated: 0,
      errors: [] as string[]
    }
    
    // Process each universe
    for (const universe of universes || []) {
      try {
        const settings = universe.universe_settings?.[0]
        if (!settings) {
          console.log(`No settings found for universe: ${universe.name}`)
          continue
        }
        console.log(`Processing cycle events for universe: ${universe.name}`)
        
        // Check if it's time for cycle events
        const now = new Date()
        const lastCycle = settings.last_cycle_event ? new Date(settings.last_cycle_event) : null
        const intervalMs = settings.cycle_interval_minutes * 60 * 1000
        
        if (lastCycle && (now.getTime() - lastCycle.getTime()) < intervalMs) {
          console.log(`Skipping ${universe.name} - not time for cycle events yet`)
          continue
        }
        
        // Update rankings for this universe
        const { data: rankingResult, error: rankingError } = await supabaseAdmin
          .rpc('update_universe_rankings', {
            p_universe_id: universe.id
          })
        
        if (rankingError) {
          console.error(`Error updating rankings for universe ${universe.name}:`, rankingError)
          results.errors.push(`Rankings update failed for ${universe.name}: ${rankingError.message}`)
        } else {
          console.log(`Rankings updated for universe: ${universe.name}`)
          results.rankingsUpdated++
        }
        
        // Update economy (planet production, IGB interest, etc.)
        const { data: economyResult, error: economyError } = await supabaseAdmin
          .rpc('update_universe_economy', {
            p_universe_id: universe.id
          })
        
        if (economyError) {
          console.error(`Error updating economy for universe ${universe.name}:`, economyError)
          results.errors.push(`Economy update failed for ${universe.name}: ${economyError.message}`)
        } else {
          console.log(`Economy updated for universe: ${universe.name}`)
          results.economyUpdated++
        }
        
        // Update the last cycle event timestamp
        await supabaseAdmin
          .rpc('update_scheduler_timestamp', {
            p_universe_id: universe.id,
            p_event_type: 'cycle_event',
            p_timestamp: now.toISOString()
          })
        
        results.universesProcessed++
        
      } catch (error) {
        console.error(`Error processing cycle events for universe ${universe.name}:`, error)
        results.errors.push(`Cycle events failed for ${universe.name}: ${error}`)
      }
    }
    
    console.log('Cycle events system completed:', results)
    
    return NextResponse.json({
      ok: true,
      message: 'Cycle events system completed',
      ...results
    })
    
  } catch (error) {
    console.error('Error in /api/cron/cycle-events:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}


