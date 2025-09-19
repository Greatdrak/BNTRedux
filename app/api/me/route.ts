import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { getUniverseSettings } from '@/lib/universe-settings'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    // Verify bearer token
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    
    const userId = authResult.userId
    
    // Get universe from query parameter or default to first available
    const url = new URL(request.url)
    const universeId = url.searchParams.get('universe_id')
    
    let universe: any = null
    
    if (universeId) {
      // Get specific universe
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .eq('id', universeId)
        .single()
      universe = data
    } else {
      // Get first available universe (fallback for existing players)
      const { data } = await supabaseAdmin
        .from('universes')
        .select('id, name')
        .order('created_at', { ascending: true })
        .limit(1)
        .single()
      universe = data
    }
    
    if (!universe) {
      return NextResponse.json(
        { error: { code: 'not_found', message: 'No universe found' } },
        { status: 404 }
      )
    }

    // Get universe settings (single source of truth)
    const universeSettings = await getUniverseSettings(universe.id)
    
    // Check if player exists in the selected universe
    const { data: existingPlayer } = await supabaseAdmin
      .from('players')
      .select('id, handle, turns, last_turn_ts, current_sector')
      .eq('user_id', userId)
      .eq('universe_id', universe.id)
      .maybeSingle()
    
    if (existingPlayer) {
      // Fetch ship and inventory separately
      const { data: shipData } = await supabaseAdmin
        .from('ships')
        .select('*')
        .eq('player_id', existingPlayer.id)
        .single()
      
      // Inventory data is now stored in ships table
      const inventoryData = {
        ore: shipData?.ore || 0,
        organics: shipData?.organics || 0,
        goods: shipData?.goods || 0,
        energy: shipData?.energy || 0,
        colonists: shipData?.colonists || 0
      }

      // Get sector number
      let currentSectorNumber: number | undefined = undefined
      if (existingPlayer.current_sector) {
        const { data: sec, error: secError } = await supabaseAdmin
          .from('sectors')
          .select('number')
          .eq('id', existingPlayer.current_sector)
          .single()
        
        
        if (secError) {
          console.error('Sector lookup error:', secError)
          // If sector doesn't exist, move player to sector 0
          const { data: sector0 } = await supabaseAdmin
            .from('sectors')
            .select('id')
            .eq('universe_id', universe.id)
            .eq('number', 0)
            .single()
          
          if (sector0) {
            await supabaseAdmin
              .from('players')
              .update({ current_sector: sector0.id })
              .eq('id', existingPlayer.id)
            
            currentSectorNumber = 0
            existingPlayer.current_sector = sector0.id
          }
        } else {
          currentSectorNumber = sec?.number
        }
      }
      
      
      
      // Player exists, return their data
      return NextResponse.json({
        player: {
          id: existingPlayer.id,
          handle: existingPlayer.handle,
          credits: shipData?.credits || 0,
          turns: existingPlayer.turns,
          turn_cap: universeSettings?.max_accumulated_turns || 5000,
          last_turn_ts: existingPlayer.last_turn_ts,
          current_sector: existingPlayer.current_sector,
          current_sector_number: currentSectorNumber,
          universe_id: universe.id,
          universe_name: universe.name
        },
        ship: shipData,
        inventory: inventoryData
      })
    }
    
    // Player doesn't exist in this universe - they need to register first
    return NextResponse.json(
      { error: { code: 'player_not_found', message: 'No player found in this universe. Please register first.' } },
      { status: 404 }
    )
    
  } catch (error) {
    console.error('Error in /api/me:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
