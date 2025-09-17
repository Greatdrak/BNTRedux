-- Complete Schema Dump for BNT Redux Database
-- This includes all tables, functions, indexes, and constraints needed to recreate the database

-- ==============================================
-- TABLES
-- ==============================================

-- Universes table
CREATE TABLE universes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    sector_count INTEGER DEFAULT 100
);

-- Sectors table
CREATE TABLE sectors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    number INTEGER NOT NULL,
    name TEXT,
    UNIQUE(universe_id, number)
);

-- Warps table
CREATE TABLE warps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    from_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    to_sector UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    CHECK (from_sector != to_sector),
    UNIQUE(universe_id, from_sector, to_sector)
);

-- Ports table
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

-- Players table
CREATE TABLE players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    handle TEXT NOT NULL,
    current_sector UUID NOT NULL REFERENCES sectors(id),
    turns INTEGER DEFAULT 100,
    credits NUMERIC DEFAULT 1000,
    UNIQUE(universe_id, handle)
);

-- Ships table
CREATE TABLE ships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    hull_lvl INTEGER DEFAULT 1 CHECK (hull_lvl >= 1 AND hull_lvl <= 10),
    hull_max INTEGER GENERATED ALWAYS AS (100 * GREATEST(hull_lvl, 1)) STORED,
    shield_lvl INTEGER DEFAULT 1 CHECK (shield_lvl >= 1 AND shield_lvl <= 10),
    shield_max INTEGER GENERATED ALWAYS AS (100 * GREATEST(shield_lvl, 1)) STORED,
    comp_lvl INTEGER DEFAULT 1,
    sensor_lvl INTEGER DEFAULT 1,
    engine_lvl INTEGER DEFAULT 1,
    cargo INTEGER DEFAULT 1000,
    fighters INTEGER DEFAULT 0,
    torpedoes INTEGER DEFAULT 0,
    name TEXT DEFAULT 'Ship',
    UNIQUE(player_id)
);

-- Inventories table
CREATE TABLE inventories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    ore INTEGER DEFAULT 0,
    organics INTEGER DEFAULT 0,
    goods INTEGER DEFAULT 0,
    energy INTEGER DEFAULT 0,
    UNIQUE(player_id)
);

-- Trades table
CREATE TABLE trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action TEXT NOT NULL CHECK (action IN ('buy', 'sell')),
    resource TEXT NOT NULL CHECK (resource IN ('ore', 'organics', 'goods', 'energy')),
    quantity INTEGER NOT NULL,
    price_per_unit NUMERIC NOT NULL,
    total_cost NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Combats table
CREATE TABLE combats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attacker_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    defender_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    result TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Visited table
CREATE TABLE visited (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    visited_at TIMESTAMPTZ DEFAULT now()
);

-- Scans table
CREATE TABLE scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    mode TEXT NOT NULL CHECK (mode IN ('single', 'full', 'warps')),
    scanned_at TIMESTAMPTZ DEFAULT now()
);

-- Favorites table
CREATE TABLE favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    favorited_at TIMESTAMPTZ DEFAULT now()
);

-- Planets table
CREATE TABLE planets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sector_id UUID NOT NULL REFERENCES sectors(id) ON DELETE CASCADE,
    owner_player_id UUID REFERENCES players(id) ON DELETE SET NULL,
    name TEXT,
    population BIGINT DEFAULT 0,
    resources JSONB DEFAULT '{}',
    UNIQUE(sector_id)
);

-- Trade Routes tables
CREATE TABLE trade_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    movement_type TEXT DEFAULT 'warp' CHECK (movement_type IN ('warp', 'realspace')),
    is_active BOOLEAN DEFAULT false,
    is_automated BOOLEAN DEFAULT false,
    max_iterations INTEGER DEFAULT 0,
    current_iteration INTEGER DEFAULT 0,
    total_profit BIGINT DEFAULT 0,
    total_turns_spent INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    last_executed_at TIMESTAMPTZ,
    UNIQUE(player_id, name)
);

