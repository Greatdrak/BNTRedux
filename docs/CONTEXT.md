# BNT-Redux — CONTEXT (Single Source of Truth)

**How to use this file**
- Read this first before any task.
- After any change, append 3–6 lines under **Change Log** summarizing:
  - What changed
  - Endpoints/tables touched
  - Any env var added
- Keep this file under one page where possible.

[Docs map] See also: `docs/API_INDEX.md`, `docs/TRADING.md`, `docs/SCHEDULER.md`, `docs/MOVEMENT.md`, `docs/MINES.md`, `docs/ADMIN.md`.

## Stack & Versions (planned)
- App: Next.js (App Router) + React + TypeScript
- Data: Supabase Postgres via supabase-js
- State: SWR
- Styling: CSS Modules
- Jobs: Vercel Cron → protected API route

## Env Vars (to be set in Vercel/Supabase; mirror locally)
- NEXT_PUBLIC_SUPABASE_URL=
- NEXT_PUBLIC_SUPABASE_ANON_KEY=
- SUPABASE_SERVICE_ROLE_KEY=      # server-only
- DATABASE_URL=                   # optional for seed script
- CRON_SECRET=                    # used by /api/cron/regen
- SENTRY_DSN=                     # optional

## Directories (target, not yet created)
- /app/ (Next.js)
- /app/api/{me,sector,move,trade,cron/regen}/route.ts
- /lib/supabase.ts
- /sql/ (raw SQL)
- /scripts/seed.mjs
- /docs/CONTEXT.md

## Tables (with purposes)
- universes: Game instances (Alpha universe with 501 sectors)
- sectors: Individual locations within universes (numbered 0-500, with sector 0 being Sol Hub)
- warps: Bidirectional connections between sectors (1-3 per sector)
- ports: Trading locations (~10% of sectors have ports with stock/prices)
- players: Game users linked to Supabase auth (credits, turns, current_sector)
- ships: Player vessels (hull, hull_max, hull_lvl, shield, shield_max, shield_lvl, cargo, fighters, torpedoes, engine_lvl, comp_lvl, sensor_lvl, name)
- inventories: Player cargo holds (ore, organics, goods, energy)
- trades: Transaction history (buy/sell actions at ports)
- combats: Battle records (attacker/defender outcomes)
- visited: Player exploration history (sector_id, first_seen, last_seen)
- scans: Player scan records (sector_id, mode: single/full, scanned_at)
- favorites: Player bookmarked sectors (sector_id)
- planets: Player-owned colonies (sector_id, owner_player_id, name, resource stocks, hull/shield)

## API Endpoints (with request/response shapes)

### GET /api/universes
- **Auth:** None (public endpoint)
- **Response:** `{ ok: true, universes: [{ id, name, created_at, sector_count, port_count, planet_count, player_count }] }`
- **Behavior:** Lists all available universes for player selection

### GET /api/me?universe_id=<uuid>
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Query:** `universe_id` (optional, defaults to first available universe)
- **Response:** `{ player: { id, handle, credits, turns, turn_cap (from universe_settings.max_accumulated_turns), last_turn_ts, current_sector, current_sector_number }, ship: { name, hull, hull_max, hull_lvl, shield, shield_max, shield_lvl, cargo, fighters, torpedoes, engine_lvl, comp_lvl, sensor_lvl }, inventory: { ore, organics, goods, energy } }`
- **Behavior:** Creates player at sector #0 (Sol Hub) in specified universe if first time, returns existing player data otherwise

### POST /api/register
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ universe_id: string, handle: string }`
- **Response:** `{ ok: true, player: { id, handle, universe_id, universe_name, credits, turns, turn_cap (from universe_settings.max_accumulated_turns), current_sector, current_sector_number }, ship: { ... }, inventory: { ... } }` or `{ error: { code, message } }`
- **Behavior:** Creates new player in specified universe with given handle

### GET /api/sector?number=<int>&universe_id=<uuid>
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Query:** `number` (0-500, where 0 is Sol Hub), `universe_id` (optional)
- **Response:** `{ sector: { number }, warps: number[], port: { id, kind, stock: { ore, organics, goods, energy }, prices: { ore, organics, goods, energy } } | null, planets: [{ id, name, owner: boolean }] }`

### POST /api/move
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ toSectorNumber: number }`
- **Response:** `{ ok: true, player: { current_sector, turns } }` or `{ error: { code, message } }`
- **Behavior:** Validates adjacency and turns ≥ 1, decrements turns

