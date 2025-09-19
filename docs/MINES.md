# Mine System — BNT‑Redux

Status: Implemented core UI + APIs; SQL functions present (see /sql/097_mine_system*.sql) with corrected constraints.

## Concepts
- Mines can be deployed in sectors; trigger on hostile entry based on tech thresholds.
- Attributes: `mine_type`, `damage_potential`, `tech_level_required`, `is_active`.

## Data
- Table: `mines` (universe_id, sector_id, owner_player_id, fields above)
- Related: `sectors(number)`, `players(id, universe_id)`, `ships(hull, shields, hull_lvl, shield_lvl)`

## APIs
- Admin:
  - `GET /api/admin/mines?universe_id=...` (bearer + admin)
- Player (planned/partial):
  - `POST /api/mines/deploy` `{ sectorNumber, type }`
  - `GET /api/sector/mines?number=...` — visibility rules TBD

## UI
- `MineIndicator` shows presence/risk in current sector.
- `MineDeployer` enables deployment when criteria met (torpedoes > 0, etc.).

## Triggering & Damage (planned)
- On sector entry, compare player tech vs `tech_level_required` to determine detonation chance.
- Apply damage to shields then hull; record event in logs/news.

## References
- SQL specs: `/sql/097_mine_system.sql`, `/sql/097_mine_system_corrected.sql`
- API routes scaffolded under `/app/api/mines` and `/app/api/sector/mines`
