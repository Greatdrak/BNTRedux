-- Migration: 325_add_performance_indexes.sql
-- Purpose: Add critical indexes to improve query performance

-- Players table indexes
CREATE INDEX IF NOT EXISTS idx_players_user_id ON public.players(user_id);
CREATE INDEX IF NOT EXISTS idx_players_universe_id ON public.players(universe_id);
CREATE INDEX IF NOT EXISTS idx_players_universe_is_ai ON public.players(universe_id, is_ai) WHERE is_ai = true;
CREATE INDEX IF NOT EXISTS idx_players_current_sector ON public.players(current_sector);

-- Sectors table indexes
CREATE INDEX IF NOT EXISTS idx_sectors_universe_number ON public.sectors(universe_id, number);
CREATE INDEX IF NOT EXISTS idx_sectors_universe_id ON public.sectors(universe_id);

-- Warps table indexes
CREATE INDEX IF NOT EXISTS idx_warps_from_sector ON public.warps(from_sector);
CREATE INDEX IF NOT EXISTS idx_warps_to_sector ON public.warps(to_sector);

-- Ports table indexes
CREATE INDEX IF NOT EXISTS idx_ports_sector_id ON public.ports(sector_id);
CREATE INDEX IF NOT EXISTS idx_ports_kind ON public.ports(kind);

-- Planets table indexes
CREATE INDEX IF NOT EXISTS idx_planets_sector_id ON public.planets(sector_id);
CREATE INDEX IF NOT EXISTS idx_planets_owner_player_id ON public.planets(owner_player_id);

-- Ships table indexes
CREATE INDEX IF NOT EXISTS idx_ships_player_id ON public.ships(player_id);

-- Trade routes table indexes
CREATE INDEX IF NOT EXISTS idx_trade_routes_player_active ON public.trade_routes(player_id, is_active);
CREATE INDEX IF NOT EXISTS idx_trade_routes_universe_id ON public.trade_routes(universe_id);

-- Rankings table indexes
CREATE INDEX IF NOT EXISTS idx_player_rankings_universe_id ON public.player_rankings(universe_id);
CREATE INDEX IF NOT EXISTS idx_player_rankings_player_id ON public.player_rankings(player_id);

-- Universe settings indexes
CREATE INDEX IF NOT EXISTS idx_universe_settings_universe_id ON public.universe_settings(universe_id);

-- Create composite indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_planets_sector_unclaimed ON public.planets(sector_id) WHERE owner_player_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_ports_sector_not_special ON public.ports(sector_id, kind) WHERE kind != 'special';

ANALYZE public.players;
ANALYZE public.sectors;
ANALYZE public.warps;
ANALYZE public.ports;
ANALYZE public.planets;
ANALYZE public.ships;
ANALYZE public.trade_routes;

