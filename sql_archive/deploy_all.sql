-- BNT Redux Complete Database Deployment Script
-- This script recreates the entire database from scratch
-- Run this in Supabase SQL Editor to deploy everything

-- ==============================================
-- STEP 1: Core Schema and Seed Data
-- ==============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop existing tables if they exist (in reverse dependency order)
DROP TABLE IF EXISTS route_executions CASCADE;
DROP TABLE IF EXISTS route_waypoints CASCADE;
DROP TABLE IF EXISTS route_profitability CASCADE;
DROP TABLE IF EXISTS trade_routes CASCADE;
DROP TABLE IF EXISTS ranking_history CASCADE;
DROP TABLE IF EXISTS player_rankings CASCADE;
DROP TABLE IF EXISTS ai_players CASCADE;
DROP TABLE IF EXISTS planets CASCADE;
DROP TABLE IF EXISTS trades CASCADE;
DROP TABLE IF EXISTS combats CASCADE;
DROP TABLE IF EXISTS inventories CASCADE;
DROP TABLE IF EXISTS ships CASCADE;
DROP TABLE IF EXISTS players CASCADE;
DROP TABLE IF EXISTS ports CASCADE;
DROP TABLE IF EXISTS warps CASCADE;
DROP TABLE IF EXISTS sectors CASCADE;
DROP TABLE IF EXISTS universes CASCADE;

-- Create core tables
CREATE TABLE universes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    sector_count INTEGER DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE sectors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    number INTEGER NOT NULL,
    name TEXT,
    UNIQUE(universe_id, number)
);

CREATE TABLE warps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    from_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    to_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    CHECK (from_sector != to_sector),
    UNIQUE(universe_id, from_sector, to_sector)
);

CREATE TABLE ports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('ore', 'organics', 'goods', 'energy', 'special')),
    stock_ore BIGINT DEFAULT 0,
    stock_organics BIGINT DEFAULT 0,
    stock_goods BIGINT DEFAULT 0,
    stock_energy BIGINT DEFAULT 0,
    price_ore NUMERIC DEFAULT 100,
    price_organics NUMERIC DEFAULT 100,
    price_goods NUMERIC DEFAULT 100,
    price_energy NUMERIC DEFAULT 100,
    UNIQUE(sector_id)
);

CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
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

CREATE TABLE ships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    name TEXT DEFAULT 'Scout',
    hull INTEGER DEFAULT 100,
    hull_lvl INTEGER DEFAULT 1,
    hull_max INTEGER GENERATED ALWAYS AS (100 * GREATEST(hull_lvl, 1)) STORED,
    shield INTEGER DEFAULT 0,
    shield_lvl INTEGER DEFAULT 0,
    shield_max INTEGER GENERATED ALWAYS AS (100 * GREATEST(shield_lvl, 1)) STORED,
    cargo INTEGER DEFAULT 1000,
    fighters INTEGER DEFAULT 0,
    torpedoes INTEGER DEFAULT 0,
    engine_lvl INTEGER DEFAULT 1,
    comp_lvl INTEGER DEFAULT 1,
    sensor_lvl INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(player_id)
);

CREATE TABLE inventories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    ore INTEGER DEFAULT 0,
    organics INTEGER DEFAULT 0,
    goods INTEGER DEFAULT 0,
    energy INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(player_id)
);

CREATE TABLE trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('buy', 'sell')),
    resource TEXT NOT NULL CHECK (resource IN ('ore', 'organics', 'goods', 'energy')),
    qty INTEGER NOT NULL,
    price NUMERIC NOT NULL,
    at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE combats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    defender_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    outcome TEXT,
    snapshot JSONB,
    at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE planets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    owner_id UUID REFERENCES players(id) ON DELETE SET NULL,
    stored_ore INTEGER DEFAULT 0,
    stored_organics INTEGER DEFAULT 0,
    stored_goods INTEGER DEFAULT 0,
    stored_energy INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Rankings and AI tables
CREATE TABLE player_rankings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id),
    universe_id UUID REFERENCES universes(id),
    economic_score INTEGER DEFAULT 0,
    territorial_score INTEGER DEFAULT 0,
    military_score INTEGER DEFAULT 0,
    exploration_score INTEGER DEFAULT 0,
    total_score INTEGER DEFAULT 0,
    rank_position INTEGER,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ai_players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID REFERENCES universes(id),
    name TEXT NOT NULL,
    ai_type TEXT CHECK (ai_type IN ('trader', 'explorer', 'military', 'balanced')),
    economic_score INTEGER DEFAULT 0,
    territorial_score INTEGER DEFAULT 0,
    military_score INTEGER DEFAULT 0,
    exploration_score INTEGER DEFAULT 0,
    total_score INTEGER DEFAULT 0,
    rank_position INTEGER,
    last_updated TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ranking_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id),
    universe_id UUID REFERENCES universes(id),
    rank_position INTEGER,
    total_score INTEGER,
    recorded_at TIMESTAMP DEFAULT NOW()
);

