import { NextRequest, NextResponse } from 'next/server'
import fs from 'fs'
import path from 'path'
import { verifyBearerToken } from '@/lib/auth-helper'
import { supabaseAdmin } from '@/lib/supabase-server'

const CONFIG_PATH = path.join(process.cwd(), 'scripts', 'scheduler.config.json')

function readConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8')
    return JSON.parse(raw)
  } catch {
    return { turnGenerationMinutes: 3, updateEventsMinutes: 1, cycleEventsMinutes: 2 }
  }
}

function writeConfig(cfg: any) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2))
}

export async function GET() {
  const cfg = readConfig()
  return NextResponse.json({ ok: true, config: cfg })
}

export async function PUT(request: NextRequest) {
  try {
    const auth = await verifyBearerToken(request)
    if ('error' in auth) {
      return NextResponse.json(auth.error, { status: 401 })
    }

    const { data: isAdmin } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: auth.userId })
    if (!isAdmin) {
      return NextResponse.json({ error: { code: 'forbidden', message: 'Admins only' } }, { status: 403 })
    }

  const body = await request.json()
  const { turnGenerationMinutes, updateEventsMinutes, cycleEventsMinutes } = body || {}
    const cfg = readConfig()
    const next = {
      turnGenerationMinutes: Number.isFinite(turnGenerationMinutes) ? turnGenerationMinutes : cfg.turnGenerationMinutes,
      updateEventsMinutes: Number.isFinite(updateEventsMinutes) ? updateEventsMinutes : cfg.updateEventsMinutes,
    cycleEventsMinutes: Number.isFinite(cycleEventsMinutes) ? cycleEventsMinutes : cfg.cycleEventsMinutes
    }
    writeConfig(next)
    return NextResponse.json({ ok: true, config: next })
  } catch (e) {
    return NextResponse.json({ error: { code: 'server_error', message: 'Failed to update config' } }, { status: 500 })
  }
}
