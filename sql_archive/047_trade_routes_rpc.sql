-- Trade Routes RPC Functions
-- Core functions for creating, managing, and executing trade routes

-- Create a new trade route
CREATE OR REPLACE FUNCTION create_trade_route(
    p_user_id UUID,
    p_universe_id UUID,
    p_name TEXT,
    p_description TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_route_id UUID;
    v_result JSON;
    v_route_count INTEGER;
BEGIN
    -- Get player ID
    SELECT id INTO v_player_id
    FROM players 
    WHERE user_id = p_user_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found in this universe'));
    END IF;
    
    -- Check trade route limit (10 routes per player)
    SELECT COUNT(*) INTO v_route_count
    FROM trade_routes
    WHERE player_id = v_player_id;
    
    IF v_route_count >= 10 THEN
        RETURN json_build_object('error', json_build_object('code', 'route_limit_exceeded', 'message', 'Maximum of 10 trade routes allowed per player'));
    END IF;
    
    -- Check if route name already exists for this player
    IF EXISTS(SELECT 1 FROM trade_routes WHERE player_id = v_player_id AND name = p_name) THEN
        RETURN json_build_object('error', json_build_object('code', 'name_taken', 'message', 'Route name already exists'));
    END IF;
    
    -- Create the route
    INSERT INTO trade_routes (player_id, universe_id, name, description)
    VALUES (v_player_id, p_universe_id, p_name, p_description)
    RETURNING id INTO v_route_id;
    
    RETURN json_build_object(
        'ok', true,
        'route_id', v_route_id,
        'message', 'Trade route created successfully'
    );
END;
$$;

-- Add waypoint to a route
CREATE OR REPLACE FUNCTION add_route_waypoint(
    p_user_id UUID,
    p_route_id UUID,
    p_port_id UUID,
    p_action_type TEXT,
    p_resource TEXT DEFAULT NULL,
    p_quantity INTEGER DEFAULT 0,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_route RECORD;
    v_port RECORD;
    v_next_sequence INTEGER;
    v_result JSON;
BEGIN
    -- Verify route ownership
    SELECT tr.*, p.id as player_id
    INTO v_route
    FROM trade_routes tr
    JOIN players p ON tr.player_id = p.id
    WHERE tr.id = p_route_id AND p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
    END IF;
    
    -- Verify port exists and is in the same universe
    SELECT p.*, s.universe_id
    INTO v_port
    FROM ports p
    JOIN sectors s ON p.sector_id = s.id
    WHERE p.id = p_port_id AND s.universe_id = v_route.universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'port_not_found', 'message', 'Port not found in this universe'));
    END IF;
    
    -- Validate action type and resource
    IF p_action_type NOT IN ('buy', 'sell', 'trade_auto') THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_action', 'message', 'Invalid action type'));
    END IF;
    
    IF p_action_type IN ('buy', 'sell') AND p_resource NOT IN ('ore', 'organics', 'goods', 'energy') THEN
        RETURN json_build_object('error', json_build_object('code', 'invalid_resource', 'message', 'Invalid resource type'));
    END IF;
    
    -- Get next sequence number
    SELECT COALESCE(MAX(sequence_order), 0) + 1
    INTO v_next_sequence
    FROM route_waypoints
    WHERE route_id = p_route_id;
    
    -- Add the waypoint
    INSERT INTO route_waypoints (route_id, sequence_order, port_id, action_type, resource, quantity, notes)
    VALUES (p_route_id, v_next_sequence, p_port_id, p_action_type, p_resource, p_quantity, p_notes);
    
    RETURN json_build_object(
        'ok', true,
        'waypoint_sequence', v_next_sequence,
        'message', 'Waypoint added successfully'
    );
END;
$$;