### POST /api/trade
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ portId: string, action: 'buy'|'sell', resource: 'ore'|'organics'|'goods'|'energy', qty: number }`
- **Response:** `{ ok: true, player: { credits, inventory }, port: { stock, prices } }` or `{ error: { code, message } }`
- **Behavior:** Validates co-location, balances, logs trade

### POST /api/trade/auto
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ portId: string }`
- **Response:** `{ ok: true, sold: { ore, organics, goods, energy }, bought: { resource: 'ore'|'organics'|'goods'|'energy', qty: number }, credits: number, inventory_after: { ... }, port_stock_after: { ... } }` or `{ error: { code, message } }`
- **Behavior:** Atomic auto-sell of non-native at 1.10×, then auto-buy native at 0.90× with `Q = min(stock, floor(credits'/price), cargoFree')`.

### POST /api/hyperspace
- **Auth:** Required (Bearer token)
- **Body:** `{ toSectorNumber: number }`
- **Response:** `{ ok: true, player: { current_sector_number, turns } }` or `{ error }`
- **Behavior:** Direct jump by sector number; turn cost = `ceil(|Δ| / max(1,engineLvl))`, min 1; upserts `visited`.

### POST /api/engine/upgrade
- **Auth:** Required (Bearer token)
- **Body:** `{}`
- **Response:** `{ ok:true, credits, ship: { engine_lvl } }` or `{ error }`
- **Behavior:** Only at Special ports; costNext = `500 * (engine_lvl + 1)`.

### POST /api/favorite
- **Auth:** Required (Bearer token)
- **Body:** `{ sectorNumber: number, flag: boolean }`
- **Response:** `{ ok:true, favorites: number[] }`

### GET /api/favorites
- **Auth:** Required (Bearer token)
- **Response:** `{ favorites: number[] }`

### POST /api/scan/single
- **Auth:** Required (Bearer token)
- **Body:** `{ sectorNumber: number }`
- **Response:** `{ ok:true, sector: { number, port: { kind } | null } }` or `{ error }`
- **Behavior:** Costs 1 turn; upserts `scans` with `mode='single'`.

### POST /api/scan/full
- **Auth:** Required (Bearer token)
- **Body:** `{ radius: number } // default 5, clamp 1..10`
- **Response:** `{ ok:true, sectors: { number, port: { kind } | null }[] }` or `{ error }`
- **Behavior:** Costs `radius` turns; upserts `scans` with `mode='full'` for numeric band.

### GET /api/map?center=<num>&radius=<num>
- **Auth:** Required (Bearer token)
- **Response:** `{ sectors: { number, visited: boolean, scanned: boolean, portKind: 'ore'|'organics'|'goods'|'energy'|'special'|null }[] }`

### POST /api/cron/regen
- **Auth:** Header `x-cron: CRON_SECRET` OR `x-vercel-cron`
- **Response:** `{ ok: true, updatedCount: number }`
- **Behavior:** Adds +1 turn to players with turns < max_accumulated_turns (from universe_settings)

### POST /api/upgrade
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ item: 'fighters'|'torpedoes', qty: number }`
- **Response:** `{ ok: true, credits: number, ship: { fighters: number, torpedoes: number } }` or `{ error: { code, message } }`
- **Behavior:** Purchases combat equipment (fighters: 50 cr each, torpedoes: 120 cr each)

### POST /api/repair
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ hull: number }` (hull points to repair)
- **Response:** `{ ok: true, credits: number, ship: { hull: number } }` or `{ error: { code, message } }`
- **Behavior:** Repairs ship hull (2 cr per point, max hull: 100)

