import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }
    const { userId } = authResult

    // Get player's planets with sector numbers and all planet data
    const { data: planets, error } = await supabaseAdmin
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
        last_production,
        last_colonist_growth,
        sectors!inner(number)
      `)
      .eq('owner_player_id', (await supabaseAdmin.from('players').select('id').eq('user_id', userId).single()).data?.id)

    if (error) {
      console.error('Planet list error:', error)
      return NextResponse.json(
        { error: { code: 'list_failed', message: error.message } },
        { status: 500 }
      )
    }

    const formattedPlanets = planets?.map(planet => ({
      id: planet.id,
      name: planet.name,
      sectorNumber: planet.sectors?.[0]?.number || 0,
      colonists: planet.colonists,
      colonistsMax: planet.colonists_max,
      stock: {
        ore: planet.ore,
        organics: planet.organics,
        goods: planet.goods,
        energy: planet.energy
      },
      defenses: {
        fighters: planet.fighters,
        torpedoes: planet.torpedoes,
        shields: planet.shields
      },
      lastProduction: planet.last_production,
      lastColonistGrowth: planet.last_colonist_growth
    })) || []

    return NextResponse.json({ planets: formattedPlanets })
  } catch (error) {
    console.error('Planet list error:', error)
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
