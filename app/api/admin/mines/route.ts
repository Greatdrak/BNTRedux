import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/admin/mines - Get mines for a sector or universe
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    // Admin authorization check
    const { data: isAdmin, error: adminError } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: userId })
    if (adminError || !isAdmin) {
      return NextResponse.json({ error: { code: 'forbidden', message: 'Access denied. Admins only.' } }, { status: 403 })
    }

    const { searchParams } = new URL(request.url)
    const sectorId = searchParams.get('sector_id')
    const universeId = searchParams.get('universe_id')

    let query = supabaseAdmin
      .from('mines')
      .select(`
        id,
        sector_id,
        universe_id,
        mine_type,
        damage_potential,
        tech_level_required,
        is_active,
        created_at,
        sectors!inner(number),
        universes!inner(name)
      `)

    if (sectorId) {
      query = query.eq('sector_id', sectorId)
    } else if (universeId) {
      query = query.eq('universe_id', universeId)
    } else {
      return NextResponse.json({ error: { code: 'missing_params', message: 'Either sector_id or universe_id is required' } }, { status: 400 })
    }

    const { data: mines, error } = await query

    if (error) {
      console.error('Error fetching mines:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to fetch mines' } }, { status: 500 })
    }

    return NextResponse.json({ mines })

  } catch (error) {
    console.error('Error in /api/admin/mines GET:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}

// POST /api/admin/mines - Create mines in a sector
export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    // Admin authorization check
    const { data: isAdmin, error: adminError } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: userId })
    if (adminError || !isAdmin) {
      return NextResponse.json({ error: { code: 'forbidden', message: 'Access denied. Admins only.' } }, { status: 403 })
    }

    const body = await request.json()
    const { sector_id, universe_id, mine_count = 1, mine_type = 'standard' } = body

    if (!sector_id || !universe_id) {
      return NextResponse.json({ error: { code: 'missing_params', message: 'sector_id and universe_id are required' } }, { status: 400 })
    }

    if (mine_count < 1 || mine_count > 10) {
      return NextResponse.json({ error: { code: 'invalid_count', message: 'mine_count must be between 1 and 10' } }, { status: 400 })
    }

    if (!['standard', 'heavy', 'plasma', 'quantum'].includes(mine_type)) {
      return NextResponse.json({ error: { code: 'invalid_type', message: 'Invalid mine_type' } }, { status: 400 })
    }

    // Create mines using the RPC function
    const { data: result, error } = await supabaseAdmin
      .rpc('create_mines_in_sector', {
        p_sector_id: sector_id,
        p_universe_id: universe_id,
        p_mine_count: mine_count,
        p_mine_type: mine_type,
        p_created_by: userId
      })

    if (error) {
      console.error('Error creating mines:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to create mines' } }, { status: 500 })
    }

    if (result.error) {
      return NextResponse.json({ error: { code: 'creation_failed', message: result.error } }, { status: 400 })
    }

    return NextResponse.json({ 
      success: true, 
      message: `Created ${result.mines_created} ${mine_type} mine(s) in sector`,
      ...result
    })

  } catch (error) {
    console.error('Error in /api/admin/mines POST:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}

// DELETE /api/admin/mines - Remove mines from a sector
export async function DELETE(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    const userId = authResult.userId

    // Admin authorization check
    const { data: isAdmin, error: adminError } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: userId })
    if (adminError || !isAdmin) {
      return NextResponse.json({ error: { code: 'forbidden', message: 'Access denied. Admins only.' } }, { status: 403 })
    }

    const { searchParams } = new URL(request.url)
    const sectorId = searchParams.get('sector_id')
    const mineId = searchParams.get('mine_id')

    if (!sectorId && !mineId) {
      return NextResponse.json({ error: { code: 'missing_params', message: 'Either sector_id or mine_id is required' } }, { status: 400 })
    }

    let query = supabaseAdmin.from('mines').delete()

    if (mineId) {
      query = query.eq('id', mineId)
    } else {
      query = query.eq('sector_id', sectorId)
    }

    const { data, error } = await query.select('id')

    if (error) {
      console.error('Error deleting mines:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to delete mines' } }, { status: 500 })
    }

    return NextResponse.json({ 
      success: true, 
      message: `Removed ${data?.length || 0} mine(s)`,
      deleted_count: data?.length || 0
    })

  } catch (error) {
    console.error('Error in /api/admin/mines DELETE:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}


