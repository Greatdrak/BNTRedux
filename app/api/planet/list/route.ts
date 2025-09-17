import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const { userId } = await verifyBearerToken(request)

    // Get player's planets with sector numbers
    const { data: planets, error } = await supabaseAdmin
      .from('planets')
      .select(`
        id,
        name,
        ore,
        organics,
        goods,
        energy,
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
      sectorNumber: planet.sectors.number,
      stock: {
        ore: planet.ore,
        organics: planet.organics,
        goods: planet.goods,
        energy: planet.energy
      }
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
