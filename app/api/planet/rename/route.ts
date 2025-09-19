import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

export async function POST(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }
    const userId = authResult.userId

    const { planetId, newName } = await request.json()

    if (!planetId || !newName) {
      return NextResponse.json({ success: false, error: 'Missing planet ID or new name' }, { status: 400 })
    }

    // Call the RPC function
    const { data, error } = await supabaseAdmin.rpc('rename_planet', {
      p_user_id: userId,
      p_planet_id: planetId,
      p_new_name: newName
    })

    if (error) {
      console.error('Error renaming planet:', error)
      return NextResponse.json({ success: false, error: 'Failed to rename planet' }, { status: 500 })
    }

    if (data && data.error) {
      return NextResponse.json({ success: false, error: data.error.message }, { status: 400 })
    }

    return NextResponse.json({ success: true, message: data.message, newName: data.new_name })

  } catch (error) {
    console.error('Error in /api/planet/rename:', error)
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500 }
    )
  }
}