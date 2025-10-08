import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// GET: View sector rules
export async function GET(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)

  const { searchParams } = new URL(request.url)
  const sectorNumber = parseInt(searchParams.get('sectorNumber') || '0')
  const universe_id = searchParams.get('universe_id')

  if (!universe_id) {
    return NextResponse.json({ error: { code: 'invalid_input', message: 'universe_id required' } }, { status: 400 })
  }

  // Get sector with rules and owner info
  const { data: sector, error } = await supabaseAdmin
    .from('sectors')
    .select(`
      id,
      number,
      name,
      owner_player_id,
      controlled,
      allow_attacking,
      allow_trading,
      allow_planet_creation,
      allow_sector_defense,
      players:owner_player_id(handle)
    `)
    .eq('universe_id', universe_id)
    .eq('number', sectorNumber)
    .single()

  if (error || !sector) {
    return NextResponse.json({ error: { code: 'not_found', message: 'Sector not found' } }, { status: 404 })
  }

  // Format response
  const players = Array.isArray(sector.players) ? sector.players[0] : sector.players
  const response = {
    sectorNumber: sector.number,
    name: sector.name || 'Uncharted Territory',
    owned: sector.controlled || false,
    ownerHandle: players?.handle || null,
    rules: {
      allowAttacking: sector.allow_attacking,
      allowTrading: sector.allow_trading,
      allowPlanetCreation: sector.allow_planet_creation,
      allowSectorDefense: sector.allow_sector_defense
    }
  }

  return NextResponse.json(response)
}

// POST: Update sector rules (owner only)
export async function POST(request: NextRequest) {
  const auth = await verifyBearerToken(request)
  if ('error' in auth) return createAuthErrorResponse(auth)

  const { sectorNumber, rules, universe_id } = await request.json()

  if (typeof sectorNumber !== 'number') {
    return NextResponse.json({ error: { code: 'invalid_input', message: 'sectorNumber required' } }, { status: 400 })
  }

  if (!rules || typeof rules !== 'object') {
    return NextResponse.json({ error: { code: 'invalid_input', message: 'rules object required' } }, { status: 400 })
  }

  // Get player ID
  const { data: player } = await supabaseAdmin
    .from('players')
    .select('id')
    .eq('user_id', auth.userId)
    .eq('universe_id', universe_id)
    .single()

  if (!player) {
    return NextResponse.json({ error: { code: 'not_found', message: 'Player not found' } }, { status: 404 })
  }

  // Get sector ID
  const { data: sector } = await supabaseAdmin
    .from('sectors')
    .select('id')
    .eq('universe_id', universe_id)
    .eq('number', sectorNumber)
    .single()

  if (!sector) {
    return NextResponse.json({ error: { code: 'not_found', message: 'Sector not found' } }, { status: 404 })
  }

  // Call update rules function
  const { data: result, error } = await supabaseAdmin.rpc('update_sector_rules', {
    p_sector_id: sector.id,
    p_player_id: player.id,
    p_allow_attacking: rules.allowAttacking !== undefined ? rules.allowAttacking : null,
    p_allow_trading: rules.allowTrading || null,
    p_allow_planet_creation: rules.allowPlanetCreation || null,
    p_allow_sector_defense: rules.allowSectorDefense || null
  })

  if (error) {
    console.error('Sector rules update error:', error)
    return NextResponse.json({ error: { code: 'update_failed', message: error.message } }, { status: 500 })
  }

  if (!result?.success) {
    return NextResponse.json({ error: { code: result?.error || 'update_failed', message: result?.message || 'Failed to update sector rules' } }, { status: 403 })
  }

  return NextResponse.json({ success: true })
}

