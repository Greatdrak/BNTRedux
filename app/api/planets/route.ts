import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')
    
    if (!universeId) {
      return NextResponse.json({ error: 'Universe ID required' }, { status: 400 })
    }

    // Get the authenticated user
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const token = authHeader.split(' ')[1]
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    
    if (authError || !user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // Get player ID
    const { data: player, error: playerError } = await supabaseAdmin
      .from('players')
      .select('id')
      .eq('user_id', user.id)
      .eq('universe_id', universeId)
      .single()

    if (playerError || !player) {
      return NextResponse.json({ error: 'Player not found' }, { status: 404 })
    }

    // Get all planets owned by this player
    const { data: planets, error: planetsError } = await supabaseAdmin
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
        credits,
        fighters,
        torpedoes,
        base_built,
        production_ore_percent,
        production_organics_percent,
        production_goods_percent,
        production_energy_percent,
        production_fighters_percent,
        production_torpedoes_percent,
        sector_id
      `)
      .eq('owner_player_id', player.id)
      .order('created_at')

    if (planetsError) {
      console.error('Error fetching planets:', planetsError)
      return NextResponse.json({ error: 'Failed to fetch planets' }, { status: 500 })
    }

    // Get sector numbers for the planets
    const sectorIds = planets.map(p => p.sector_id).filter(Boolean)
    let sectorNumbers: Record<string, number> = {}
    
    if (sectorIds.length > 0) {
      const { data: sectors, error: sectorsError } = await supabaseAdmin
        .from('sectors')
        .select('id, number')
        .in('id', sectorIds)
        .eq('universe_id', universeId)
      
      if (!sectorsError && sectors) {
        sectorNumbers = sectors.reduce((acc, sector) => {
          acc[sector.id] = sector.number
          return acc
        }, {} as Record<string, number>)
      }
    }

    // Calculate totals
    const totals = planets.reduce((acc, planet) => ({
      colonists: acc.colonists + planet.colonists,
      ore: acc.ore + planet.ore,
      organics: acc.organics + planet.organics,
      goods: acc.goods + planet.goods,
      energy: acc.energy + planet.energy,
      credits: acc.credits + planet.credits,
      fighters: acc.fighters + planet.fighters,
      torpedoes: acc.torpedoes + planet.torpedoes,
      bases: acc.bases + (planet.base_built ? 1 : 0)
    }), {
      colonists: 0,
      ore: 0,
      organics: 0,
      goods: 0,
      energy: 0,
      credits: 0,
      fighters: 0,
      torpedoes: 0,
      bases: 0
    })

    return NextResponse.json({
      planets: planets.map(planet => ({
        id: planet.id,
        name: planet.name,
        sector: sectorNumbers[planet.sector_id] || 0,
        colonists: planet.colonists,
        colonists_max: planet.colonists_max,
        ore: planet.ore,
        organics: planet.organics,
        goods: planet.goods,
        energy: planet.energy,
        credits: planet.credits,
        fighters: planet.fighters,
        torpedoes: planet.torpedoes,
        has_base: planet.base_built || false,
        production_allocation: {
          ore: planet.production_ore_percent || 0,
          organics: planet.production_organics_percent || 0,
          goods: planet.production_goods_percent || 0,
          energy: planet.production_energy_percent || 0,
          fighters: planet.production_fighters_percent || 0,
          torpedoes: planet.production_torpedoes_percent || 0
        }
      })),
      totals,
      count: planets.length
    })

  } catch (error) {
    console.error('Error in planets API:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}