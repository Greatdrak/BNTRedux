# Scheduler & Cron — BNT‑Redux

Purpose: Single source of truth for game timing (turns, ticks, events) and how UI reflects it.

## Components
- **Heartbeat System**: `/api/cron/heartbeat` - Main coordinator that runs all scheduled events
- **Individual Endpoints**: `/api/cron/{turn-generation,update-events,cycle-events,test,manual}` (POST)
- **Local runner**: `scripts/local-cron.js` (node-cron)
- **Status API**: `/api/scheduler/status?universe_id=...` (GET; bearer)
- **UI (player)**: `HeaderHUD` shows Next Turn only (cron-synced)
- **UI (admin)**: `app/admin/cron-status` shows full timers via `TurnCounter`

## Cron Jobs Overview

The system uses a **heartbeat-based approach** where `/api/cron/heartbeat` checks all scheduled events and runs them if they're due. This provides better coordination and logging than individual cron endpoints.

### Core Game Events

#### 1. **Turn Generation** 
- **Purpose**: Adds turns to all players in a universe
- **Default Interval**: 3 minutes
- **RPC Function**: `generate_turns_for_universe(p_universe_id, p_turns_to_add)`
- **What it does**: Gives players 4 turns (configurable) up to their maximum accumulated turns
- **Settings**: `turns_generation_interval_minutes`, `turns_per_generation`

#### 2. **Port Regeneration**
- **Purpose**: Updates port stock dynamics and prices
- **Default Interval**: 15 minutes  
- **RPC Function**: `update_port_stock_dynamics(p_universe_id)`
- **What it does**: Regenerates port resources, decays overstocked resources, adjusts prices
- **Settings**: `port_regeneration_interval_minutes`

#### 3. **Planet Production**
- **Purpose**: Processes planet resource production and colonist growth
- **Default Interval**: 30 minutes
- **RPC Function**: `run_planet_production(p_universe_id)`
- **What it does**: Produces resources, grows colonists, generates interest on planet credits
- **Settings**: `planet_production_interval_minutes`

#### 4. **Rankings Update**
- **Purpose**: Updates player rankings and scores
- **Default Interval**: 1 hour
- **RPC Function**: `update_universe_rankings(p_universe_id)`
- **What it does**: Calculates and updates player scores based on assets, territory, military power
- **Settings**: `rankings_generation_interval_minutes`

### AI and Automation

#### 5. **AI Player Actions**
- **Purpose**: Runs AI player decision-making and actions
- **Default Interval**: 5 minutes
- **RPC Function**: `cron_run_ai_actions(p_universe_id)`
- **What it does**: AI players make decisions, move, trade, claim planets, upgrade ships
- **Settings**: `ai_player_actions_interval_minutes`


### Economic Systems

#### 6. **IGB Interest**
- **Purpose**: Applies Inter-Galactic Bank interest
- **Default Interval**: 1 hour
- **RPC Function**: `apply_igb_interest(p_universe_id)`
- **What it does**: Applies interest to IGB accounts and loans
- **Settings**: `igb_interest_accumulation_interval_minutes`

### Military and Defense

#### 7. **Defenses Check**
- **Purpose**: Runs defense system checks
- **Default Interval**: 2 hours
- **RPC Function**: `run_defenses_checks(p_universe_id)`
- **What it does**: Checks and updates sector defense systems
- **Settings**: `defenses_check_interval_minutes`

#### 8. **Sector Defenses Degrade**
- **Purpose**: Degrades sector defense systems over time
- **Default Interval**: 6 hours
- **RPC Function**: `degrade_sector_defenses(p_universe_id)`
- **What it does**: Reduces sector defense levels if not maintained
- **Settings**: `sector_defenses_degrade_interval_minutes`

#### 9. **Ships Tow from Fed**
- **Purpose**: Tows ships from federation sectors
- **Default Interval**: 1 hour
- **RPC Function**: `tow_ships_from_fed(p_universe_id)`
- **What it does**: Moves ships out of federation-controlled sectors
- **Settings**: `ships_tow_from_fed_sectors_interval_minutes`

### Special Events

