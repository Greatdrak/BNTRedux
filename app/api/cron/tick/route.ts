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
    
    console.log('Starting 5-minute tick system...')
    
    // Get all universes
    const { data: universes, error: universesError } = await supabaseAdmin
      .from('universes')
      .select('id, name')
    
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
      errors: [] as string[]
    }
    
    // Process each universe
    for (const universe of universes || []) {
      try {
        console.log(`Processing universe: ${universe.name} (${universe.id})`)
        
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
        
        results.universesProcessed++
        
        // Future: Add other 5-minute tick operations here
        // - Interest calculations on planets
        // - Bank account interest
        // - AI player actions
        // - Economic events
        
      } catch (error) {
        console.error(`Error processing universe ${universe.name}:`, error)
        results.errors.push(`Universe processing failed for ${universe.name}: ${error}`)
      }
    }
    
    console.log('5-minute tick system completed:', results)
    
    return NextResponse.json({
      ok: true,
      message: '5-minute tick system completed',
      ...results
    })
    
  } catch (error) {
    console.error('Error in /api/cron/tick:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
