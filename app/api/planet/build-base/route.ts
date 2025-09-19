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

    const { planetId } = await request.json()

    if (!planetId) {
      return NextResponse.json({ success: false, error: 'Missing planet ID' }, { status: 400 })
    }

    // Call the RPC function
    const { data, error } = await supabaseAdmin.rpc('build_planet_base', {
      p_user_id: userId,
      p_planet_id: planetId
    })

    if (error) {
      console.error('Error building planet base:', error)
      return NextResponse.json({ success: false, error: 'Failed to build planet base' }, { status: 500 })
    }

    if (data.error) {
      return NextResponse.json({ success: false, error: data.error.message }, { status: 400 })
    }

    return NextResponse.json({ 
      success: true, 
      message: data.message, 
      baseCost: data.base_cost,
      resourcesConsumed: data.resources_consumed
    })

  } catch (error) {
    console.error('Error in /api/planet/build-base:', error)
    return NextResponse.json(
      { success: false, error: 'Internal server error' },
      { status: 500 }
    )
  }
}
