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
        colonists,
        colonists_max,
        ore,
        organics,
        goods,
        energy,
        fighters,
        torpedoes,
        shields,
        credits,
        last_production,
        last_colonist_growth,
        production_ore_percent,
        production_organics_percent,
        production_goods_percent,
        production_energy_percent,
        production_fighters_percent,
        production_torpedoes_percent,
        owner_player_id,
        base_built,
        base_cost,
        base_colonists_required,
        base_resources_required
      `)
      .eq('sector_id', sector.id)
    
    const planetData = planetError ? null : planets
    
    // Get player ID for current user to check ownership
    let playerId = null
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', userId)
      .eq('universe_id', sector.universe_id)
      .single()
    
    if (!playerError && player) {
      playerId = player.id
    }
    
    // Get ships in this sector
    const { data: ships, error: shipsError } = await supabaseAdmin
      .from('ships')
      .select(`
        id,
        name,
        players!inner(
          id,
          handle,
          is_ai,
          current_sector
        )
      `)
      .eq('players.current_sector', sector.id)
      .eq('players.universe_id', sector.universe_id)
    
    const shipData = shipsError ? [] : (ships?.map(ship => ({
      id: ship.id,
      name: ship.name || 'Scout',
      player: {
        id: ship.players.id,
        handle: ship.players.handle,
        is_ai: ship.players.is_ai
      }
    })) || [])

    // Get owner names for planets
    let ownerNames: Record<string, string> = {}
    if (planetData && planetData.length > 0) {
      const ownerPlayerIds = planetData
        .map(p => p.owner_player_id)
        .filter(id => id !== null)
      
      if (ownerPlayerIds.length > 0) {
        const { data: owners, error: ownersError } = await supabaseAdmin
          .from('players')
          .select('id, handle')
          .in('id', ownerPlayerIds)
        
        if (!ownersError && owners) {
          ownerNames = owners.reduce((acc, owner) => {
            acc[owner.id] = owner.handle
            return acc
          }, {} as Record<string, string>)
        }
      }
    }
    
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
        number: sector.number,
        ownerPlayerId: null,
        controlled: false,
        ownershipThreshold: 3,
        name: null
      },
      warps: warpSectorNumbers,
      ships: shipData,
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
        owner: p.owner_player_id === playerId,
        ownerName: p.owner_player_id ? ownerNames[p.owner_player_id] || null : null,
        colonists: p.colonists,
        colonistsMax: p.colonists_max,
        stock: {
          ore: p.ore,
          organics: p.organics,
          goods: p.goods,
          energy: p.energy,
          credits: p.credits || 0
        },
        defenses: {
          fighters: p.fighters,
          torpedoes: p.torpedoes,
          shields: p.shields
        },
        lastProduction: p.last_production,
        lastColonistGrowth: p.last_colonist_growth,
        productionAllocation: {
          ore: p.production_ore_percent || 0,
          organics: p.production_organics_percent || 0,
          goods: p.production_goods_percent || 0,
          energy: p.production_energy_percent || 0,
          fighters: p.production_fighters_percent || 0,
          torpedoes: p.production_torpedoes_percent || 0
        },
        base: {
          built: p.base_built || false,
          cost: p.base_cost || 50000,
          colonistsRequired: p.base_colonists_required || 10000,
          resourcesRequired: p.base_resources_required || 10000
        }
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
