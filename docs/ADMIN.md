# Admin Tools — BNT‑Redux

## Pages
- `/admin` — Universe management (list/create/destroy)
- `/admin/cron-status` — Cron status, universe selector, live timers (TurnCounter), manual tests
- `/admin/universe-settings` — Per‑universe gameplay settings (scheduler intervals, limits)

## APIs (admin‑protected)
- `GET /api/admin/universes` — list universes
- `POST /api/admin/universes` — create universe
- `DELETE /api/admin/universes/[id]` — destroy universe
- `GET /api/admin/universe-settings?universe_id=...`
- `PUT /api/admin/universe-settings` — update settings
- `GET /api/admin/mines?universe_id=...` — inspect mines

Auth: Bearer token + RPC `is_user_admin(p_user_id)` must be true.

## Notes
- Cron endpoints require `x-cron` header; admin pages do not expose secrets.
- Universe selector in cron status page wires timers to selected universe.
