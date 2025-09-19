# Scheduler & Cron — BNT‑Redux

Purpose: Single source of truth for game timing (turns, ticks, events) and how UI reflects it.

## Components
- API: `/api/cron/{turn-generation,update-events,cycle-events,test,manual}` (POST)
- Local runner: `scripts/local-cron.js` (node-cron)
- Status API: `/api/scheduler/status?universe_id=...` (GET; bearer)
- UI (player): `HeaderHUD` shows Next Turn only (cron-synced)
- UI (admin): `app/admin/cron-status` shows full timers via `TurnCounter`

## Intervals (defaults)
- Turn generation: every 3 minutes
- Update events: every 15 minutes
- Cycle events: every 6 hours

All configurable per universe in `public.universe_settings`:
- `turn_generation_interval_minutes`
- `update_interval_minutes`
- `cycle_interval_minutes`
- `last_turn_generation`, `last_update_event`, `last_cycle_event`

## Status Endpoint
- RPC `get_next_scheduled_events(p_universe_id uuid)` computes timestamps and seconds-until for the three events.
- Route: `app/api/scheduler/status/route.ts`
- Response includes `time_until_turn_generation_seconds` used by UI countdowns.

## Security
- Cron endpoints require `x-cron: CRON_SECRET` (or `x-vercel-cron`).
- Local runner reads `CRON_SECRET` and `NEXT_PUBLIC_SITE_URL` from env.

## UI Wiring
- Header (`HeaderHUD`): counts down using `/api/scheduler/status`; falls back to a local 60s-per-turn timer if status is unavailable.
- Admin page (`/admin/cron-status`): Universe selector + `TurnCounter` for live cron-driven timers.

## Running Locally
- Start app: `npm run dev`
- Start cron: `npm run cron`
- Test endpoints: `npm run cron:test`

## Change Notes
- 2025‑09‑18: Header wired to scheduler; TurnCounter moved to Admin; cron runner authorized via `.env.local`.
