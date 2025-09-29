import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    
    // Get universe from query parameter
    const url = new URL(request.url)
    const universeId = url.searchParams.get('universe_id')
    
    if (!universeId) {
      return NextResponse.json(
        { error: { code: 'missing_universe_id', message: 'universe_id parameter is required' } },
        { status: 400 }
      )
    }
    
    // Check if universe exists
    const { data: universeExists } = await supabaseAdmin.rpc('universe_exists', {
      p_universe_id: universeId
    })
    
    if (!universeExists) {
      // Check for orphaned data
      const { data: orphanedData } = await supabaseAdmin.rpc('cleanup_orphaned_player_data', {
        p_user_id: userId
      })
      
      // Get first available universe
      const { data: firstUniverse } = await supabaseAdmin.rpc('get_first_available_universe')
      
      return NextResponse.json({
        valid: false,
        error: {
          code: 'universe_not_found',
          message: 'The requested universe no longer exists'
        },
        orphaned_data: orphanedData,
        first_available_universe: firstUniverse?.[0] || null
      })
    }
    
    // Universe exists, check if player has data in it
    const { data: playerData } = await supabaseAdmin
      .from('players')
      .select('id, handle, universe_id')
      .eq('user_id', userId)
      .eq('universe_id', universeId)
      .maybeSingle()
    
    return NextResponse.json({
      valid: true,
      universe_id: universeId,
      has_player_data: !!playerData,
      player_data: playerData
    })
    
  } catch (error) {
    console.error('Error in /api/validate-universe:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