#### 10. **News Generation**
- **Purpose**: Generates universe news and events
- **Default Interval**: 4 hours
- **RPC Function**: `generate_universe_news(p_universe_id)`
- **What it does**: Creates news events, announcements, and universe-wide events
- **Settings**: `news_generation_interval_minutes`

#### 11. **Planetary Apocalypse**
- **Purpose**: Runs apocalypse events
- **Default Interval**: 24 hours
- **RPC Function**: `run_apocalypse_tick(p_universe_id)`
- **What it does**: Triggers catastrophic events that can destroy planets
- **Settings**: `planetary_apocalypse_interval_minutes`

## Configuration

All intervals are configurable per universe in `public.universe_settings`:
- `turns_generation_interval_minutes` (default: 3)
- `port_regeneration_interval_minutes` (default: 15)
- `planet_production_interval_minutes` (default: 30)
- `rankings_generation_interval_minutes` (default: 60)
- `ai_player_actions_interval_minutes` (default: 5)
- `igb_interest_accumulation_interval_minutes` (default: 60)
- `defenses_check_interval_minutes` (default: 120)
- `sector_defenses_degrade_interval_minutes` (default: 360)
- `ships_tow_from_fed_sectors_interval_minutes` (default: 60)
- `news_generation_interval_minutes` (default: 240)
- `planetary_apocalypse_interval_minutes` (default: 1440)

Each event also has a corresponding `last_*_event` timestamp field to track when it last ran.

## Heartbeat System

The heartbeat system (`/api/cron/heartbeat`) is the main coordinator that:

1. **Checks all universes** for scheduled events
2. **Determines which events are due** based on intervals and last run times
3. **Executes due events** by calling their respective RPC functions
4. **Logs all activity** to the `cron_logs` table for monitoring
5. **Updates timestamps** when events complete successfully
6. **Returns detailed results** including execution times and statistics

### Event Execution Flow
```
Heartbeat Trigger → Check Universe Settings → Determine Due Events → Execute RPC Functions → Log Results → Update Timestamps
```

### Logging and Monitoring
- All events are logged to `cron_logs` table with execution details
- Success/failure status tracked for each event
- Execution times measured and recorded
- Detailed metadata captured for debugging

## Status Endpoint
- RPC `get_next_scheduled_events(p_universe_id uuid)` computes timestamps and seconds-until for scheduled events
- Route: `app/api/scheduler/status/route.ts`
- Response includes `time_until_turn_generation_seconds` used by UI countdowns

## Security
- Cron endpoints require `x-cron: CRON_SECRET` (or `x-vercel-cron`)
- Local runner reads `CRON_SECRET` and `NEXT_PUBLIC_SITE_URL` from env
- Heartbeat endpoint validates authorization before processing any events

## UI Wiring
- **Header (`HeaderHUD`)**: counts down using `/api/scheduler/status`; falls back to a local 60s-per-turn timer if status is unavailable
- **Admin page (`/admin/cron-status`)**: Universe selector + `TurnCounter` for live cron-driven timers
- **Cron logs**: Available in admin panel for monitoring event execution

## Running Locally
- **Start app**: `npm run dev`
- **Start cron**: `npm run cron` (runs heartbeat every minute)
- **Test endpoints**: `npm run cron:test`
- **Manual trigger**: Use `/api/cron/manual` for testing specific events

## Event Dependencies
Some events have logical dependencies:
- **Turn Generation** should run before **AI Player Actions** (AI needs turns to act)
- **Planet Production** should run before **Rankings Update** (affects player scores)
- **Port Regeneration** affects trading opportunities for AI players

## Error Handling
- Failed events are logged with error details
- Events continue to run even if previous events failed
- Heartbeat system is resilient to individual event failures
- Admin can manually trigger failed events via `/api/cron/manual`

## Change Notes
- **2025‑09‑18**: Header wired to scheduler; TurnCounter moved to Admin; cron runner authorized via `.env.local`
- **2025‑09‑28**: Added comprehensive heartbeat system with 11 scheduled events; improved logging and monitoring
- **2025‑09‑28**: Removed legacy Xenobes Play system; now using enhanced AI system exclusively