### POST /api/planet/claim
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ sectorNumber: number, name?: string }` (name defaults to 'Colony')
- **Response:** `{ ok: true, planet_id: string, name: string, sector_number: number, credits: number, turns: number }` or `{ error: { code, message } }`
- **Behavior:** Claims planet in current sector (costs: 10,000 credits + 5 turns)

### POST /api/planet/store
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ planetId: string, resource: 'ore'|'organics'|'goods'|'energy', qty: number }`
- **Response:** `{ ok: true, player: { inventory }, planet: { stock } }` or `{ error: { code, message } }`
- **Behavior:** Stores resources from player inventory to owned planet

### POST /api/planet/withdraw
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ planetId: string, resource: 'ore'|'organics'|'goods'|'energy', qty: number }`
- **Response:** `{ ok: true, player: { inventory }, planet: { stock } }` or `{ error: { code, message } }`
- **Behavior:** Withdraws resources from owned planet to player inventory

### GET /api/planet/list
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Response:** `{ planets: [{ id: string, name: string, sectorNumber: number, stock: { ore, organics, goods, energy } }] }`
- **Behavior:** Returns list of player's owned planets with stock summary

### GET /api/ship
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Response:** `{ name, hull, hull_max, hull_lvl, shield, shield_max, shield_lvl, engine_lvl, comp_lvl, sensor_lvl, cargo, fighters, torpedoes, atSpecialPort: boolean }`
- **Behavior:** Returns full ship attributes and whether player is at a special port

### POST /api/ship/upgrade
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ attr: 'engine'|'computer'|'sensors'|'shields'|'hull' }`
- **Response:** `{ ok: true, credits: number, ship: { ...all attributes } }` or `{ error: { code, message } }`
- **Behavior:** Upgrades ship attribute; only available at special ports; costs vary by attribute and current level

### POST /api/ship/rename
- **Auth:** Required (Bearer token)
- **Headers:** `Authorization: Bearer <supabase_access_token>`
- **Body:** `{ name: string }`
- **Response:** `{ ok: true, name: string }` or `{ error: { code, message } }`
- **Behavior:** Renames ship; validates length (≤32 chars) and sanitizes input

## Auth Bridge
Client forwards Supabase access token via `Authorization: Bearer <token>` header. Server verifies token using Supabase admin client, then uses service role for gameplay operations. Stateless authentication without cookies.

**Manual Testing:**
```javascript
// Browser console after login:
const { data: { session } } = await window.supabase.auth.getSession()
console.log(session.access_token)

// Then test with curl:
curl -H "Authorization: Bearer <token>" http://localhost:3000/api/me
```

## UI Components & API Integration
- **HeaderHUD**: Uses SWR to fetch `/api/me`, displays handle/sector/turns/credits with refresh button and turn countdown timer
- **SectorPanel**: Fetches `/api/sector?number=<current>` via SWR, shows warps as move buttons
- **PortPanel**: Displays port stock/prices table when port exists in current sector
- **ActionsPanel**: Trade form (buy/sell) with resource selection, quantity input, Max Buy/Sell helpers, and live trade preview (buy uses 0.90× price and cargo limit; sell uses 1.10×)
- **PortOverlay**: Single stacked overlay with header, 2×2 stock grid, segmented Buy/Sell/Trade(auto); auto-trade preview and submission; keeps overlay open, revalidates `/api/me` + `/api/sector`.
- **InventoryPanel**: Live inventory display (🪨 Ore, 🌿 Organics, 📦 Goods, ⚡ Energy) with quantities
- **StatusBar**: Single-line status messages for loading/error/success feedback
- **Move Action**: POST `/api/move` with bearer token, revalidates both `/api/me` and `/api/sector` on success
- **Trade Action**: POST `/api/trade` with bearer token, revalidates data on success for live inventory updates

