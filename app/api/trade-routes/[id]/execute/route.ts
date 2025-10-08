import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-server'
import { verifyBearerToken, createAuthErrorResponse } from '@/lib/auth-helper'

// POST /api/trade-routes/[id]/execute - Execute a trade route
export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id: routeId } = await params
    const authResult = await verifyBearerToken(request)
    if ('error' in authResult) {
      return createAuthErrorResponse(authResult)
    }

    const userId = authResult.userId
    const body = await request.json()
    const { max_iterations = 1, universe_id } = body

    if (!routeId || typeof routeId !== 'string') {
      return NextResponse.json(
        { error: { code: 'invalid_route_id', message: 'Invalid route ID' } },
        { status: 400 }
      )
    }

    if (typeof max_iterations !== 'number' || max_iterations < 1) {
      return NextResponse.json(
        { error: { code: 'invalid_iterations', message: 'Max iterations must be a positive number' } },
        { status: 400 }
      )
    }

    // If a single iteration, do one RPC call and return
    if (max_iterations === 1) {
      const { data, error } = await supabaseAdmin.rpc('execute_trade_route', {
        p_user_id: userId,
        p_route_id: routeId,
        p_max_iterations: 1,
        p_universe_id: universe_id
      })
      if (error || !data) {
        return NextResponse.json({ error: { code: 'server_error', message: 'Failed to execute trade route' } }, { status: 500 })
      }
      return NextResponse.json(data)
    }

    // For multiple iterations, force a loop of single-iteration calls and aggregate
    let totalProfit = 0
    let totalTurns = 0
    let iterationsDone = 0
    let logs: string[] = []

    for (let i = 0; i < max_iterations; i++) {
      const { data, error } = await supabaseAdmin.rpc('execute_trade_route', {
        p_user_id: userId,
        p_route_id: routeId,
        p_max_iterations: 1,
        p_universe_id: universe_id
      })
      if (error || !data?.ok) {
        return NextResponse.json({
          ok: iterationsDone > 0,
          total_profit: totalProfit,
          turns_spent: totalTurns,
          iterations_done: iterationsDone,
          log: logs.join('\n'),
          error: error?.message || data?.error || 'Execution failed'
        }, { status: iterationsDone > 0 ? 200 : 500 })
      }
      iterationsDone += 1
      totalProfit += Number(data.total_profit || 0)
      totalTurns += Number(data.turns_spent || 0)
      if (data.log) logs.push(String(data.log))
    }

    return NextResponse.json({
      ok: true,
      total_profit: totalProfit,
      turns_spent: totalTurns,
      iterations_done: iterationsDone,
      log: logs.join('\n')
    })

  } catch (error) {
    return NextResponse.json(
      { error: { code: 'server_error', message: 'Internal server error' } },
      { status: 500 }
    )
  }
}
