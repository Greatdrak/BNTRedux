import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/sector/mines - Get mine information for a sector
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    
    const { searchParams } = new URL(request.url)
    const sectorNumber = parseInt(searchParams.get('number') || '0')
    const universeId = searchParams.get('universe_id')
    
    if (sectorNumber < 0 || sectorNumber > 500) {
      return NextResponse.json(
        { error: 'Invalid sector number' },
        { status: 400 }
      )
    }
    
    if (!universeId) {
      return NextResponse.json(
        { error: 'Universe ID is required' },
        { status: 400 }
      )
    }
    
    // Get sector info
    const { data: sector, error: sectorError } = await supabaseAdmin
      .from('sectors')
      .select('id')
      .eq('number', sectorNumber)
      .eq('universe_id', universeId)
      .single()
    
    if (sectorError || !sector) {
      return NextResponse.json(
        { error: 'Sector not found' },
        { status: 404 }
      )
    }
    
    // Get mine information for this sector
    const { data: mineInfo, error: mineError } = await supabaseAdmin
      .rpc('get_sector_mine_info', {
        p_sector_id: sector.id,
        p_universe_id: universeId
      })
    
    if (mineError) {
      console.error('Error fetching mine info:', mineError)
      return NextResponse.json(
        { error: 'Failed to fetch mine information' },
        { status: 500 }
      )
    }
    
    return NextResponse.json({ 
      sector_number: sectorNumber,
      ...mineInfo
    })
    
  } catch (error) {
    console.error('Error in /api/sector/mines:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}


