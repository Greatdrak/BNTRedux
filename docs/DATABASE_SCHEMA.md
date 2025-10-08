# Database Schema Documentation

## Overview
This document provides a comprehensive overview of the BNT Redux database schema, including all tables, relationships, functions, and constraints.

## Core Tables

### `universes`
The top-level container for game instances.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `name` | TEXT | Universe name (e.g., "Alpha", "Gamma") |
| `sector_count` | INTEGER | Total number of sectors in this universe |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `universes_pkey` PRIMARY KEY (`id`)
- `universes_name_key` UNIQUE (`name`)

### `sectors`
Individual sectors within a universe.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `universe_id` | UUID | Foreign key to `universes.id` |
| `number` | INTEGER | Sector number (0 to sector_count-1) |
| `created_at` | TIMESTAMP | Creation timestamp |

**Constraints:**
- `sectors_pkey` PRIMARY KEY (`id`)
- `sectors_universe_id_number_key` UNIQUE (`universe_id`, `number`)

### `warps`
Warp gate connections between sectors.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `universe_id` | UUID | Foreign key to `universes.id` |
| `from_sector_id` | UUID | Foreign key to `sectors.id` |
| `to_sector_id` | UUID | Foreign key to `sectors.id` |
| `created_at` | TIMESTAMP | Creation timestamp |

**Constraints:**
- `warps_pkey` PRIMARY KEY (`id`)
- `warps_from_sector_id_fkey` FOREIGN KEY (`from_sector_id`) REFERENCES `sectors(id)`
- `warps_to_sector_id_fkey` FOREIGN KEY (`to_sector_id`) REFERENCES `sectors(id)`
- `warps_universe_id_fkey` FOREIGN KEY (`universe_id`) REFERENCES `universes(id)`

**Triggers:**
- `warp_limit_trigger` - Prevents more than 15 warps per sector

### `players`
Player characters within a universe.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Foreign key to `auth.users.id` |
| `universe_id` | UUID | Foreign key to `universes.id` |
| `handle` | TEXT | Player display name |
| `current_sector` | UUID | Foreign key to `sectors.id` |
| `is_ai` | BOOLEAN | Whether this is an AI player |
| `ai_personality` | `ai_personality` | AI personality type (if AI) |
| `turns` | INTEGER | Available turns |
| `turns_spent` | INTEGER | Total turns used |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `players_pkey` PRIMARY KEY (`id`)
- `players_user_id_universe_id_key` UNIQUE (`user_id`, `universe_id`)
- `players_handle_universe_id_key` UNIQUE (`handle`, `universe_id`)

**Enums:**
- `ai_personality`: `trader`, `explorer`, `warrior`, `colonizer`, `balanced`

### `ships`
Player ships with equipment and cargo.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `player_id` | UUID | Foreign key to `players.id` |
| `name` | TEXT | Ship name |
| `hull` | INTEGER | Hull level |
| `hull_max` | INTEGER | Generated column: `100 * (1.5^hull)` |
| `computer` | INTEGER | Computer level |
| `computer_max` | INTEGER | Generated column: `100 * (1.5^computer)` |
| `power` | INTEGER | Power level |
| `power_max` | INTEGER | Generated column: `100 * (1.5^power)` |
| `armor_lvl` | INTEGER | Armor level |
| `armor_max` | INTEGER | Generated column: `100 * (1.5^armor_lvl)` |
| `shield_lvl` | INTEGER | Shield level |
| `shields` | INTEGER | Current shields |
| `energy` | INTEGER | Current energy |
| `energy_max` | INTEGER | Generated column: `100 * (1.5^power)` |
| `beam_weapons` | INTEGER | Beam weapons level |
| `beam_weapons_max` | INTEGER | Generated column: `100 * (1.5^beam_weapons)` |
| `torpedo_launchers` | INTEGER | Torpedo launchers level |
| `torpedo_launchers_max` | INTEGER | Generated column: `100 * (1.5^torpedo_launchers)` |
| `credits` | BIGINT | Available credits |
| `ore` | INTEGER | Ore cargo |
| `organics` | INTEGER | Organics cargo |
| `goods` | INTEGER | Goods cargo |
| `energy_cargo` | INTEGER | Energy cargo |
| `colonists` | INTEGER | Colonists on board |
| `fighters` | INTEGER | Fighters on board |
| `torpedoes` | INTEGER | Torpedoes on board |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `ships_pkey` PRIMARY KEY (`id`)
- `ships_player_id_key` UNIQUE (`player_id`)

