import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

// POST /api/cron/turn-generation - Generate turns for all players
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
    
    console.log('Starting turn generation system...')
    
    // Get all universes with their settings
    const { data: universes, error: universesError } = await supabaseAdmin
      .from('universes')
      .select(`
        id, 
        name,
        universe_settings(
          turn_generation_interval_minutes,
          turns_per_generation,
          last_turn_generation
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
      playersUpdated: 0,
      errors: [] as string[]
    }
    
    // Process each universe
    for (const universe of universes || []) {
      try {
        const settings = universe.universe_settings || { turn_generation_interval_minutes: 3, turns_per_generation: 12, last_turn_generation: null }
        console.log(`Processing turn generation for universe: ${universe.name}`)
        
        // Check if it's time for turn generation
        const now = new Date()
        const lastGeneration = settings.last_turn_generation ? new Date(settings.last_turn_generation) : null
        const intervalMs = settings.turn_generation_interval_minutes * 60 * 1000
        
        if (lastGeneration && (now.getTime() - lastGeneration.getTime()) < intervalMs) {
          console.log(`Skipping ${universe.name} - not time for turn generation yet`)
          continue
        }
        
        // Generate turns for all players in this universe using RPC
        const { data: players, error: playersError } = await supabaseAdmin
          .rpc('generate_turns_for_universe', {
            p_universe_id: universe.id,
            p_turns_to_add: settings.turns_per_generation
          })
        
        if (playersError) {
          console.error(`Error updating turns for universe ${universe.name}:`, playersError)
          results.errors.push(`Turn generation failed for ${universe.name}: ${playersError.message}`)
        } else {
          const turnResult = players?.[0]
          const playersUpdated = turnResult?.players_updated || 0
          const totalTurnsGenerated = turnResult?.total_turns_generated || 0
          
          console.log(`Generated ${totalTurnsGenerated} turns for ${playersUpdated} players in ${universe.name}`)
          results.playersUpdated += playersUpdated
          
          // Update the last turn generation timestamp
          await supabaseAdmin
            .rpc('update_scheduler_timestamp', {
              p_universe_id: universe.id,
              p_event_type: 'turn_generation',
              p_timestamp: now.toISOString()
            })
        }
        
        results.universesProcessed++
        
      } catch (error) {
        console.error(`Error processing turn generation for universe ${universe.name}:`, error)
        results.errors.push(`Turn generation failed for ${universe.name}: ${error}`)
      }
    }
    
    console.log('Turn generation system completed:', results)
    
    return NextResponse.json({
      ok: true,
      message: 'Turn generation system completed',
      ...results
    })
    
  } catch (error) {
    console.error('Error in /api/cron/turn-generation:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
