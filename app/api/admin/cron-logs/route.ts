import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken } from '@/lib/auth-helper'

// GET /api/admin/cron-logs - Get cron logs for a universe
export async function GET(request: NextRequest) {
  try {
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return NextResponse.json(authResult.error, { status: 401 })
    }
    
    // Require admin
    const { data: isAdmin } = await supabaseAdmin.rpc('is_user_admin', { p_user_id: authResult.userId })
    if (!isAdmin) {
      return NextResponse.json({ error: { code: 'forbidden', message: 'Admins only' } }, { status: 403 })
    }

    const { searchParams } = new URL(request.url)
    const universeId = searchParams.get('universe_id')
    const limit = parseInt(searchParams.get('limit') || '50')

    if (!universeId) {
      return NextResponse.json({ error: { code: 'missing_universe_id', message: 'Universe ID is required' } }, { status: 400 })
    }

    // Try RPCs first; if not present (migrations not applied), fall back to direct selects
    let logs: any[] | null = null
    let summary: any[] | null = null

    try {
      const rpcLogs = await supabaseAdmin.rpc('get_cron_logs', { p_universe_id: universeId, p_limit: limit })
      if (!rpcLogs.error) logs = rpcLogs.data || []
    } catch {}

    try {
      const rpcSummary = await supabaseAdmin.rpc('get_cron_log_summary', { p_universe_id: universeId })
      if (!rpcSummary.error) summary = rpcSummary.data || []
    } catch {}

    // Fallback: direct table query and compute summary in Node
    if (!logs) {
      const { data: tableLogs, error: tableErr } = await supabaseAdmin
        .from('cron_logs')
        .select('id,event_type,event_name,status,message,execution_time_ms,triggered_at,metadata')
        .eq('universe_id', universeId)
        .order('triggered_at', { ascending: false })
        .limit(limit)

      if (tableErr) {
        console.error('Error fetching cron logs (fallback):', tableErr)
        return NextResponse.json({ error: { code: 'server_error', message: 'Failed to fetch cron logs' } }, { status: 500 })
      }
      logs = tableLogs || []
    }

    if (!summary) {
      // Compute summary from logs (limited window). Optionally fetch a larger window for better summary.
      const lastByType: Record<string, any> = {}
      const counts24h: Record<string, number> = {}
      const timeAgg: Record<string, { total: number; count: number }> = {}
      const nowMs = Date.now()

      for (const log of logs) {
        const key = log.event_type
        if (!lastByType[key]) lastByType[key] = log
        const tsMs = new Date(log.triggered_at).getTime()
        if (nowMs - tsMs <= 24 * 60 * 60 * 1000) {
          counts24h[key] = (counts24h[key] || 0) + 1
        }
        if (typeof log.execution_time_ms === 'number') {
          if (!timeAgg[key]) timeAgg[key] = { total: 0, count: 0 }
          timeAgg[key].total += log.execution_time_ms
          timeAgg[key].count += 1
        }
      }

      summary = Object.keys(lastByType).map((key) => {
        const last = lastByType[key]
        const agg = timeAgg[key]
        return {
          event_type: key,
          event_name: last.event_name,
          last_execution: last.triggered_at,
          last_status: last.status,
          last_message: last.message,
          execution_count_24h: counts24h[key] || 0,
          avg_execution_time_ms: agg ? Math.round(agg.total / Math.max(1, agg.count)) : null
        }
      })
    }

    return NextResponse.json({ logs, summary })

  } catch (error) {
    console.error('Error in /api/admin/cron-logs:', error)
    return NextResponse.json({ error: { code: 'server_error', message: 'Internal server error' } }, { status: 500 })
  }
}