-- Get player's trade routes
CREATE OR REPLACE FUNCTION get_player_trade_routes(
    p_user_id UUID,
    p_universe_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_routes JSONB := '[]'::jsonb;
    v_route RECORD;
    v_waypoints JSONB;
BEGIN
    -- Get player ID
    SELECT id INTO v_player_id
    FROM players 
    WHERE user_id = p_user_id AND universe_id = p_universe_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'player_not_found', 'message', 'Player not found in this universe'));
    END IF;
    
    -- Get all routes for this player
    FOR v_route IN 
        SELECT tr.*, 
               COUNT(rw.id) as waypoint_count,
               MAX(rp.profit_per_turn) as current_profit_per_turn
        FROM trade_routes tr
        LEFT JOIN route_waypoints rw ON tr.id = rw.route_id
        LEFT JOIN route_profitability rp ON tr.id = rp.route_id AND rp.is_current = true
        WHERE tr.player_id = v_player_id
        GROUP BY tr.id
        ORDER BY tr.created_at DESC
    LOOP
        -- Get waypoints for this route
        SELECT jsonb_agg(
            jsonb_build_object(
                'id', rw.id,
                'sequence_order', rw.sequence_order,
                'port_id', rw.port_id,
                'action_type', rw.action_type,
                'resource', rw.resource,
                'quantity', rw.quantity,
                'notes', rw.notes,
                'port_info', jsonb_build_object(
                    'sector_number', s.number,
                    'port_kind', p.kind
                )
            ) ORDER BY rw.sequence_order
        )
        INTO v_waypoints
        FROM route_waypoints rw
        JOIN ports p ON rw.port_id = p.id
        JOIN sectors s ON p.sector_id = s.id
        WHERE rw.route_id = v_route.id;
        
        v_routes := v_routes || jsonb_build_object(
            'id', v_route.id,
            'name', v_route.name,
            'description', v_route.description,
            'is_active', v_route.is_active,
            'is_automated', v_route.is_automated,
            'max_iterations', v_route.max_iterations,
            'current_iteration', v_route.current_iteration,
            'total_profit', v_route.total_profit,
            'total_turns_spent', v_route.total_turns_spent,
            'waypoint_count', v_route.waypoint_count,
            'current_profit_per_turn', v_route.current_profit_per_turn,
            'created_at', v_route.created_at,
            'updated_at', v_route.updated_at,
            'last_executed_at', v_route.last_executed_at,
            'waypoints', COALESCE(v_waypoints, '[]'::jsonb)
        );
    END LOOP;
    
    RETURN json_build_object('ok', true, 'routes', v_routes);
END;
$$;