## UI (Retro Skin)
- Three-column `GameShell`: left commands stack, center sector viewport, right ship/cargo/nav stack. Collapses right column below center under 1100px.
- Theme tokens in `app/game/retro-theme.module.css` with starfield background and neon purple/teal palette. Panels use bevelled `.panel`, headers use smallcaps `.panelTitle`.
- Bracketed action links via `.linkBracket`/`.btnBracket` used across controls (e.g., `[scan]`, `[jump]`).
- Center viewport emphasizes sector number, inline port line, optional floating planet orbs, and minimal ships line. Status bar remains at bottom.
- Overlays (Map/Port) inherit theme and focus styles; ESC closes, Enter submits.
 - Overlays (Map/Port) inherit theme and focus styles; ESC closes, Enter submits.
 - [T09] Trading Finalization: constants/prices, RPCs, auto-trade, stacked overlay
   - Updated: /sql/006_rpc_trade_by_type.sql (cargo cap; standardized error codes)
   - Added/Updated: /sql/013_rpc_trade_auto.sql (atomic auto-sell then buy with 0-turn cost)
   - API: /api/trade and /api/trade/auto return { error: { code, message } } and success snapshots
   - UI: PortOverlay stacked panel; ActionsPanel uses 0.90/1.10 multipliers and cargo in Max Buy
   - Revalidation: Successful trades refresh /api/me and /api/sector

## UX Behavior
- **Turn Countdown**: Client-side countdown timer shows "Next turn in MM:SS" with progress bar, triggers silent SWR refresh when reaching 0
- **Max Buy/Sell**: Calculates maximum affordable quantities based on credits, port stock, and remaining cargo capacity
- **Trade Preview**: Live calculation of total cost and after-balance, disables submit if trade would exceed limits
- **Number Formatting**: Credits formatted with commas (1,234), prices to 2 decimals with "cr" unit label
- **Keyboard Shortcuts**: Enter submits trade form, Escape resets quantity to 1

### Navigation & Scanning
- Backbone warps: guaranteed 1↔2↔…↔N links per universe in addition to random warps.
- Hyperspace cost: `cost = max(1, ceil(|current-target| / max(1, engineLvl)))` turns.
- Engine upgrade: only at Special ports; `costNext = 500 * (engineLvl + 1)`.
- Scans: single = 1 turn; full scan = `radius` turns (1..10). Both persist to `scans`.
- Map API returns visited/scanned flags and port kinds for a numeric band.

## Gameplay constants (tentative)
- Turn regen: +1 per minute up to max_accumulated_turns (from universe_settings)
- max_accumulated_turns: 5000 (default, configurable per universe)
- Seed parameters: sector_count=501 (0-500), warp_degree=1–3, port_density≈10%, sector 0=Sol Hub with special port
- Equipment pricing: fighters=50 cr, torpedoes=120 cr
- Hull repair: 2 cr per point, max hull=100
- Planet claim: 10,000 credits + 5 turns per planet
- Hyperspace band default radius: 10 (map); full scan default radius: 5 (clamped 1..10)

## Working Rules (minimal)
- Read this CONTEXT before coding.
- After any change: update **Change Log** with 3–6 lines.
- Don't add new dependencies without explicit instruction.

## Open TODOs (max 3)
1) —
2) —
3) —

## Change Log
- [init] Created CONTEXT and minimal rules (docs-only guardrails).
- [Multi-Universe] Implemented multi-universe player system with universe selection
  - Added: Landing page with universe selection and registration flow
  - Added: /api/universes (public endpoint for universe listing)
  - Added: /api/register (player creation in specific universe)
  - Updated: /api/me and /api/sector to accept universe_id parameter
  - Updated: Login page with universe selection and registration tabs
  - Behavior: Players can now join different universes, each with separate characters
- [T01] Minimal Bootstrap: Next.js App Router + TypeScript + Supabase Auth
  - Added: package.json, next.config.js, tsconfig.json
  - Added: /lib/supabase-client.ts (browser client helper)
  - Added: /app/layout.tsx, /app/page.tsx (redirect logic)
  - Added: /app/login/page.tsx (magic link auth with CSS Modules)
  - Added: /app/game/page.tsx (authenticated shell with HUD)
  - Uses: NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY
