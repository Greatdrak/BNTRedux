-- Trade Routes System Schema
-- Builds on existing trading system to add route planning and automation

-- Trade Routes: Saved multi-port trading sequences
CREATE TABLE IF NOT EXISTS trade_routes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
    universe_id UUID NOT NULL REFERENCES universes(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT false,
    is_automated BOOLEAN DEFAULT false,
    max_iterations INTEGER DEFAULT 0, -- 0 = infinite
    current_iteration INTEGER DEFAULT 0,
    total_profit BIGINT DEFAULT 0,
    total_turns_spent INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    last_executed_at TIMESTAMPTZ,
    UNIQUE(player_id, name)
);

-- Route Waypoints: Individual ports in a trade route
CREATE TABLE IF NOT EXISTS route_waypoints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    sequence_order INTEGER NOT NULL, -- Order in the route (1, 2, 3...)
    port_id UUID NOT NULL REFERENCES ports(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL CHECK (action_type IN ('buy', 'sell', 'trade_auto')),
    resource TEXT CHECK (resource IN ('ore', 'organics', 'goods', 'energy')),
    quantity INTEGER DEFAULT 0, -- 0 = max possible
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(route_id, sequence_order)
);

-- Route Execution Log: Track automated route runs
CREATE TABLE IF NOT EXISTS route_executions (
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
    execution_data JSONB DEFAULT '{}'::jsonb -- Store detailed execution info
);

-- Route Profitability Cache: Store calculated profit data
CREATE TABLE IF NOT EXISTS route_profitability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id UUID NOT NULL REFERENCES trade_routes(id) ON DELETE CASCADE,
    calculated_at TIMESTAMPTZ DEFAULT now(),
    estimated_profit_per_cycle BIGINT,
    estimated_turns_per_cycle INTEGER,
    profit_per_turn NUMERIC,
    cargo_efficiency NUMERIC, -- profit per cargo unit
    market_conditions JSONB DEFAULT '{}'::jsonb, -- Snapshot of prices when calculated
    is_current BOOLEAN DEFAULT true,
    UNIQUE(route_id, calculated_at)
);

-- Route Templates: Pre-built route patterns for common trade loops
CREATE TABLE IF NOT EXISTS route_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    template_data JSONB NOT NULL, -- JSON structure defining the route pattern
    difficulty_level INTEGER DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    required_engine_level INTEGER DEFAULT 1,
    required_cargo_capacity INTEGER DEFAULT 1000,
    estimated_profit_per_turn NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_trade_routes_player_universe ON trade_routes(player_id, universe_id);
CREATE INDEX IF NOT EXISTS idx_trade_routes_active ON trade_routes(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_route_waypoints_route_order ON route_waypoints(route_id, sequence_order);
CREATE INDEX IF NOT EXISTS idx_route_executions_route ON route_executions(route_id);
CREATE INDEX IF NOT EXISTS idx_route_executions_status ON route_executions(status) WHERE status = 'running';
CREATE INDEX IF NOT EXISTS idx_route_profitability_current ON route_profitability(route_id) WHERE is_current = true;

-- Function to update route statistics
CREATE OR REPLACE FUNCTION update_route_stats(p_route_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_profit BIGINT := 0;
    v_total_turns INTEGER := 0;
    v_iterations INTEGER := 0;
BEGIN
    -- Calculate total profit and turns from executions
    SELECT 
        COALESCE(SUM(total_profit), 0),
        COALESCE(SUM(turns_spent), 0),
        COUNT(*)
    INTO v_total_profit, v_total_turns, v_iterations
    FROM route_executions 
    WHERE route_id = p_route_id AND status = 'completed';
    
    -- Update route statistics
    UPDATE trade_routes 
    SET 
        total_profit = v_total_profit,
        total_turns_spent = v_total_turns,
        current_iteration = v_iterations,
        updated_at = now()
    WHERE id = p_route_id;
END;
$$;

-- Function to validate route waypoints
CREATE OR REPLACE FUNCTION validate_route_waypoints(p_route_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_waypoint_count INTEGER;
    v_sequence_gaps BOOLEAN;
BEGIN
    -- Check if route has waypoints
    SELECT COUNT(*) INTO v_waypoint_count
    FROM route_waypoints 
    WHERE route_id = p_route_id;
    
    IF v_waypoint_count = 0 THEN
        RETURN false;
    END IF;
    
    -- Check for sequence gaps
    SELECT EXISTS(
        SELECT 1 FROM (
            SELECT sequence_order, 
                   LAG(sequence_order) OVER (ORDER BY sequence_order) as prev_order
            FROM route_waypoints 
            WHERE route_id = p_route_id
        ) gaps
        WHERE sequence_order - COALESCE(prev_order, 0) > 1
    ) INTO v_sequence_gaps;
    
    RETURN NOT v_sequence_gaps;
END;
$$;
