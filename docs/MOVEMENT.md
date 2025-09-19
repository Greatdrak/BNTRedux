# Movement & Hyperspace — BNT‑Redux

## Movement Modes
- Realspace: move along warp links (1 turn per hop)
- Hyperspace: jump by sector number

### Hyperspace Turn Cost
```
distance = |from - to|
turn_cost = max(1, ceil(distance / max(1, engine_lvl)))
```

API:
- `POST /api/move` `{ toSectorNumber }` — validates adjacency (realspace)
- `POST /api/hyperspace` `{ toSectorNumber }` — applies hyperspace cost

Data:
- Player `turns`, `current_sector_number`
- Ship `engine_lvl`
- Tables: `sectors`, `warps`

UX:
- Left panel Move buttons for warps
- Hyperspace panel with target input and computed cost

Future hooks:
- Fuel consumption
- Interdiction/ambush
- Waypoint queues and autopilot