CREATE TABLE route_waypoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    sequence_order INTEGER NOT NULL,
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('buy', 'sell', 'trade_auto')),
    resource TEXT CHECK (resource IN ('ore', 'organics', 'goods', 'energy')),
    quantity INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(route_id, sequence_order)
);

CREATE TABLE route_executions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed', 'paused')),
    current_waypoint INTEGER DEFAULT 1,
    total_profit BIGINT DEFAULT 0,
    turns_spent INTEGER DEFAULT 0,
    error_message TEXT,
    execution_data JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE route_profitability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    calculated_at TIMESTAMPTZ DEFAULT now(),
    estimated_profit_per_cycle BIGINT,
    estimated_turns_per_cycle INTEGER,
    profit_per_turn NUMERIC,
    cargo_efficiency NUMERIC,
    market_conditions JSONB DEFAULT '{}'::jsonb,
    is_current BOOLEAN DEFAULT true,
    UNIQUE(route_id, calculated_at)
);

CREATE TABLE route_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    template_data JSONB NOT NULL,
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    required_engine_level INTEGER DEFAULT 1,
    required_cargo_capacity INTEGER DEFAULT 1000,
    estimated_profit_per_turn NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Rankings tables
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
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(player_id, universe_id)
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
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(name, universe_id)
);

CREATE TABLE ranking_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID REFERENCES players(id),
    universe_id UUID REFERENCES universes(id),
    rank_position INTEGER,
    total_score INTEGER,
    recorded_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE ai_ranking_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ai_player_id UUID REFERENCES ai_players(id),
    universe_id UUID REFERENCES universes(id),
    rank_position INTEGER,
    total_score INTEGER,
    recorded_at TIMESTAMP DEFAULT NOW()
);

-- ==============================================
-- INDEXES
-- ==============================================

CREATE INDEX idx_trade_routes_player_universe ON trade_routes(player_id, universe_id);
CREATE INDEX idx_trade_routes_active ON trade_routes(is_active) WHERE is_active = true;
CREATE INDEX idx_route_waypoints_route_id ON route_waypoints(route_id);
CREATE INDEX idx_route_executions_route_id ON route_executions(route_id);
CREATE INDEX idx_route_executions_player_id ON route_executions(player_id);
CREATE INDEX idx_route_profitability_route_id ON route_profitability(route_id);
CREATE INDEX idx_players_universe_id ON players(universe_id);
CREATE INDEX idx_sectors_universe_id ON sectors(universe_id);
CREATE INDEX idx_warps_universe_id ON warps(universe_id);
CREATE INDEX idx_ports_sector_id ON ports(sector_id);
CREATE INDEX idx_trades_player_id ON trades(player_id);
CREATE INDEX idx_trades_port_id ON trades(port_id);
CREATE INDEX idx_visited_player_id ON visited(player_id);
CREATE INDEX idx_scans_player_id ON scans(player_id);
CREATE INDEX idx_favorites_player_id ON favorites(player_id);
CREATE INDEX idx_planets_sector_id ON planets(sector_id);
CREATE INDEX idx_planets_owner_player_id ON planets(owner_player_id);

-- ==============================================
-- FUNCTIONS (from 083_complete_fix.sql)
-- ==============================================

