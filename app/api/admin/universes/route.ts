import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/admin/universes - List all universes
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }

    // TODO: Add admin authorization check here
    // For now, any authenticated user can access admin functions

    const { data, error } = await supabaseAdmin.rpc('list_universes')

    if (error) {
      console.error('Error listing universes:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to list universes' } }, { status: 500 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Error in /api/admin/universes:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}

// POST /api/admin/universes - Create new universe
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }

    // TODO: Add admin authorization check here

    const body = await request.json()
    const { 
      name = 'Alpha', 
      portDensity = 0.30, 
      planetDensity = 0.25, 
      sectorCount = 500,
      aiPlayerCount = 0
    } = body

    // Validate inputs
    if (typeof name !== 'string' || name.trim().length === 0) {
      return NextResponse.json({ error: { code: 'invalid_name', message: 'Universe name is required' } }, { status: 400 })
    }

    if (typeof portDensity !== 'number' || portDensity < 0 || portDensity > 1) {
      return NextResponse.json({ error: { code: 'invalid_density', message: 'Port density must be between 0 and 1' } }, { status: 400 })
    }

    if (typeof planetDensity !== 'number' || planetDensity < 0 || planetDensity > 1) {
      return NextResponse.json({ error: { code: 'invalid_density', message: 'Planet density must be between 0 and 1' } }, { status: 400 })
    }

    if (typeof sectorCount !== 'number' || sectorCount < 1 || sectorCount > 1000) {
      return NextResponse.json({ error: { code: 'invalid_sectors', message: 'Sector count must be between 1 and 1000' } }, { status: 400 })
    }

    if (typeof aiPlayerCount !== 'number' || aiPlayerCount < 0 || aiPlayerCount > 100) {
      return NextResponse.json({ error: { code: 'invalid_ai_count', message: 'AI player count must be between 0 and 100' } }, { status: 400 })
    }

    const { data, error } = await supabaseAdmin.rpc('create_universe', {
      p_name: name.trim(),
      p_port_density: portDensity,
      p_planet_density: planetDensity,
      p_sector_count: sectorCount,
      p_ai_player_count: aiPlayerCount
    })

    if (error) {
      console.error('Error creating universe:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to create universe' } }, { status: 500 })
    }

    if (data.error) {
      return NextResponse.json(data.error, { status: 400 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Error in /api/admin/universes POST:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
