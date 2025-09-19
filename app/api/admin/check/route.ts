import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

export async function GET(request: NextRequest) {
  try {
    const auth = await verifyBearerToken(request)
    if ('error' in auth) {
      return NextResponse.json(auth.error, { status: 401 })
    }

    const { data: isAdmin } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: auth.userId })
    return NextResponse.json({ is_admin: !!isAdmin })
  } catch (e) {
    return NextResponse.json({ is_admin: false }, { status: 200 })
  }
}