-- Complete execute_trade_route function with movement types
CREATE OR REPLACE FUNCTION execute_trade_route(
    p_user_id UUID,
    p_route_id UUID,
    p_max_iterations INTEGER DEFAULT 1,
    p_universe_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_player RECORD;
    v_route RECORD;
    v_execution_id UUID;
    v_start_port RECORD;
    v_target_port RECORD;
    v_trade_result JSONB;
    v_move_result JSON;
    v_log TEXT := '';
    v_turns_spent INTEGER := 0;
    v_total_profit BIGINT := 0;
    v_turns_before INTEGER;
    v_turns_after INTEGER;
    v_credits_before NUMERIC;
    v_credits_after NUMERIC;
    v_movement_type TEXT;
    v_distance INTEGER;
    v_engine_level INTEGER;
BEGIN
    -- Get player info
    IF p_universe_id IS NOT NULL THEN
        SELECT p.*, s.engine_lvl INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id AND p.universe_id = p_universe_id;
    ELSE
        SELECT p.*, s.engine_lvl INTO v_player
        FROM players p
        JOIN ships s ON p.id = s.player_id
        WHERE p.user_id = p_user_id;
    END IF;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found'));
    END IF;
    
    v_player_id := v_player.id;
    v_turns_before := v_player.turns;
    v_credits_before := v_player.credits;
    v_engine_level := v_player.engine_lvl;
    
    -- Get route info including movement_type
    SELECT tr.* INTO v_route
    FROM trade_routes tr
    WHERE tr.id = p_route_id AND tr.player_id = v_player_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found'));
    END IF;
    
    -- Get waypoints (should be 2: start and target)
    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_start_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    LIMIT 1;
    
    SELECT rw.*, p.id as port_id, p.kind as port_kind, p.sector_id, s.number as sector_number
    INTO v_target_port
    FROM route_waypoints rw
    JOIN ports p ON rw.port_id = p.id
    JOIN sectors s ON p.sector_id = s.id
    WHERE rw.route_id = p_route_id
    ORDER BY rw.sequence_order
    OFFSET 1
    LIMIT 1;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'no_waypoints', 'message', 'Route needs 2 waypoints'));
    END IF;
    
    -- Get movement type from route (default to warp if not set)
    v_movement_type := COALESCE(v_route.movement_type, 'warp');
    v_distance := ABS(v_target_port.sector_number - v_start_port.sector_number);
    
    v_log := 'Starting trade route execution' || E'\n';
    v_log := v_log || 'Start port: Sector ' || v_start_port.sector_number || ' (' || v_start_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Target port: Sector ' || v_target_port.sector_number || ' (' || v_target_port.port_kind || ')' || E'\n';
    v_log := v_log || 'Movement type: ' || v_movement_type || E'\n';
    v_log := v_log || 'Initial state - Turns: ' || v_turns_before || ', Credits: ' || v_credits_before || E'\n';
    
    -- Calculate required turns based on movement type
    DECLARE
        v_required_turns INTEGER;
    BEGIN
        IF v_movement_type = 'warp' THEN
            v_required_turns := 3; -- 1 move + 1 trade + 1 return
        ELSE -- realspace
            v_required_turns := (v_distance * 2) + 1; -- distance turns each way + 1 trade
        END IF;
        
        IF v_player.turns < v_required_turns THEN
            RETURN json_build_object('error', json_build_object('code', 'insufficient_turns', 'message', 'Need at least ' || v_required_turns || ' turns'));
        END IF;
    END;
    
    -- Create execution record
    INSERT INTO route_executions (route_id, player_id, status, started_at)
    VALUES (p_route_id, v_player_id, 'running', now())
    RETURNING id INTO v_execution_id;
    
    -- STEP 1: Trade at start port (if player is there)
    IF v_player.current_sector = v_start_port.sector_id THEN
        v_log := v_log || 'Trading at start port...' || E'\n';
        
        SELECT game_trade_auto(p_user_id, v_start_port.port_id, p_universe_id) INTO v_trade_result;
        
        v_log := v_log || 'Start trade result: ' || v_trade_result::text || E'\n';
        
        IF (v_trade_result->>'ok')::boolean = true THEN
            v_turns_spent := v_turns_spent + 1;
            v_log := v_log || 'Start port trade successful' || E'\n';
        ELSE
            v_log := v_log || 'Start port trade failed: ' || (v_trade_result->>'message') || E'\n';
        END IF;
    ELSE
        v_log := v_log || 'Not at start port, skipping start trade' || E'\n';
    END IF;
    
    -- STEP 2: Move to target port using correct movement function
    v_log := v_log || 'Moving to target port using ' || v_movement_type || '...' || E'\n';
    
    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_target_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;
    
    v_log := v_log || 'Move result: ' || v_move_result::text || E'\n';
    
    -- Check if move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'move_failed', 'message', v_log));
    END IF;
    
    v_turns_spent := v_turns_spent + 1;
    v_log := v_log || 'Moved to target port' || E'\n';
    
    -- STEP 3: Trade at target port
    v_log := v_log || 'Trading at target port...' || E'\n';
    
    SELECT game_trade_auto(p_user_id, v_target_port.port_id, p_universe_id) INTO v_trade_result;
    
    v_log := v_log || 'Target trade result: ' || v_trade_result::text || E'\n';
    
    -- Check if trade failed (either ok=false or error field exists)
    IF (v_trade_result->>'ok')::boolean = false OR (v_trade_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Target port trade failed: ' || COALESCE(v_trade_result->>'message', v_trade_result->'error'->>'message', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'trade_failed', 'message', v_log));
    END IF;
    
    v_turns_spent := v_turns_spent + 1;
    v_log := v_log || 'Target port trade successful' || E'\n';
    
    -- STEP 4: Move back to start port using correct movement function
    v_log := v_log || 'Moving back to start port using ' || v_movement_type || '...' || E'\n';
    
    IF v_movement_type = 'warp' THEN
        SELECT game_move(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    ELSE -- realspace
        SELECT game_hyperspace(p_user_id, v_start_port.sector_number, p_universe_id) INTO v_move_result;
    END IF;
    
    v_log := v_log || 'Return move result: ' || v_move_result::text || E'\n';
    
    -- Check if return move failed (either ok=false or error field exists)
    IF (v_move_result->>'ok')::boolean = false OR (v_move_result::jsonb) ? 'error' THEN
        v_log := v_log || 'Return move failed: ' || COALESCE(v_move_result->>'message', v_move_result->>'error', 'Unknown error');
        UPDATE route_executions SET status = 'failed', error_message = v_log, completed_at = now() WHERE id = v_execution_id;
        RETURN json_build_object('error', json_build_object('code', 'return_failed', 'message', v_log));
    END IF;
    
    v_turns_spent := v_turns_spent + 1;
    v_log := v_log || 'Returned to start port' || E'\n';
    
    -- Get final player state
    SELECT turns, credits INTO v_turns_after, v_credits_after
    FROM players
    WHERE id = v_player_id;
    
    v_log := v_log || 'Final state - Turns: ' || v_turns_after || ' (was ' || v_turns_before || '), Credits: ' || v_credits_after || ' (was ' || v_credits_before || ')' || E'\n';
    v_log := v_log || 'Trade route completed! Total turns: ' || v_turns_spent || E'\n';
    
    -- Update execution record
    UPDATE route_executions 
    SET 
        status = 'completed',
        total_profit = v_total_profit,
        turns_spent = v_turns_spent,
        completed_at = now(),
        execution_data = json_build_object('log', v_log)
    WHERE id = v_execution_id;
    
    -- Update route
    UPDATE trade_routes 
    SET last_executed_at = now(), updated_at = now()
    WHERE id = p_route_id;
    
    RETURN json_build_object(
        'ok', true,
        'execution_id', v_execution_id,
        'total_profit', v_total_profit,
        'turns_spent', v_turns_spent,
        'log', v_log,
        'message', 'Trade route completed successfully'
    );
END;
$$;

-- ==============================================
-- NOTE: Additional functions needed
-- ==============================================
-- You'll also need to run the other SQL files to get all functions:
-- - game_trade, game_trade_auto (from 006_rpc_trade_by_type.sql, 013_rpc_trade_auto.sql)
-- - game_move, game_hyperspace (from 043_update_game_move_universe_aware.sql)
-- - create_trade_route, add_route_waypoint, etc. (from 047_trade_routes_rpc.sql)
-- - All other RPC functions from the remaining SQL files
