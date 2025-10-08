import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universeId') || '3c491d51-61e2-4969-ba3e-142d4f5747d8'
    
    // Test the diagnostic function
    const { data: diagnosticResult, error: diagnosticError } = await supabase.rpc('diagnose_ai_players', {
      p_universe_id: universeId
    })
    
    // Test the simple debug function
    const { data: simpleResult, error: simpleError } = await supabase.rpc('simple_ai_debug', {
      p_universe_id: universeId
    })
    
    // Test the test diagnostic function
    const { data: testResult, error: testError } = await supabase.rpc('test_diagnostic')
    
    // Test the cron function directly
    const { data: cronResult, error: cronError } = await supabase.rpc('test_cron_function', {
      p_universe_id: universeId
    })
    
    return NextResponse.json({
      success: true,
      diagnostic: {
        result: diagnosticResult,
        error: diagnosticError
      },
      simple: {
        result: simpleResult,
        error: simpleError
      },
      test: {
        result: testResult,
        error: testError
      },
      cron: {
        result: cronResult,
        error: cronError
      }
    })
    
  } catch (error) {
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error'
    }, { status: 500 })
  }
}
