import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/universe-settings?universe_id=<uuid> - Get public universe settings
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }

    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    // Get universe settings (public read-only access)
    const { data: settings, error } = await supabaseAdmin
      .from('universe_settings')
      .select(`
        max_accumulated_turns,
        turns_generation_interval_minutes,
        port_regeneration_interval_minutes,
        rankings_generation_interval_minutes,
        defenses_check_interval_minutes,
        xenobes_play_interval_minutes,
        igb_interest_accumulation_interval_minutes,
        news_generation_interval_minutes,
        planet_production_interval_minutes,
        ships_tow_from_fed_sectors_interval_minutes,
        sector_defenses_degrade_interval_minutes,
        planetary_apocalypse_interval_minutes,
        game_version,
        game_name
      `)
      .eq('universe_id', universeId)
      .single()

    if (error) {
      console.error('Error fetching universe settings:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to fetch universe settings' } }, { status: 500 })
    }

    if (!settings) {
      return NextResponse.json({ error: { code: 'not_found', message: 'Universe settings not found' } }, { status: 404 })
    }

    return NextResponse.json({ settings })

  } catch (error) {
    console.error('Error in /api/universe-settings GET:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