### `planets`
Planets within sectors.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `sector_id` | UUID | Foreign key to `sectors.id` |
| `name` | TEXT | Planet name |
| `owner_player_id` | UUID | Foreign key to `players.id` (nullable) |
| `colonists` | INTEGER | Current colonists |
| `colonists_max` | INTEGER | Maximum colonists |
| `ore` | INTEGER | Ore production |
| `organics` | INTEGER | Organics production |
| `goods` | INTEGER | Goods production |
| `energy` | INTEGER | Energy production |
| `fighters` | INTEGER | Fighter production |
| `torpedoes` | INTEGER | Torpedo production |
| `shields` | INTEGER | Shield production |
| `credits` | BIGINT | Planet credits |
| `base_built` | BOOLEAN | Whether base is built |
| `base_cost` | INTEGER | Base construction cost |
| `base_colonists_required` | INTEGER | Colonists needed for base |
| `base_resources_required` | INTEGER | Resources needed for base |
| `last_production` | TIMESTAMP | Last production update |
| `last_colonist_growth` | TIMESTAMP | Last colonist growth |
| `production_ore_percent` | INTEGER | Ore production allocation (0-100) |
| `production_organics_percent` | INTEGER | Organics production allocation (0-100) |
| `production_goods_percent` | INTEGER | Goods production allocation (0-100) |
| `production_energy_percent` | INTEGER | Energy production allocation (0-100) |
| `production_fighters_percent` | INTEGER | Fighter production allocation (0-100) |
| `production_torpedoes_percent` | INTEGER | Torpedo production allocation (0-100) |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

### `ports`
Trading ports within sectors.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `sector_id` | UUID | Foreign key to `sectors.id` |
| `universe_id` | UUID | Foreign key to `universes.id` |
| `kind` | TEXT | Port type: 'special', 'ore', 'organics', 'goods', 'energy' |
| `name` | TEXT | Port name (for special ports) |
| `ore` | INTEGER | Ore stock |
| `organics` | INTEGER | Organics stock |
| `goods` | INTEGER | Goods stock |
| `energy` | INTEGER | Energy stock |
| `price_ore` | NUMERIC | Ore price |
| `price_organics` | NUMERIC | Organics price |
| `price_goods` | NUMERIC | Goods price |
| `price_energy` | NUMERIC | Energy price |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `ports_pkey` PRIMARY KEY (`id`)
- `ports_sector_id_key` UNIQUE (`sector_id`)