-- Trade routes tables
CREATE TABLE trade_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    is_loop BOOLEAN DEFAULT false,
    movement_type TEXT DEFAULT 'warp' CHECK (movement_type IN ('warp', 'realspace')),
    current_waypoint_index INTEGER DEFAULT 0,
    execution_count INTEGER DEFAULT 0,
    max_executions INTEGER DEFAULT -1,
    last_executed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE route_waypoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    sequence_order INTEGER NOT NULL,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('buy', 'sell', 'trade_auto')),
    resource TEXT,
    quantity INTEGER,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE route_executions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed')),
    error_message TEXT,
    total_profit BIGINT DEFAULT 0,
    turns_spent INTEGER DEFAULT 0,
    execution_data JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE route_profitability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    calculated_at TIMESTAMPTZ DEFAULT now(),
    estimated_profit_per_cycle BIGINT DEFAULT 0,
    estimated_turns_per_cycle INTEGER DEFAULT 0,
    profit_per_turn NUMERIC DEFAULT 0,
    market_conditions JSONB,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==============================================
-- STEP 2: Indexes
-- ==============================================

CREATE INDEX idx_sectors_universe_number ON sectors(universe_id, number);
CREATE INDEX idx_warps_from_sector ON warps(from_sector);
CREATE INDEX idx_warps_to_sector ON warps(to_sector);
CREATE INDEX idx_players_user_id ON players(user_id);
CREATE INDEX idx_players_current_sector ON players(current_sector);
CREATE INDEX idx_trades_player_id ON trades(player_id);
CREATE INDEX idx_trades_at ON trades(at);
CREATE INDEX idx_combats_attacker ON combats(attacker_id);
CREATE INDEX idx_combats_defender ON combats(defender_id);
CREATE INDEX idx_planets_sector_id ON planets(sector_id);
CREATE INDEX idx_planets_owner_id ON planets(owner_id);

-- ==============================================
-- STEP 3: Create Default Universe
-- ==============================================

-- Create the Alpha universe
INSERT INTO universes (name, sector_count) VALUES ('Alpha', 500);

-- Get the universe ID for reference
DO $$
DECLARE
    universe_uuid UUID;
    sector_uuid UUID;
    port_count INTEGER := 0;
    target_ports INTEGER := 50;
    warp_count INTEGER;
    target_sector INTEGER;
    existing_warps INTEGER;
BEGIN
    -- Get the universe ID
    SELECT id INTO universe_uuid FROM universes WHERE name = 'Alpha';
    
    -- Create 500 sectors
    FOR i IN 1..500 LOOP
        INSERT INTO sectors (universe_id, number) 
        VALUES (universe_uuid, i);
    END LOOP;
    
    -- Create warps: backbone connections
    FOR i IN 1..499 LOOP
        INSERT INTO warps (universe_id, from_sector, to_sector)
        SELECT universe_uuid, s1.id, s2.id
        FROM sectors s1, sectors s2
        WHERE s1.universe_id = universe_uuid AND s1.number = i
        AND s2.universe_id = universe_uuid AND s2.number = i + 1;
        
        INSERT INTO warps (universe_id, from_sector, to_sector)
        SELECT universe_uuid, s2.id, s1.id
        FROM sectors s1, sectors s2
        WHERE s1.universe_id = universe_uuid AND s1.number = i
        AND s2.universe_id = universe_uuid AND s2.number = i + 1;
    END LOOP;
    
    -- Create random warps (up to 10 total per universe)
    FOR i IN 1..500 LOOP
        warp_count := 1 + (random() * 2)::INTEGER;
        
        FOR j IN 1..warp_count LOOP
            LOOP
                target_sector := 1 + (random() * 499)::INTEGER;
                IF target_sector >= i THEN
                    target_sector := target_sector + 1;
                END IF;
                
                SELECT COUNT(*) INTO existing_warps
                FROM warps w
                JOIN sectors s1 ON w.from_sector = s1.id
                JOIN sectors s2 ON w.to_sector = s2.id
                WHERE w.universe_id = universe_uuid 
                AND s1.number = i 
                AND s2.number = target_sector;
                
                IF existing_warps = 0 THEN
                    INSERT INTO warps (universe_id, from_sector, to_sector)
                    SELECT universe_uuid, s1.id, s2.id
                    FROM sectors s1, sectors s2
                    WHERE s1.universe_id = universe_uuid AND s1.number = i
                    AND s2.universe_id = universe_uuid AND s2.number = target_sector;
                    
                    INSERT INTO warps (universe_id, from_sector, to_sector)
                    SELECT universe_uuid, s2.id, s1.id
                    FROM sectors s1, sectors s2
                    WHERE s1.universe_id = universe_uuid AND s1.number = i
                    AND s2.universe_id = universe_uuid AND s2.number = target_sector;
                    
                    EXIT;
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;
    
    -- Create special port in Sector 0 (Sol Hub)
    SELECT id INTO sector_uuid FROM sectors 
    WHERE universe_id = universe_uuid AND number = 0;
    
    INSERT INTO ports (sector_id, kind, stock_ore, stock_organics, stock_goods, stock_energy, 
                     price_ore, price_organics, price_goods, price_energy)
    VALUES (sector_uuid, 'special', 1000000000, 1000000000, 1000000000, 1000000000, 
            100, 100, 100, 100);
    
    -- Create commodity ports on ~10% of sectors (excluding Sector 0)
    FOR i IN 1..500 LOOP
        IF random() < 0.1 THEN
            SELECT id INTO sector_uuid FROM sectors 
            WHERE universe_id = universe_uuid AND number = i;
            
            INSERT INTO ports (sector_id, kind, stock_ore, stock_organics, stock_goods, stock_energy, 
                             price_ore, price_organics, price_goods, price_energy)
            VALUES (
                sector_uuid,
                CASE (random() * 4)::INTEGER
                    WHEN 0 THEN 'ore'
                    WHEN 1 THEN 'organics'
                    WHEN 2 THEN 'goods'
                    ELSE 'energy'
                END,
                1000000000, 0, 0, 0,  -- Native stock only
                100, 100, 100, 100     -- Base prices
            );
            
            port_count := port_count + 1;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Created universe Alpha with 500 sectors and % ports', port_count;
