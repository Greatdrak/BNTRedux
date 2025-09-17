-- Add Trade Route Limit (10 routes per player)
-- This script updates the create_trade_route function to enforce a 10 route limit

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
