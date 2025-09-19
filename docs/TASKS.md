# TASKS (Minimal)

## Current Focus
- Sync UI with cron (done): Header countdown uses scheduler; admin cron page hosts timers.
- Document key systems (done): SCHEDULER, MOVEMENT, MINES, ADMIN, API_INDEX.
- Next: Player‑facing read‑only Settings page mirroring classic BNT table (no timers).

## T01 — Minimal Bootstrap
- Fresh Next.js (App Router, TS), add @supabase/supabase-js and swr.
- Pages: /login (magic link), /game (protected), / (redirect).
- /lib/supabase.ts helper.
- Update CONTEXT (Stack, Env Vars).

## T02 — Minimal Schema & Seed (SQL only)
- /sql/001_init.sql with players, universes, sectors(number), warps, ports, ships, inventories, trades.
- /scripts/seed.mjs to create 500 sectors, 1–3 warps/sector (bidirectional), ~10% ports.

## T03 — Minimal API
- GET /api/me, GET /api/sector?number=
- POST /api/move, POST /api/trade (transaction), POST /api/cron/regen (x-cron).
- Validate adjacency in move.

## T04 — Minimal UI
- /game sector view, warp buttons (Move), Buy/Sell form, top bar (turns/credits) via swr.

## T05 — Deploy
- vercel.json cron → /api/cron/regen with x-cron header; set envs.

(Always update /docs/CONTEXT.md Change Log after each task.)