- [T02] Schema & Seed: Complete database structure with Alpha universe
  - Added: /sql/001_init.sql (9 tables, constraints, indexes)
  - Added: /sql/002_seed.sql (500 sectors, bidirectional warps, ~50 ports)
  - Tables: universes, sectors, warps, ports, players, ships, inventories, trades, combats
  - Seed: 1 universe, 500 sectors, 1-3 warps/sector, ~10% ports with stock/prices
- [T03] Minimal API: Server-authoritative gameplay routes with RPC functions
  - Added: /lib/supabase-server.ts (service role client + session auth)
  - Added: /sql/003_rpc.sql (game_move, game_trade atomic functions)
  - Added: /app/api/{me,sector,move,trade,cron/regen}/route.ts (5 endpoints)
  - Uses: SUPABASE_SERVICE_ROLE_KEY, CRON_SECRET
- [T03.1] Auth Bridge: Bearer token authentication for stateless API
  - Added: /lib/auth-helper.ts (bearer token verification)
  - Updated: /api/{me,move,trade} routes to use Authorization header
  - Updated: /app/game/page.tsx to include bearer tokens in API calls
  - Auth: Client forwards access_token, server verifies via admin client
- [T04] UI Wiring: Complete game interface with SWR and live API integration
  - Updated: /app/game/page.tsx with SWR hooks for /api/me and /api/sector
  - Added: HUD with refresh control, sector panel with warp buttons, trade form
  - Added: Move action (POST /api/move) with loading states and revalidation
  - Added: Trade form (POST /api/trade) with port stock/prices display
  - Added: Inventory display and error handling for failed operations
- [T04.1] UI Touch-Up: Sleek space-trading console with modular components and live inventory
  - Updated: /app/globals.css with dark space theme CSS variables and starfield background
  - Added: Modular components (HeaderHUD, SectorPanel, PortPanel, ActionsPanel, InventoryPanel, StatusBar)
  - Added: Live inventory updates after trades via SWR revalidation
  - Added: Status messages for trade/move feedback with success/error states
  - Layout: Two-column grid with top HUD and bottom status bar
- [T04.2] HUD Polish: Turn countdown, number formatting, and trade UX helpers
  - Updated: /api/me to include last_turn_ts field for countdown calculation
  - Added: Turn countdown timer with progress bar in HeaderHUD, triggers silent refresh at 0
  - Added: Intl.NumberFormat for credits (1,234) and prices (12.34 cr)
  - Added: Max Buy/Sell buttons with cargo capacity and credit limit calculations
  - Added: Live trade preview showing total cost and after-balance
  - Added: Keyboard shortcuts (Enter/Escape) for trade form interaction
- [T05] Equipment & Repair: Combat equipment purchase and hull repair system
  - Added: /sql/004_rpc_upgrades.sql with game_upgrade and game_repair RPC functions
  - Added: /app/api/upgrade/route.ts and /app/api/repair/route.ts with bearer token auth
  - Added: EquipmentPanel component for purchasing fighters/torpedoes and repairing hull
  - Added: Live cost previews and validation for equipment purchases and repairs
  - Pricing: fighters=50 cr, torpedoes=120 cr, hull repair=2 cr per point (max 100)
  - Integration: EquipmentPanel renders only at ports, updates ship stats via SWR revalidation
 - [T06] Port Types & Trade Rules + Overlay (server groundwork)
  - Added: /sql/005_port_types.sql to assign `ports.kind`; updated trade RPC to enforce type rules via /sql/006_rpc_trade_by_type.sql (sell own @0.90x, buy others @1.10x; Special = no commodity trading)
  - API: gated /api/upgrade and /api/repair to Special ports; /api/sector now includes `port.kind`
 - [T07] Navigation & Scanning (phase 1)
  - Added: /sql/007_nav_backbone_and_exploration.sql (backbone warps; tables visited/scans/favorites/planets)
  - Added: /sql/008_rpc_nav_and_engine.sql (game_hyperspace, game_engine_upgrade)
  - API: /api/hyperspace, /api/engine/upgrade, /api/favorite, /api/favorites, /api/scan/single, /api/scan/full, /api/map
  - UI: engine level in HUD; hyperspace panel; favorite toggle; map/scans server endpoints ready
  - Run once in Supabase: 005_port_types.sql, 006_rpc_trade_by_type.sql, 007_nav_backbone_and_exploration.sql, 008_rpc_nav_and_engine.sql
