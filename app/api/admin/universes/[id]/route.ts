import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// DELETE /api/admin/universes/[id] - Destroy universe
export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }

    // TODO: Add admin authorization check here

    const universeId = params.id

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    if (!uuidRegex.test(universeId)) {
      return NextResponse.json({ error: { code: 'invalid_id', message: 'Invalid universe ID format' } }, { status: 400 })
    }

    const { data, error } = await supabaseAdmin.rpc('destroy_universe', {
      p_universe_id: universeId
    })

    if (error) {
      console.error('Error destroying universe:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to destroy universe' } }, { status: 500 })
    }

    if (data.error) {
      return NextResponse.json(data.error, { status: 400 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Error in /api/admin/universes/[id] DELETE:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
