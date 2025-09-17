import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const { userId } = await verifyBearerToken(request)
    const { searchParams } = new URL(request.url)
    const sectorNumber = parseInt(searchParams.get('number') || '0')
    const universeId = searchParams.get('universe_id')
    
    if (sectorNumber < 0 || sectorNumber > 500) {
      return NextResponse.json(
        { error: 'Invalid sector number' },
        { status: 400 }
      )
    }
    
    // Get sector info - filter by universe if provided
    let sectorQuery = supabaseAdmin
      .from('sectors')
      .select(`
        id,
        number,
        universe_id
      `)
      .eq('number', sectorNumber)
    
    if (universeId) {
      sectorQuery = sectorQuery.eq('universe_id', universeId)
    }
    
    const { data: sector, error: sectorError } = await sectorQuery.single()
    
    
    if (sectorError || !sector) {
      console.error('Sector not found:', { sectorNumber, sectorError })
      return NextResponse.json(
        { error: 'Sector not found' },
        { status: 404 }
      )
    }
    
    // Get warps from this sector
    const { data: warps, error: warpsError } = await supabaseAdmin
      .from('warps')
      .select(`
        to_sector
      `)
      .eq('from_sector', sector.id)
    
    
    if (warpsError) {
      console.error('Warps error:', warpsError)
      return NextResponse.json(
        { error: 'Failed to fetch warps' },
        { status: 500 }
      )
    }
    
    // Get port info if it exists
    const { data: port, error: portError } = await supabaseAdmin
      .from('ports')
      .select('*')
      .eq('sector_id', sector.id)
      .single()
    
    
    // Port error is OK if no port exists
    const portData = portError && portError.code === 'PGRST116' ? null : port
    
    // Get planet info if it exists (there can be multiple planets per sector)
    const { data: planets, error: planetError } = await supabaseAdmin
      .from('planets')
      .select(`
        id,
        name,
        owner_player_id,
        players(user_id)
      `)
      .eq('sector_id', sector.id)
    
    const planetData = planetError ? null : planets
    const isOwner = planetData && planetData.some(p => p.players && p.players.user_id === userId)
    
    // Get sector numbers for warps
    const warpSectorNumbers = []
    if (warps && warps.length > 0) {
      const { data: warpSectors, error: warpSectorsError } = await supabaseAdmin
        .from('sectors')
        .select('number')
        .in('id', warps.map(w => w.to_sector))
      
      if (!warpSectorsError && warpSectors) {
        warpSectorNumbers.push(...warpSectors.map(s => s.number))
      }
    }

    return NextResponse.json({
      sector: {
        number: sector.number
      },
      warps: warpSectorNumbers,
      port: portData ? {
        id: portData.id,
        kind: portData.kind,
        stock: {
          ore: portData.ore,
          organics: portData.organics,
          goods: portData.goods,
          energy: portData.energy
        },
        prices: {
          ore: portData.price_ore,
          organics: portData.price_organics,
          goods: portData.price_goods,
          energy: portData.price_energy
        }
      } : null,
      planets: planetData ? planetData.map(p => ({
        id: p.id,
        name: p.name,
        owner: p.players && p.players.user_id === userId
      })) : []
    })
    
  } catch (error) {
    console.error('Error in /api/sector:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