-- Calculate route profitability
CREATE OR REPLACE FUNCTION calculate_route_profitability(
    p_user_id UUID,
    p_route_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_route RECORD;
    v_waypoint RECORD;
    v_total_profit BIGINT := 0;
    v_total_turns INTEGER := 0;
    v_cargo_capacity INTEGER;
    v_engine_level INTEGER;
    v_current_sector INTEGER;
    v_previous_sector INTEGER;
    v_distance INTEGER;
    v_turn_cost INTEGER;
    v_profit_per_turn NUMERIC;
    v_market_conditions JSONB := '{}'::jsonb;
    v_result JSON;
BEGIN
    -- Verify route ownership
    SELECT tr.*, p.id as player_id, s.engine_lvl, s.cargo, p.current_sector
    INTO v_route
    FROM trade_routes tr
    JOIN players p ON tr.player_id = p.id
    JOIN ships s ON s.player_id = p.id
    WHERE tr.id = p_route_id AND p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
    END IF;
    
    v_cargo_capacity := v_route.cargo;
    v_engine_level := v_route.engine_lvl;
    
    -- Get current sector number
    SELECT s.number INTO v_current_sector
    FROM sectors s
    WHERE s.id = v_route.current_sector;
    
    v_previous_sector := v_current_sector;
    
    -- Calculate profitability for each waypoint
    FOR v_waypoint IN 
        SELECT rw.*, p.kind as port_kind, s.number as sector_number,
               p.price_ore, p.price_organics, p.price_goods, p.price_energy,
               p.ore as stock_ore, p.organics as stock_organics, 
               p.goods as stock_goods, p.energy as stock_energy
        FROM route_waypoints rw
        JOIN ports p ON rw.port_id = p.id
        JOIN sectors s ON p.sector_id = s.id
        WHERE rw.route_id = p_route_id
        ORDER BY rw.sequence_order
    LOOP
        -- Calculate travel cost
        v_distance := ABS(v_waypoint.sector_number - v_previous_sector);
        v_turn_cost := GREATEST(1, CEIL(v_distance::NUMERIC / GREATEST(v_engine_level, 1)));
        v_total_turns := v_total_turns + v_turn_cost;
        
        -- Calculate profit based on action type
        CASE v_waypoint.action_type
            WHEN 'buy' THEN
                -- Buying native commodity at port
                CASE v_waypoint.resource
                    WHEN 'ore' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_ore * 0.9);
                    WHEN 'organics' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_organics * 0.9);
                    WHEN 'goods' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_goods * 0.9);
                    WHEN 'energy' THEN v_total_profit := v_total_profit - (v_cargo_capacity * v_waypoint.price_energy * 0.9);
                END CASE;
            WHEN 'sell' THEN
                -- Selling non-native commodity at port
                CASE v_waypoint.resource
                    WHEN 'ore' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_ore * 1.1);
                    WHEN 'organics' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_organics * 1.1);
                    WHEN 'goods' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_goods * 1.1);
                    WHEN 'energy' THEN v_total_profit := v_total_profit + (v_cargo_capacity * v_waypoint.price_energy * 1.1);
                END CASE;
            WHEN 'trade_auto' THEN
                -- Auto-trade: sell all non-native, buy native
                -- Simplified calculation - would need more complex logic for actual implementation
                v_total_profit := v_total_profit + (v_cargo_capacity * 5); -- Placeholder
        END CASE;
        
        -- Store market conditions
        v_market_conditions := v_market_conditions || jsonb_build_object(
            'sector_' || v_waypoint.sector_number, jsonb_build_object(
                'port_kind', v_waypoint.port_kind,
                'prices', jsonb_build_object(
                    'ore', v_waypoint.price_ore,
                    'organics', v_waypoint.price_organics,
                    'goods', v_waypoint.price_goods,
                    'energy', v_waypoint.price_energy
                ),
                'stock', jsonb_build_object(
                    'ore', v_waypoint.stock_ore,
                    'organics', v_waypoint.stock_organics,
                    'goods', v_waypoint.stock_goods,
                    'energy', v_waypoint.stock_energy
                )
            )
        );
        
        v_previous_sector := v_waypoint.sector_number;
    END LOOP;
    
    -- Calculate profit per turn
    IF v_total_turns > 0 THEN
        v_profit_per_turn := v_total_profit::NUMERIC / v_total_turns;
    ELSE
        v_profit_per_turn := 0;
    END IF;
    
    -- Store profitability data
    INSERT INTO route_profitability (
        route_id, estimated_profit_per_cycle, estimated_turns_per_cycle, 
        profit_per_turn, cargo_efficiency, market_conditions
    )
    VALUES (
        p_route_id, v_total_profit, v_total_turns, 
        v_profit_per_turn, v_profit_per_turn / GREATEST(v_cargo_capacity, 1), v_market_conditions
    );
    
    -- Mark previous calculations as not current
    UPDATE route_profitability 
    SET is_current = false 
    WHERE route_id = p_route_id AND id != (SELECT id FROM route_profitability WHERE route_id = p_route_id ORDER BY calculated_at DESC LIMIT 1);
    
    RETURN json_build_object(
        'ok', true,
        'estimated_profit_per_cycle', v_total_profit,
        'estimated_turns_per_cycle', v_total_turns,
        'profit_per_turn', v_profit_per_turn,
        'cargo_efficiency', v_profit_per_turn / GREATEST(v_cargo_capacity, 1),
        'message', 'Route profitability calculated successfully'
    );
END;
$$;

-- Execute a trade route (manual or automated)
CREATE OR REPLACE FUNCTION execute_trade_route(
    p_user_id UUID,
    p_route_id UUID,
    p_max_iterations INTEGER DEFAULT 1
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_player_id UUID;
    v_route RECORD;
    v_execution_id UUID;
    v_result JSON;
BEGIN
    -- Verify route ownership and get route details
    SELECT tr.*, p.id as player_id
    INTO v_route
    FROM trade_routes tr
    JOIN players p ON tr.player_id = p.id
    WHERE tr.id = p_route_id AND p.user_id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('error', json_build_object('code', 'route_not_found', 'message', 'Route not found or access denied'));
    END IF;
    
    -- Extract player_id from the route record
    v_player_id := v_route.player_id;
    
    -- Check if route has waypoints
    IF NOT EXISTS(SELECT 1 FROM route_waypoints WHERE route_id = p_route_id) THEN
        RETURN json_build_object('error', json_build_object('code', 'no_waypoints', 'message', 'Route has no waypoints'));
    END IF;
    
    -- Create execution record
    INSERT INTO route_executions (route_id, player_id, status)
    VALUES (p_route_id, v_player_id, 'running')
    RETURNING id INTO v_execution_id;
    
    -- Update route last executed time
    UPDATE trade_routes 
    SET last_executed_at = now(), updated_at = now()
    WHERE id = p_route_id;
    
    RETURN json_build_object(
        'ok', true,
        'execution_id', v_execution_id,
        'message', 'Route execution started'
    );
END;
$$;
