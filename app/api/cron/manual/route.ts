import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

// POST /api/cron/manual - Manually trigger all cron events for testing
export async function POST(request: NextRequest) {
  try {
    const cronSecret = process.env.CRON_SECRET
    const xCronHeader = request.headers.get('x-cron')
    
    // Check authorization (only allow with secret for manual triggers)
    if (!xCronHeader || !cronSecret || xCronHeader !== cronSecret) {
      return NextResponse.json(
        { error: 'Unauthorized - requires cron secret' },
        { status: 401 }
      )
    }
    
    console.log('Manual cron trigger started...')
    
    const results = {
      turnGeneration: { success: false, error: null as string | null },
      cycleEvents: { success: false, error: null as string | null },
      updateEvents: { success: false, error: null as string | null }
    }
    
    // Trigger turn generation
    try {
      const turnResponse = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'}/api/cron/turn-generation`, {
        method: 'POST',
        headers: {
          'x-cron': cronSecret
        }
      })
      
      if (turnResponse.ok) {
        results.turnGeneration.success = true
        console.log('Turn generation triggered successfully')
      } else {
        const errorData = await turnResponse.json()
        results.turnGeneration.error = errorData.error || 'Unknown error'
      }
    } catch (error) {
      results.turnGeneration.error = error instanceof Error ? error.message : 'Unknown error'
    }
    
    // Trigger cycle events
    try {
      const cycleResponse = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'}/api/cron/cycle-events`, {
        method: 'POST',
        headers: {
          'x-cron': cronSecret
        }
      })
      
      if (cycleResponse.ok) {
        results.cycleEvents.success = true
        console.log('Cycle events triggered successfully')
      } else {
        const errorData = await cycleResponse.json()
        results.cycleEvents.error = errorData.error || 'Unknown error'
      }
    } catch (error) {
      results.cycleEvents.error = error instanceof Error ? error.message : 'Unknown error'
    }
    
    // Trigger update events
    try {
      const updateResponse = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'}/api/cron/update-events`, {
        method: 'POST',
        headers: {
          'x-cron': cronSecret
        }
      })
      
      if (updateResponse.ok) {
        results.updateEvents.success = true
        console.log('Update events triggered successfully')
      } else {
        const errorData = await updateResponse.json()
        results.updateEvents.error = errorData.error || 'Unknown error'
      }
    } catch (error) {
      results.updateEvents.error = error instanceof Error ? error.message : 'Unknown error'
    }
    
    return NextResponse.json({
      ok: true,
      timestamp: new Date().toISOString(),
      results
    })
    
  } catch (error) {
    console.error('Error in manual cron trigger:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}


