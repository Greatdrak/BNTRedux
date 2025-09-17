import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'

// GET /api/universes - Public endpoint to list available universes
export async function GET() {
  try {
    const { data, error } = await supabaseAdmin.rpc('list_universes')

    if (error) {
      console.error('Error listing universes:', error)
      return NextResponse.json({ error: { code: 'server_error', message: 'Failed to list universes' } }, { status: 500 })
    }

    if (data.error) {
      return NextResponse.json(data.error, { status: 400 })
    }

    return NextResponse.json(data)

  } catch (error) {
    console.error('Error in /api/universes:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