### `universe_settings`
Configuration settings for each universe.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `universe_id` | UUID | Foreign key to `universes.id` |
| `ai_actions_enabled` | BOOLEAN | Whether enhanced AI is enabled |
| `max_planets_per_sector` | INTEGER | Maximum planets per sector |
| `planets_needed_for_sector_ownership` | INTEGER | Planets needed to own a sector |
| `avg_tech_level_mines` | INTEGER | Average tech level for mines |
| `avg_tech_emergency_warp_degrade` | INTEGER | Tech level for emergency warp degrade |
| `max_avg_tech_federation_sectors` | INTEGER | Max tech for federation sectors |
| `igb_enabled` | BOOLEAN | Inter-Galactic Bank enabled |
| `igb_interest_rate_per_update` | NUMERIC | IGB interest rate |
| `igb_loan_rate_per_update` | NUMERIC | IGB loan rate |
| `planet_interest_rate` | NUMERIC | Planet interest rate |
| `colonists_limit` | INTEGER | Colonists limit |
| `colonist_production_rate` | NUMERIC | Colonist production rate |
| `colonists_per_fighter` | INTEGER | Colonists per fighter |
| `colonists_per_torpedo` | INTEGER | Colonists per torpedo |
| `colonists_per_ore` | INTEGER | Colonists per ore |
| `colonists_per_organics` | INTEGER | Colonists per organics |
| `colonists_per_goods` | INTEGER | Colonists per goods |
| `colonists_per_energy` | INTEGER | Colonists per energy |
| `colonists_per_credits` | INTEGER | Colonists per credits |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `universe_settings_pkey` PRIMARY KEY (`id`)
- `universe_settings_unique_per_universe` UNIQUE (`universe_id`)

### `ai_player_memory`
AI player persistent memory and state.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `player_id` | UUID | Foreign key to `players.id` |
| `current_goal` | TEXT | Current AI goal |
| `target_sector` | UUID | Target sector for movement |
| `target_planet` | UUID | Target planet for actions |
| `last_action` | TEXT | Last action taken |
| `action_count` | INTEGER | Number of actions taken |
| `efficiency_score` | NUMERIC | AI efficiency rating |
| `created_at` | TIMESTAMP | Creation timestamp |
| `updated_at` | TIMESTAMP | Last update timestamp |

**Constraints:**
- `ai_player_memory_pkey` PRIMARY KEY (`id`)
- `ai_player_memory_player_id_key` UNIQUE (`player_id`)

## Key Functions

### Game Functions
- `game_move(p_user_id, p_sector_number, p_universe_id)` - Move player to sector
- `game_trade(p_user_id, p_port_id, p_action, p_resource, p_qty, p_universe_id)` - Trade at port
- `game_planet_claim(p_user_id, p_planet_id, p_universe_id)` - Claim a planet
- `game_ship_upgrade(p_user_id, p_upgrade_type, p_universe_id)` - Upgrade ship
- `track_turn_spent(p_player_id)` - Track turn usage

### AI Functions
- `run_enhanced_ai_actions(p_universe_id)` - Run enhanced AI system
- `ai_make_decision(p_player_id)` - AI decision making
- `ai_execute_action(p_player_id, p_action)` - Execute AI action
- `ai_optimize_trading(p_player_id)` - AI trading optimization
- `ai_strategic_explore(p_player_id)` - AI exploration
- `ai_claim_planet(p_player_id)` - AI planet claiming
- `ai_manage_planets(p_player_id)` - AI planet management

### Utility Functions
- `create_universe(p_name, p_sector_count)` - Create new universe
- `destroy_universe(p_universe_id)` - Destroy universe
- `get_ship_capacity(p_ship_id, p_cargo_type)` - Get ship capacity
- `bnt_capacity_lookup(p_tech_level)` - BNT capacity formula
- `create_universe_default_settings(p_universe_id, p_settings)` - Create default settings

### Cron Functions
- `cron_run_ai_actions(p_universe_id)` - Cron wrapper for AI actions
- `run_ai_player_actions(p_universe_id)` - Basic AI actions
- `cron_cycle_events(p_universe_id)` - Cycle game events
- `cron_regen(p_universe_id)` - Regenerate resources

## Relationships

```
universes (1) ──→ (N) sectors
universes (1) ──→ (N) warps
universes (1) ──→ (N) players
universes (1) ──→ (1) universe_settings

sectors (1) ──→ (N) warps (from_sector_id)
sectors (1) ──→ (N) warps (to_sector_id)
sectors (1) ──→ (N) planets
sectors (1) ──→ (1) ports
sectors (1) ──→ (N) players (current_sector)

players (1) ──→ (1) ships
players (1) ──→ (N) planets (owner)
players (1) ──→ (1) ai_player_memory (if AI)

ships (N) ──→ (1) players

planets (N) ──→ (1) sectors
planets (N) ──→ (1) players (owner, nullable)

ports (N) ──→ (1) sectors
ports (N) ──→ (1) universes
```