END $$;

-- ==============================================
-- STEP 4: Essential RPC Functions
-- ==============================================

-- Note: This is a simplified version. For full functionality,
-- you'll need to run the individual RPC files in order:
-- 003_rpc.sql, 006_rpc_trade_by_type.sql, 013_rpc_trade_auto.sql,
-- 018_rpc_ship_upgrades.sql, 040_universe_management.sql,
-- 044_rankings_system.sql, 047_trade_routes_rpc.sql, etc.

-- Basic move function
CREATE OR REPLACE FUNCTION game_move(
    p_user_id UUID,
    p_to_sector_number INTEGER,
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player RECORD;
    v_current_sector RECORD;
    v_target_sector RECORD;
    v_warp_exists BOOLEAN;
    v_result JSON;
BEGIN
    -- Get player info - filter by universe if provided
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.number as current_sector_number
        INTO v_player
        FROM players p
        JOIN sectors s ON p.current_sector = s.id
        WHERE p.user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Player not found');
    END IF;
    
    IF v_player.turns < 1 THEN
        RETURN json_build_object('error', 'Insufficient turns');
    END IF;
    
    -- Get target sector
    IF p_universe_id IS NOT NULL THEN
        SELECT * INTO v_target_sector
        FROM sectors s
        WHERE s.universe_id = p_universe_id AND s.number = p_to_sector_number;
    ELSE
        SELECT * INTO v_target_sector
        FROM sectors s
        JOIN universes u ON s.universe_id = u.id
        WHERE u.name = 'Alpha' AND s.number = p_to_sector_number;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Target sector not found');
    END IF;
    
    -- Check if warp exists
    SELECT EXISTS(
        SELECT 1 FROM warps w
        WHERE w.from_sector = v_player.current_sector
        AND w.to_sector = v_target_sector.id
    ) INTO v_warp_exists;
    
    IF NOT v_warp_exists THEN
        RETURN json_build_object('error', 'No warp connection to target sector');
    END IF;
    
    -- Perform the move
    UPDATE players 
    SET current_sector = v_target_sector.id, turns = turns - 1
    WHERE id = v_player.id;
    
    RETURN json_build_object(
        'ok', true,
        'player', json_build_object(
            'current_sector', v_target_sector.id,
            'turns', v_player.turns - 1
        )
    );
END;
$$;

-- ==============================================
-- DEPLOYMENT COMPLETE
-- ==============================================

-- This script creates the basic database structure and one universe.
-- To get full functionality, run the individual RPC files in order:
-- 003_rpc.sql, 006_rpc_trade_by_type.sql, 013_rpc_trade_auto.sql,
-- 018_rpc_ship_upgrades.sql, 040_universe_management.sql,
-- 044_rankings_system.sql, 047_trade_routes_rpc.sql, etc.

SELECT 'Database deployment complete! Run individual RPC files for full functionality.' as status;


