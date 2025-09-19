# API Index — BNT‑Redux

Auth legend: (P) public, (A) auth required, (X) cron/admin key.

## Player
- (A) GET `/api/universes` — list universes (public in code; shown here under Player)
- (A) GET `/api/me?universe_id=`
- (A) GET `/api/sector?number=&universe_id=`
- (A) POST `/api/move`
- (A) POST `/api/hyperspace`
- (A) POST `/api/trade`
- (A) POST `/api/trade/auto`
- (A) GET `/api/ship`
- (A) POST `/api/ship/upgrade`
- (A) POST `/api/ship/rename`
- (A) POST `/api/planet/{claim|store|withdraw}`
- (A) GET `/api/planet/list`
- (A) POST `/api/favorite`
- (A) GET `/api/favorites`
- (A) POST `/api/scan/{single|full}`
- (A) GET `/api/map`

## Scheduler
- (A) GET `/api/scheduler/status?universe_id=`
- (X) POST `/api/cron/test`
- (X) POST `/api/cron/turn-generation`
- (X) POST `/api/cron/update-events`
- (X) POST `/api/cron/cycle-events`
- (X) POST `/api/cron/manual`

## Admin
- (A admin) GET/POST `/api/admin/universes`
- (A admin) DELETE `/api/admin/universes/[id]`
- (A admin) GET `/api/admin/universe-settings`
- (A admin) PUT `/api/admin/universe-settings`
- (A admin) GET `/api/admin/mines`

Notes:
- All (A) require `Authorization: Bearer <supabase_access_token>`.
- Admin checks use RPC `is_user_admin`.