- [T08] Planets (Phase 1): Planet generation, free claiming, resource storage, and map integration
  - Added: /sql/010_planets_schema.sql (planets table with unique sector constraint)
  - Added: /sql/011_rpc_planets.sql (game_planet_claim, game_planet_store, game_planet_withdraw RPCs)
  - Added: /app/api/planet/{claim,store,withdraw,list}/route.ts with bearer token auth
  - Updated: /api/sector to include planet data (id, name, owner boolean)
  - Updated: /api/map to include planet badges (hasPlanet, planetOwned flags)
  - Added: PlanetOverlay and ClaimPlanetModal UI components with store/withdraw forms
  - Added: Planet buttons in sector view and planet badges on map overlay
  - Generation: planets are pre-generated unowned by 012_generate_planets.sql; claiming is free
  - One planet per sector maximum; later phases may add combat/transfer mechanics
  - Run once in Supabase: 010_planets_schema.sql, 011_rpc_planets.sql, 012_generate_planets.sql
 - [T07.2] Retro BNT UI skin + 3-column layout + themed overlays
  - Added: `app/game/retro-theme.module.css` (tokens, starfield, bracket links) and `GameShell` layout
  - Updated: `/app/game/page.tsx` markup to left/center/right composition with inline port and floating planets
  - Restyled commands, cargo, hyperspace, and warp lists to neon bracket style; preserved all API logic
  - Overlays themed and keyboard-accessible (ESC to close, Enter submits)
- [T09] Ship Details & Special-Port-Gated Upgrades
  - Added: `/sql/017_ship_attributes.sql` (hull_max, shield_lvl, shield_max, comp_lvl, sensor_lvl, name columns)
  - Added: `/sql/018_rpc_ship_upgrades.sql` (game_ship_upgrade, game_ship_rename RPC functions)
  - Added: `/app/api/ship`, `/app/api/ship/upgrade`, `/app/api/ship/rename` endpoints with bearer auth
  - Added: `/app/ship/page.tsx` with SVG ship art, stats grid, and upgrade interface
  - Added: Ship command to left sidebar navigation; upgrades gated to special ports only
  - Cost formulas: engine=500×(lvl+1), computer/sensors=400×(lvl+1), shields=300×(lvl+1), hull=2000×(lvl+1)
  - Hull system: hull_lvl controls cargo capacity (Lv1=1000, Lv2=3500, Lv3+=1000×lvl^1.8); hull_max=100×hull_lvl
- [T10] Sol Hub - Sector 0 Universe Update
  - Added: `/sql/019_sol_hub_sector_zero.sql` (creates sector 0 with special port, shifts existing sectors 1→2, 2→3, etc.)
  - Updated: Universe now spans sectors 0-500 (501 total); sector 0 is "Sol Hub" with guaranteed special port
  - Updated: Player creation starts at sector 0 instead of sector 1; all existing players moved to sector 0
  - Updated: API endpoints (/api/sector, /api/map) to handle sector range 0-500
  - Updated: Documentation to reflect new sector numbering and Sol Hub concept
- [2025‑09‑18] Scheduler/UI consolidation + new docs
  - Updated: HeaderHUD to use `/api/scheduler/status`; moved TurnCounter to `/admin/cron-status`
  - Added: `docs/SCHEDULER.md`, `docs/MOVEMENT.md`, `docs/MINES.md`, `docs/ADMIN.md`, `docs/API_INDEX.md`
  - Cron: local runner reads `.env.local` for `CRON_SECRET`; added universe selector on admin cron page