## Indexes

### Performance Indexes
- `idx_players_universe_sector` on `players(universe_id, current_sector)`
- `idx_ships_player_id` on `ships(player_id)`
- `idx_planets_sector_owner` on `planets(sector_id, owner_player_id)`
- `idx_warps_from_sector` on `warps(from_sector_id)`
- `idx_warps_to_sector` on `warps(to_sector_id)`

### Unique Indexes
- `universes_name_key` on `universes(name)`
- `sectors_universe_id_number_key` on `sectors(universe_id, number)`
- `players_user_id_universe_id_key` on `players(user_id, universe_id)`
- `players_handle_universe_id_key` on `players(handle, universe_id)`
- `ships_player_id_key` on `ships(player_id)`
- `ports_sector_id_key` on `ports(sector_id)`
- `universe_settings_unique_per_universe` on `universe_settings(universe_id)`
- `ai_player_memory_player_id_key` on `ai_player_memory(player_id)`

## Triggers

### Warp Limit Trigger
- `warp_limit_trigger` - Prevents more than 15 warps per sector
- Fires on INSERT to `warps` table
- Raises exception if limit exceeded

### Timestamp Triggers
- `update_updated_at_column()` - Updates `updated_at` timestamp
- Applied to: `universes`, `players`, `ships`, `planets`, `ports`, `universe_settings`, `ai_player_memory`

## Generated Columns

### Ship Capacity Columns
All ship capacity columns are generated using the BNT formula: `100 * (1.5^tech_level)`

- `ships.hull_max` = `100 * (1.5^hull)`
- `ships.computer_max` = `100 * (1.5^computer)`
- `ships.power_max` = `100 * (1.5^power)`
- `ships.armor_max` = `100 * (1.5^armor_lvl)`
- `ships.energy_max` = `100 * (1.5^power)`
- `ships.beam_weapons_max` = `100 * (1.5^beam_weapons)`
- `ships.torpedo_launchers_max` = `100 * (1.5^torpedo_launchers)`

## Data Types

### Custom Types
- `ai_personality` ENUM: `trader`, `explorer`, `warrior`, `colonizer`, `balanced`

### Numeric Types
- `INTEGER` - Standard integers for levels, counts
- `BIGINT` - Large integers for credits, high-value resources
- `NUMERIC` - Decimal numbers for prices, rates, percentages

### UUID Types
- All primary keys use `UUID` type
- Foreign keys use `UUID` type
- Generated using `gen_random_uuid()`

## Security

### Row Level Security (RLS)
- Enabled on all tables
- Policies ensure users can only access their own data
- AI players have special access patterns

### Function Security
- All game functions use `SECURITY DEFINER`
- Functions validate user permissions
- AI functions have elevated privileges

## Backup and Recovery

### Schema Backups
- Complete schema dumps in `sql_backups/complete_schema_dump_*.sql`
- Function dumps in `sql_backups/all_functions_dump_*.sql`
- Generated automatically with timestamps

### Migration System
- Sequential migration files in `sql/` directory
- Numbered format: `XXX_description.sql`
- Applied in order to maintain schema consistency

## Performance Considerations

### Query Optimization
- Use indexes for common query patterns
- Limit result sets with appropriate WHERE clauses
- Use generated columns to avoid complex calculations

### AI Performance
- AI functions are optimized for batch processing
- Memory table reduces database queries
- Turn tracking prevents excessive AI actions

### Scaling Considerations
- Universe isolation allows horizontal scaling
- Sector-based partitioning possible
- AI actions can be distributed across multiple processes
