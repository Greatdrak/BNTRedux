import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/admin/universe-settings - Get settings for a specific universe
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
    const universeId = searchParams.get('universe_id')

    if (!universeId) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    // Get universe settings
    const { data: settings, error } = await supabaseAdmin
      .rpc('get_universe_settings', { p_universe_id: universeId })

    if (error) {
      console.error('Error fetching universe settings:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to fetch universe settings' } }, { status: 500 })
    }

    if (!settings || settings.length === 0) {
      return NextResponse.json({ error: { code: 'not_found', message: 'Universe settings not found' } }, { status: 404 })
    }

    return NextResponse.json({ settings: settings[0] })

  } catch (error) {
    console.error('Error in /api/admin/universe-settings GET:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}

// PUT /api/admin/universe-settings - Update universe settings
export async function PUT(request: NextRequest) {
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
    const { universe_id, settings } = body

    if (!universe_id) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    if (!settings || typeof settings !== 'object') {
      return NextResponse.json({ error: { code: 'invalid_settings', message: 'Settings object is required' } }, { status: 400 })
    }

    // Update universe settings
    const { data: success, error } = await supabaseAdmin
      .rpc('update_universe_settings', {
        p_universe_id: universe_id,
        p_settings: settings,
        p_updated_by: userId
      })

    if (error) {
      console.error('Error updating universe settings:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to update universe settings' } }, { status: 500 })
    }

    if (!success) {
      return NextResponse.json({ error: { code: 'update_failed', message: 'Failed to update universe settings' } }, { status: 400 })
    }

    return NextResponse.json({ success: true, message: 'Universe settings updated successfully' })

  } catch (error) {
    console.error('Error in /api/admin/universe-settings PUT:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}

// POST /api/admin/universe-settings - Create default settings for a new universe
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
    const { universe_id } = body

    if (!universe_id) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    // Verify universe exists
    const { data: universe, error: universeError } = await supabaseAdmin
      .from('universes')
      .select('id')
      .eq('id', universe_id)
      .single()

    if (universeError || !universe) {
      return NextResponse.json({ error: { code: 'universe_not_found', message: 'Universe not found' } }, { status: 404 })
    }

    // Create default settings
    const { data: settingsId, error } = await supabaseAdmin
      .rpc('create_universe_default_settings', {
        p_universe_id: universe_id,
        p_created_by: userId
      })

    if (error) {
      console.error('Error creating universe settings:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to create universe settings' } }, { status: 500 })
    }

    return NextResponse.json({ 
      success: true, 
      message: 'Default universe settings created successfully',
      settings_id: settingsId
    })

  } catch (error) {
    console.error('Error in /api/admin/universe-settings POST:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}


