-- BNT Redux Database Schema
-- How to apply: Run this file once in Supabase SQL Editor to create all tables and constraints

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Universes: Game instances
CREATE TABLE IF NOT EXISTS universes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    sector_count INTEGER NOT NULL,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Sectors: Individual locations within a universe
CREATE TABLE IF NOT EXISTS sectors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    number INTEGER NOT NULL,
    meta JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(universe_id, number)
);

-- Warps: Bidirectional connections between sectors
CREATE TABLE IF NOT EXISTS warps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    from_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    to_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(universe_id, from_sector, to_sector),
    CHECK(from_sector != to_sector)
);

-- Ports: Trading locations within sectors
CREATE TABLE IF NOT EXISTS ports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    kind TEXT DEFAULT 'trade',
    -- Stock levels
    ore INTEGER DEFAULT 0,
    organics INTEGER DEFAULT 0,
    goods INTEGER DEFAULT 0,
    energy INTEGER DEFAULT 0,
    -- Prices per unit
    price_ore NUMERIC DEFAULT 10.0,
    price_organics NUMERIC DEFAULT 15.0,
    price_goods NUMERIC DEFAULT 25.0,
    price_energy NUMERIC DEFAULT 5.0,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(sector_id)
);

-- Players: Game users linked to Supabase auth
CREATE TABLE IF NOT EXISTS players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL, -- Supabase auth.users.id
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    handle TEXT NOT NULL,
    credits BIGINT DEFAULT 1000,
    turns INTEGER DEFAULT 60,
    turn_cap INTEGER DEFAULT 120,
    current_sector UUID REFERENCES sectors(id),
    last_turn_ts TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(universe_id, handle)
);

-- Ships: Player vessels
CREATE TABLE IF NOT EXISTS ships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    name TEXT DEFAULT 'Scout',
    hull INTEGER DEFAULT 100,
    shield INTEGER DEFAULT 0,
    cargo INTEGER DEFAULT 100,
    fighters INTEGER DEFAULT 0,
    torpedoes INTEGER DEFAULT 0,
    engine_lvl INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(player_id)
);

-- Inventories: Player cargo holds
CREATE TABLE IF NOT EXISTS inventories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    ore INTEGER DEFAULT 0,
    organics INTEGER DEFAULT 0,
    goods INTEGER DEFAULT 0,
    energy INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(player_id)
);

-- Trades: Transaction history
CREATE TABLE IF NOT EXISTS trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('buy', 'sell')),
    resource TEXT NOT NULL CHECK (resource IN ('ore', 'organics', 'goods', 'energy')),
    qty INTEGER NOT NULL,
    price NUMERIC NOT NULL,
    at TIMESTAMPTZ DEFAULT now()
);

-- Combats: Battle records
CREATE TABLE IF NOT EXISTS combats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    defender_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    outcome TEXT,
    snapshot JSONB,
    at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sectors_universe_number ON sectors(universe_id, number);
CREATE INDEX IF NOT EXISTS idx_warps_from_sector ON warps(from_sector);
CREATE INDEX IF NOT EXISTS idx_warps_to_sector ON warps(to_sector);
CREATE INDEX IF NOT EXISTS idx_players_user_id ON players(user_id);
CREATE INDEX IF NOT EXISTS idx_players_current_sector ON players(current_sector);
CREATE INDEX IF NOT EXISTS idx_trades_player_id ON trades(player_id);
CREATE INDEX IF NOT EXISTS idx_trades_at ON trades(at);
CREATE INDEX IF NOT EXISTS idx_combats_attacker ON combats(attacker_id);
CREATE INDEX IF NOT EXISTS idx_combats_defender ON combats(defender_id);
